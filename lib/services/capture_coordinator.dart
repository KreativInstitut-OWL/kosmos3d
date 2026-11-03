import 'dart:async';
import 'package:flutter/foundation.dart';

enum CapturePhase {
  idle,
  synchronizing,
  ready,
  starting,
  capturing,
  stopping,
  fault,
}

abstract class RigCamera {
  String get id;
  Future<void> configure(
    String mode,
    Map<String, String> settings,
    void Function(String) progress,
  );
  Future<void> verifyReady();
  Future<void> start();
  Future<void> stop();

  /// Photos on the card, or null when the camera cannot tell.
  Future<int?> photoCount();
}

/// Interval timing value that hands the interval to the cameras' own timers.
const cameraTimerTiming = 'Camera timer';

/// Interval timing value where the app fires and confirms every shot.
const appTiming = 'App (confirmed)';

/// Intervals the GoPro photo interval timer offers (setting 171).
const cameraTimerIntervals = [0.5, 1.0, 2.0, 3.0, 5.0, 10.0, 30.0, 60.0, 120.0];

/// Frozen rig membership, verified readiness and one owner for all transitions.
/// App-paced intervals keep camera interval Off, so every dispatch can be
/// logged. Camera-timer intervals start every camera's own timer at the same
/// moment; the photo events are then estimated from the interval.
class CaptureCoordinator extends ChangeNotifier {
  CapturePhase phase = CapturePhase.idle;
  String progress = 'Not synchronized';
  String? error;
  List<RigCamera> _rig = [];
  bool _locked = false, _active = false, _video = false, _cameraTimer = false;
  Duration? _interval;
  Timer? _timer;
  Future<void>? _stopFuture;
  int _generation = 0;

  /// Camera-timer run: first estimated shot, shots logged, card counts at start.
  DateTime? _timerStarted;
  int _timerShots = 0;
  final Map<String, int> _countAtStart = {};
  Future<void> Function(DateTime)? onPhoto;
  List<Map<String, Object>> lastDispatch = [];

  /// Start of the current Start..Stop run, logged with every photo event.
  DateTime? runStarted;
  bool get busy => _locked;
  bool get active => _active;
  bool get cameraTimer => _cameraTimer;
  List<String> get cameraIds => _rig.map((c) => c.id).toList(growable: false);
  void _state(CapturePhase state, String text) {
    phase = state;
    progress = text;
    notifyListeners();
  }

  Future<void> prepare(
    List<RigCamera> cameras,
    String mode,
    Map<String, String> settings,
  ) async {
    if (_locked || _active || _stopFuture != null) {
      throw StateError('Capture operation already in progress');
    }
    if (cameras.isEmpty) throw StateError('Connect at least one camera');
    if (mode != 'photo' && mode != 'video') {
      throw UnsupportedError('Capture mode $mode');
    }
    final intervalText = settings['Interval'] ?? 'Off';
    final seconds = intervalText == 'Off'
        ? null
        : double.tryParse(intervalText.replaceAll('s', ''));
    if (mode == 'photo' &&
        intervalText != 'Off' &&
        (seconds == null || seconds < 0.5 || !seconds.isFinite)) {
      throw ArgumentError('Invalid capture interval: $intervalText');
    }
    final cameraTimer =
        mode == 'photo' &&
        seconds != null &&
        settings['Interval Timing'] == cameraTimerTiming;
    if (cameraTimer && !cameraTimerIntervals.contains(seconds)) {
      throw ArgumentError(
        'The camera timer cannot shoot every $intervalText. '
        'Choose ${cameraTimerIntervals.map(_seconds).join(', ')} or app timing.',
      );
    }
    _locked = true;
    error = null;
    _rig = List.unmodifiable(cameras);
    _video = mode == 'video';
    _cameraTimer = cameraTimer;
    _interval = !_video && seconds != null
        ? Duration(microseconds: (seconds * 1000000).round())
        : null;
    _state(CapturePhase.synchronizing, 'Synchronizing cameras');
    try {
      for (var i = 0; i < _rig.length; i++) {
        final label = 'Camera ${i + 1}/${_rig.length}';
        await _rig[i].configure(
          mode,
          Map.unmodifiable(settings),
          (step) => _state(CapturePhase.synchronizing, '$label: $step'),
        );
      }
      for (final camera in _rig) {
        await camera.verifyReady();
      }
      _state(
        CapturePhase.ready,
        'Ready - BLE settings verified; check manual exposure and mounting',
      );
    } catch (e) {
      error = '$e';
      _state(CapturePhase.fault, error!);
      rethrow;
    } finally {
      _locked = false;
      notifyListeners();
    }
  }

  Future<void> toggle() async {
    if (_locked || _stopFuture != null) return;
    if (_active) {
      await stop();
      return;
    }
    if (phase != CapturePhase.ready) {
      throw StateError('Synchronize cameras before capture');
    }
    _locked = true;
    _active = _video || _interval != null;
    final generation = ++_generation;
    runStarted = DateTime.now().toUtc();
    _state(CapturePhase.starting, 'Checking cameras');
    try {
      if (_cameraTimer) {
        await _startCameraTimers(generation);
        return;
      }
      await _shot(generation);
      _state(
        _active ? CapturePhase.capturing : CapturePhase.ready,
        _active ? 'Capturing - tap Stop' : 'Ready',
      );
      if (_interval != null) _schedule(generation);
    } catch (e) {
      await _recover(e);
      rethrow;
    } finally {
      _locked = false;
      notifyListeners();
    }
  }

  /// [verified]: interval shots skip the pre-shot check because every
  /// photo already ends with a full readiness check of all cameras.
  Future<void> _shot(int generation, {bool verified = false}) async {
    if (!verified || _video) {
      await Future.wait(_rig.map((c) => c.verifyReady()));
    }
    if (generation != _generation) return;
    final dispatchTime = DateTime.now().toUtc();
    final clock = Stopwatch()..start();
    lastDispatch = [];
    await Future.wait(
      _rig.map((c) async {
        final record = <String, Object>{
          'cameraId': c.id,
          'dispatchOffsetUs': clock.elapsedMicroseconds,
          'exposureTimeVerified': false,
        };
        lastDispatch.add(record);
        try {
          await c.start();
          record['ackOffsetUs'] = clock.elapsedMicroseconds;
        } catch (e) {
          record['error'] = '$e';
          rethrow;
        }
      }),
    );
    if (!_video) {
      await onPhoto?.call(dispatchTime);
      await Future.wait(_rig.map((c) => c.verifyReady()));
    }
  }

  /// One shutter command to every camera; each camera then shoots on its own
  /// timer until Stop. Cameras start within the BLE ACK skew (~0.1 s).
  Future<void> _startCameraTimers(int generation) async {
    await Future.wait(_rig.map((c) => c.verifyReady()));
    if (generation != _generation) return;
    _countAtStart.clear();
    for (final c in _rig) {
      final n = await _count(c);
      if (n != null) _countAtStart[c.id] = n;
    }
    final started = DateTime.now().toUtc();
    final clock = Stopwatch()..start();
    lastDispatch = [];
    await Future.wait(
      _rig.map((c) async {
        final record = <String, Object>{
          'cameraId': c.id,
          'dispatchOffsetUs': clock.elapsedMicroseconds,
          'exposureTimeVerified': false,
          'cameraTimer': true,
        };
        lastDispatch.add(record);
        try {
          await c.start();
          record['ackOffsetUs'] = clock.elapsedMicroseconds;
        } catch (e) {
          record['error'] = '$e';
          rethrow;
        }
      }),
    );
    _state(
      CapturePhase.capturing,
      'Capturing on camera timers (${_seconds(_interval!.inMicroseconds / 1e6)}) - tap Stop',
    );
    _timerStarted = started;
    _timerShots = 0;
    Future<void> estimate() async {
      if (!_active || generation != _generation) return;
      final shot = _timerShots++;
      await onPhoto?.call(started.add(_interval! * shot));
    }

    await estimate();
    _timer = Timer.periodic(_interval!, (_) => unawaited(estimate()));
  }

  static String _seconds(double s) =>
      '${s == s.roundToDouble() ? s.round() : s}s';

  void _schedule(int generation) {
    if (!_active || generation != _generation) return;
    // Fixed delay after readiness: slow processing never builds a shutter queue.
    _timer = Timer(_interval!, () async {
      if (!_active || generation != _generation || _locked) return;
      _locked = true;
      try {
        await _shot(generation, verified: true);
        _schedule(generation);
      } catch (e) {
        await _recover(e);
      } finally {
        _locked = false;
        notifyListeners();
      }
    });
  }

  Future<void> _recover(Object cause) async {
    _timer?.cancel();
    _generation++;
    final failures = await _stopEveryCamera();
    _active = failures.isNotEmpty;
    error =
        '$cause${failures.isEmpty ? '' : '; stop unconfirmed: ${failures.join(', ')}'}';
    _state(CapturePhase.fault, error!);
  }

  Future<List<String>> _stopEveryCamera() async {
    final failures = <String>[];
    await Future.wait(
      _rig.map((c) async {
        try {
          await c.stop();
        } catch (e) {
          failures.add('${c.id}: $e');
        }
      }),
    );
    return failures;
  }

  Future<void> stop() => _stopFuture ??= _stop().whenComplete(() {
    _stopFuture = null;
  });

  Future<void> _stop() async {
    _active = false;
    _timer?.cancel();
    _generation++;
    while (_locked) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    _locked = true;
    _state(CapturePhase.stopping, 'Stopping all cameras');
    try {
      final failures = await _stopEveryCamera();
      if (failures.isNotEmpty) {
        _active = true;
        throw StateError('Stop unconfirmed: ${failures.join(', ')}');
      }
      await _logShotsBeforeStop();
      _state(
        error == null ? CapturePhase.ready : CapturePhase.fault,
        error == null ? 'Stopped' : 'Stopped - synchronize again',
      );
    } catch (e) {
      error = '$e';
      _state(CapturePhase.fault, error!);
      rethrow;
    } finally {
      _locked = false;
      notifyListeners();
    }
  }

  static Future<int?> _count(RigCamera c) async {
    try {
      return await c.photoCount();
    } catch (_) {
      return null;
    }
  }

  /// The camera timers keep shooting until the Stop command arrives, often one
  /// shot after the phone's last estimate. Log the shots the cards counted.
  Future<void> _logShotsBeforeStop() async {
    final started = _timerStarted;
    _timerStarted = null;
    if (!_cameraTimer || started == null || _countAtStart.isEmpty) return;
    var taken = 0;
    for (final c in _rig) {
      final before = _countAtStart[c.id];
      final after = await _count(c);
      if (before != null && after != null && after - before > taken) {
        taken = after - before;
      }
    }
    while (_timerShots < taken) {
      await onPhoto?.call(started.add(_interval! * _timerShots++));
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

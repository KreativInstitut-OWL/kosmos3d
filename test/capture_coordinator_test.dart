import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:kosmos3d/services/capture_coordinator.dart';

class FakeCamera implements RigCamera {
  FakeCamera(this.id, this.events);
  @override
  final String id;
  final List<String> events;
  Completer<void>? configureGate, startGate, readyGate;
  bool failStart = false, failStop = false, failReady = false;
  @override
  Future<void> configure(
    String mode,
    Map<String, String> settings,
    void Function(String) progress,
  ) async {
    events.add('$id:configure');
    progress('setting $mode');
    await configureGate?.future;
  }

  @override
  Future<void> verifyReady() async {
    events.add('$id:ready');
    await readyGate?.future;
    if (failReady) throw StateError('wrong mode');
  }

  @override
  Future<void> start() async {
    events.add('$id:start');
    await startGate?.future;
    if (failStart) throw StateError('start rejected');
  }

  @override
  Future<void> stop() async {
    events.add('$id:stop');
    if (failStop) throw StateError('stop rejected');
  }

  int? photos;
  @override
  Future<int?> photoCount() async => photos;
}

void main() {
  test(
    'configuration is sequential and readiness waits for every camera',
    () async {
      final events = <String>[];
      final a = FakeCamera('a', events)..configureGate = Completer<void>();
      final b = FakeCamera('b', events);
      final rig = CaptureCoordinator();
      addTearDown(rig.dispose);
      final pending = rig.prepare([a, b], 'photo', {});
      expect(events, ['a:configure']);
      expect(rig.busy, isTrue);
      await expectLater(rig.prepare([a, b], 'photo', {}), throwsStateError);
      a.configureGate!.complete();
      await pending;
      expect(events, ['a:configure', 'b:configure', 'a:ready', 'b:ready']);
      expect(rig.phase, CapturePhase.ready);
    },
  );
  test(
    'double tap dispatches a single shot and no leading extra shutter',
    () async {
      final events = <String>[];
      final a = FakeCamera('a', events)..startGate = Completer<void>();
      final rig = CaptureCoordinator();
      addTearDown(rig.dispose);
      await rig.prepare([a], 'photo', {});
      events.clear();
      final first = rig.toggle();
      await Future<void>.delayed(Duration.zero);
      await rig.toggle();
      expect(events.where((e) => e == 'a:start'), hasLength(1));
      a.startGate!.complete();
      await first;
      expect(rig.active, isFalse);
      expect(rig.phase, CapturePhase.ready);
    },
  );
  test('video start/stop never starts a new exposure on Stop', () async {
    final events = <String>[];
    final rig = CaptureCoordinator();
    addTearDown(rig.dispose);
    await rig.prepare(
      [FakeCamera('a', events), FakeCamera('b', events)],
      'video',
      {},
    );
    await rig.toggle();
    expect(rig.active, isTrue);
    await rig.toggle();
    expect(events.where((e) => e.endsWith(':start')), hasLength(2));
    expect(events.where((e) => e.endsWith(':stop')), hasLength(2));
    expect(rig.active, isFalse);
  });
  test('partial start stops every camera and retains fault', () async {
    final events = <String>[];
    final rig = CaptureCoordinator();
    addTearDown(rig.dispose);
    await rig.prepare(
      [FakeCamera('a', events), FakeCamera('b', events)..failStart = true],
      'video',
      {},
    );
    await expectLater(rig.toggle(), throwsStateError);
    expect(events, containsAll(['a:stop', 'b:stop']));
    expect(rig.phase, CapturePhase.fault);
    expect(rig.active, isFalse);
  });
  test('uncertain stop retains a recovery Stop action', () async {
    final events = <String>[];
    final a = FakeCamera('a', events)..failStop = true;
    final rig = CaptureCoordinator();
    addTearDown(rig.dispose);
    await rig.prepare([a], 'video', {});
    await rig.toggle();
    await expectLater(rig.stop(), throwsStateError);
    expect(rig.active, isTrue);
    a.failStop = false;
    await rig.stop();
    expect(rig.active, isFalse);
    expect(rig.phase, CapturePhase.fault);
  });
  test('interval repeats single shots, Stop cancels future shots', () async {
    final events = <String>[];
    final rig = CaptureCoordinator();
    addTearDown(rig.dispose);
    var logs = 0;
    rig.onPhoto = (_) async {
      logs++;
    };
    await rig.prepare([FakeCamera('a', events)], 'photo', {'Interval': '0.5s'});
    await rig.toggle();
    expect(logs, 1);
    await Future<void>.delayed(const Duration(milliseconds: 550));
    expect(logs, 2);
    await rig.stop();
    await Future<void>.delayed(const Duration(milliseconds: 550));
    expect(logs, 2);
    expect(rig.active, isFalse);
  });
  test('changed camera mode blocks all shutters', () async {
    final events = <String>[];
    final a = FakeCamera('a', events);
    final rig = CaptureCoordinator();
    addTearDown(rig.dispose);
    await rig.prepare([a], 'photo', {});
    a.failReady = true;
    await expectLater(rig.toggle(), throwsStateError);
    expect(events.where((e) => e.endsWith(':start')), isEmpty);
  });
  test('empty rig and invalid interval fail before any command', () async {
    final rig = CaptureCoordinator();
    addTearDown(rig.dispose);
    await expectLater(rig.prepare([], 'photo', {}), throwsStateError);
    final events = <String>[];
    await expectLater(
      rig.prepare([FakeCamera('a', events)], 'photo', {'Interval': 'oops'}),
      throwsArgumentError,
    );
    expect(events, isEmpty);
  });
  test('Stop during preflight cancels the undispatched shutter', () async {
    final events = <String>[];
    final a = FakeCamera('a', events);
    final rig = CaptureCoordinator();
    addTearDown(rig.dispose);
    await rig.prepare([a], 'photo', {'Interval': '0.5s'});
    a.readyGate = Completer<void>();
    final start = rig.toggle();
    await Future<void>.delayed(Duration.zero);
    final stop = rig.stop();
    a.readyGate!.complete();
    await Future.wait([start, stop]);
    expect(events.where((e) => e.endsWith(':start')), isEmpty);
    expect(events.where((e) => e.endsWith(':stop')), hasLength(1));
    expect(rig.active, isFalse);
  });
  test(
    'pending Stop blocks restart and rig replacement after preflight',
    () async {
      final events = <String>[];
      final a = FakeCamera('a', events);
      final rig = CaptureCoordinator();
      addTearDown(rig.dispose);
      await rig.prepare([a], 'photo', {'Interval': '0.5s'});
      a.readyGate = Completer<void>();
      final start = rig.toggle();
      final stop = rig.stop();
      a.readyGate!.complete();
      await start;
      // Start has released its lock, but Stop is still waiting to acquire it.
      await rig.toggle();
      await expectLater(
        rig.prepare([FakeCamera('b', events)], 'video', {}),
        throwsStateError,
      );
      await stop;
      expect(events.where((e) => e.endsWith(':start')), isEmpty);
      expect(events.where((e) => e.endsWith(':stop')), ['a:stop']);
      expect(rig.cameraIds, ['a']);
    },
  );

  test(
    'camera timer starts every camera once and estimates photos until Stop',
    () async {
      final events = <String>[];
      final a = FakeCamera('a', events);
      final b = FakeCamera('b', events);
      final rig = CaptureCoordinator();
      addTearDown(rig.dispose);
      final photos = <DateTime>[];
      rig.onPhoto = (t) async => photos.add(t);
      await rig.prepare(
        [a, b],
        'photo',
        {'Interval': '0.5s', 'Interval Timing': cameraTimerTiming},
      );
      expect(rig.cameraTimer, isTrue);
      events.clear();
      await rig.toggle();
      expect(rig.phase, CapturePhase.capturing);
      await Future<void>.delayed(const Duration(milliseconds: 1150));
      await rig.stop();
      expect(events.where((e) => e.endsWith(':start')), hasLength(2));
      expect(events.where((e) => e.endsWith(':stop')), hasLength(2));
      expect(photos.length, 3);
      expect(photos[2].difference(photos[0]), const Duration(seconds: 1));
      expect(rig.lastDispatch.every((d) => d['cameraTimer'] == true), isTrue);
      final count = photos.length;
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(photos.length, count);
    },
  );
  test('camera timer logs the shot the cameras took before Stop', () async {
    final a = FakeCamera('a', [])..photos = 10;
    final b = FakeCamera('b', [])..photos = 4;
    final rig = CaptureCoordinator();
    addTearDown(rig.dispose);
    final photos = <DateTime>[];
    rig.onPhoto = (t) async => photos.add(t);
    await rig.prepare(
      [a, b],
      'photo',
      {'Interval': '0.5s', 'Interval Timing': cameraTimerTiming},
    );
    await rig.toggle();
    await Future<void>.delayed(const Duration(milliseconds: 1150));
    a.photos = 14;
    b.photos = 8;
    await rig.stop();
    expect(photos.length, 4);
    expect(photos[3].difference(photos[0]), const Duration(milliseconds: 1500));
  });
  test('camera timer refuses intervals the cameras cannot run', () async {
    final rig = CaptureCoordinator();
    addTearDown(rig.dispose);
    await expectLater(
      rig.prepare(
        [FakeCamera('a', [])],
        'photo',
        {'Interval': '1.5s', 'Interval Timing': cameraTimerTiming},
      ),
      throwsArgumentError,
    );
  });
}

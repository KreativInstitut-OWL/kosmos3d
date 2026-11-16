import '../l10n/app_text.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/capture_coordinator.dart';
import '../services/gopro_service.dart';

/// One real MPEG-TS/UDP preview at a time. LIVE requires a decoded first frame.
class CameraLiveMonitor extends StatefulWidget {
  final VoidCallback? onClose;

  /// Camera to preselect (and start right away).
  final String? initialId;
  const CameraLiveMonitor({super.key, this.onClose, this.initialId});
  @override
  State<CameraLiveMonitor> createState() => _CameraLiveMonitorState();
}

class _CameraLiveMonitorState extends State<CameraLiveMonitor>
    with WidgetsBindingObserver {
  GoProService? _service;
  late String? _selected = widget.initialId;
  String? _playingId;
  String _status = 'Choose a camera to frame your shot.';
  bool _showPlayer = false, _busy = false, _live = false;
  Timer? _poll;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final first = _service == null;
    _service = context.read<GoProService>();
    if (first && widget.initialId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _start());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    final id = _playingId;
    if (id != null) unawaited(_service!.stopLiveStream(id));
    super.dispose();
  }

  Future<void> _stop() async {
    _poll?.cancel();
    final id = _playingId;
    if (mounted) {
      setState(() {
        _showPlayer = false;
        _live = false;
        _busy = true;
      });
    }
    final stopped = id == null || await _service!.stopLiveStream(id);
    if (stopped) _playingId = null;
    if (mounted) {
      setState(() {
        _busy = false;
        _status = stopped
            ? 'Preview stopped.'
            : 'Stop was not confirmed. Reconnect Wi-Fi and retry Stop.';
      });
    }
  }

  Future<void> _start() async {
    if (_busy || _selected == null) return;
    if (!Platform.isAndroid) {
      setState(
        () =>
            _status = 'Live video decoding is currently available on Android.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _live = false;
      _status = 'Opening video receiver…';
    });
    try {
      if (_service!.previewCameraId != null) await _service!.stopAllPreviews();
      final id = _selected!;
      final joined = _service!.devices.any(
        (c) => c.id == id && c.isWifiConnected && c.wifiIpAddress != null,
      );
      if (!joined) {
        // The preview only runs over the camera's own Wi-Fi: join it first
        // (the same automatic join the import uses).
        setState(
          () => _status =
              'Joining ${_service!.nameOf(id)} Wi-Fi… approve the prompt if asked',
        );
        await _service!.joinCameraWifi(id);
      }
      if (!mounted) return;
      _playingId = _selected;
      setState(() {
        _showPlayer = true;
        _status = 'Connecting to camera…';
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = describeError(e);
        });
      }
    }
  }

  Future<void> _receiverReady(int viewId) async {
    if (!mounted || _playingId == null) return;
    final id = _playingId!;
    try {
      await _service!.startLiveStream(id);
      if (!mounted || !_showPlayer) {
        await _service!.stopLiveStream(id);
        return;
      }
      final channel = MethodChannel('kosmos/preview/$viewId');
      var polling = false;
      _poll = Timer.periodic(const Duration(milliseconds: 750), (_) async {
        if (polling || !mounted) return;
        polling = true;
        try {
          final result = await channel.invokeMapMethod<String, dynamic>(
            'status',
          );
          if (!mounted) return;
          setState(() {
            _live = result?['firstFrame'] == true && result?['playing'] == true;
            _status = result?['error'] != null
                ? 'Decoder: ${result!['error']}'
                : _live
                ? 'Live video · Wi-Fi'
                : 'Waiting for video frames… Check camera Wi-Fi.';
          });
        } on PlatformException catch (e) {
          if (mounted) {
            setState(() {
              _live = false;
              _status = 'Preview unavailable: ${e.message}';
            });
          }
        } finally {
          polling = false;
        }
      });
      setState(() {
        _busy = false;
        _status = 'Waiting for video frames…';
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = '$e';
          _showPlayer = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<GoProService>();
    final cameras = service.devices.where((c) => c.isConnected).toList();
    if (!cameras.any((c) => c.id == _selected)) {
      _selected = cameras.isEmpty ? null : cameras.first.id;
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF141816),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(
                Icons.videocam_outlined,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: AppText(
                  'Viewfinder',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (widget.onClose != null)
                IconButton(
                  onPressed: () async {
                    await _stop();
                    widget.onClose?.call();
                  },
                  tooltip: 'Close preview',
                  icon: const Icon(Icons.close, color: Colors.white70),
                ),
            ],
          ),
          if (cameras.isNotEmpty)
            DropdownButton<String>(
              value: _selected,
              isExpanded: true,
              dropdownColor: const Color(0xFF141816),
              style: const TextStyle(color: Colors.white),
              items: cameras
                  .map(
                    (c) => DropdownMenuItem(
                      value: c.id,
                      child: AppText(c.displayName),
                    ),
                  )
                  .toList(),
              onChanged: _busy
                  ? null
                  : (v) async {
                      if (v == null || v == _selected) return;
                      // Switch camera: stop this stream, join the other.
                      if (_showPlayer) await _stop();
                      if (!mounted) return;
                      setState(() => _selected = v);
                      await _start();
                    },
            ),
          AspectRatio(
            aspectRatio: 16 / 9,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const ColoredBox(color: Colors.black),
                  if (_showPlayer && Platform.isAndroid)
                    AndroidView(
                      viewType: 'kosmos/gopro_preview',
                      onPlatformViewCreated: _receiverReady,
                      creationParams: const {},
                      creationParamsCodec: const StandardMessageCodec(),
                    ),
                  if (!_showPlayer)
                    const Center(
                      child: Icon(
                        Icons.videocam_outlined,
                        color: Colors.white24,
                        size: 48,
                      ),
                    ),
                  if (_live)
                    Positioned(
                      left: 10,
                      top: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const AppText(
                          '● LIVE',
                          style: TextStyle(
                            color: Color(0xFF55FC27),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          AppText(
            cameras.isEmpty
                ? 'Connect a GoPro in Cameras to use the viewfinder.'
                : _status,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed:
                      _busy ||
                          cameras.isEmpty ||
                          service.capture.active ||
                          service.capture.busy
                      ? null
                      : _start,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow),
                  label: const AppText('Start preview'),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: _playingId == null || _busy ? null : _stop,
                child: const AppText('Stop'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const AppText(
            'One camera over Wi-Fi. Preview stops before capture; model and firmware support varies.',
            style: TextStyle(color: Colors.white54, fontSize: 11),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

import '../l10n/app_text.dart';
import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import '../models/scan_project.dart';
import '../models/capture_point.dart';
import '../providers/settings_provider.dart';
import '../services/gopro_service.dart';
import '../services/capture_coordinator.dart';
import '../services/project_service.dart';
import '../services/trajectory_service.dart';
import '../services/orientation_service.dart';
import '../widgets/gopro_media_transfer_dialog.dart';

import '../widgets/camera_live_monitor.dart';
import 'point_cloud_preview.dart';
import '../services/lidar_service.dart';
import '../widgets/measured_cloud_view.dart';
import '../widgets/point_cloud_coverage_visualizer.dart';

/// The live capture session screen with coverage heatmap and 3D point cloud.
class CaptureSessionScreen extends StatefulWidget {
  final ScanProject project;
  final bool camerasPrepared;

  const CaptureSessionScreen({
    super.key,
    required this.project,
    this.camerasPrepared = false,
  });

  @override
  State<CaptureSessionScreen> createState() => _CaptureSessionScreenState();
}

class _CaptureSessionScreenState extends State<CaptureSessionScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late ScanProject _project;
  late GoProService _goPro;
  late OrientationService _orientation;
  late TrajectoryService _trajectory;
  late ProjectService _projects;
  late LidarService _lidar;
  bool _ending = false;
  bool _isPreparing = false;
  bool _allowPop = false;
  bool get _isCapturing => _goPro.capture.busy || _isPreparing;
  int _sessionCaptureCount = 0;
  final Stopwatch _sessionTimer = Stopwatch();
  Timer? _uiTimer;
  bool _showLiveMonitor = false;

  // Coverage & Spatial tracking
  final List<CapturePoint> _capturePoints = [];
  Position? _currentPosition;

  // Quality scoring
  double _qualityScore = 0;

  // Animations
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late AnimationController _flashController;
  late Animation<double> _flashAnimation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _project = widget.project;
    _goPro = context.read<GoProService>();
    _orientation = context.read<OrientationService>();
    _trajectory = context.read<TrajectoryService>();
    _projects = context.read<ProjectService>();
    _lidar = context.read<LidarService>();
    _goPro.capture.onPhoto = _recordPhoto;

    _sessionCaptureCount = _project.captureCount;
    _sessionTimer.start();

    _uiTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.06).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _flashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _flashAnimation = Tween<double>(
      begin: 0.0,
      end: 0.5,
    ).animate(CurvedAnimation(parent: _flashController, curve: Curves.easeOut));

    _initSensors();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      _orientation.start();
      final settings = context.read<SettingsProvider>();
      _trajectory.configure(
        sensorRateMs: settings.sensorRate,
        gpsRateSec: settings.gpsRate,
        recordBarometer: settings.recordBarometer,
      );
      final sessionDocs = await getApplicationDocumentsDirectory();
      if (!mounted) return;
      try {
        await _trajectory.startRecording(
          outputDirectory:
              '${sessionDocs.path}/kosmos3d_projects/${_project.id}/sensors',
        );
      } catch (e) {
        _showError('Sensor recording failed: $e');
      }
      if (!mounted) {
        await _trajectory.stopRecording();
        return;
      }
      await _lidar.checkAvailability();
      if (mounted && settings.coverageVisualizer && _lidar.isAvailable) {
        final docs = await getApplicationDocumentsDirectory();
        if (mounted) {
          await _lidar.startCapture(
            outputDir: '${docs.path}/kosmos3d_projects/${_project.id}/depth',
          );
        }
      }
      if (!mounted) return;
      // New projects arrive already prepared. Resumed projects must synchronize.
      if (!widget.camerasPrepared ||
          _goPro.capture.phase != CapturePhase.ready) {
        await _prepare();
      }
    });
  }

  Future<void> _prepare() async {
    if (_isPreparing) return;
    setState(() => _isPreparing = true);
    try {
      await _goPro.prepareCapture(
        _project.captureMode,
        _project.cameraSettings,
      );
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _isPreparing = false);
    }
  }

  Future<void> _reconnectAndStop() async {
    if (_isPreparing) return;
    setState(() => _isPreparing = true);
    final failures = <String>[];
    try {
      for (final id in _goPro.capture.cameraIds) {
        try {
          await _goPro.disconnectDevice(id);
          await _goPro.connectToDevice(id);
        } catch (e) {
          failures.add('$id: $e');
        }
      }
      await _goPro.capture.stop();
      if (failures.isNotEmpty) _showError(failures.join('; '));
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _isPreparing = false);
    }
  }

  void _showError(Object error) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: AppText('$error'), backgroundColor: Colors.redAccent),
      );
    }
  }

  Future<void> _initSensors() async {
    // GPS
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.whileInUse ||
          perm == LocationPermission.always) {
        _currentPosition = await Geolocator.getCurrentPosition();
      }
    } catch (e) {
      debugPrint("GPS init error: $e");
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if ((state == AppLifecycleState.paused ||
            state == AppLifecycleState.detached) &&
        _goPro.capture.active) {
      unawaited(
        _goPro.capture.stop().catchError((Object e) {
          _showError(e);
        }),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _uiTimer?.cancel();
    _sessionTimer.stop();
    _pulseController.dispose();
    _flashController.dispose();
    _goPro.capture.onPhoto = null;
    _orientation.stop();
    _trajectory.stopRecording();
    unawaited(_lidar.stopCapture());
    super.dispose();
  }

  String get _elapsedTime {
    final elapsed = _sessionTimer.elapsed;
    final m = elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = elapsed.inHours;
    if (h > 0) return '$h:$m:$s';
    return '$m:$s';
  }

  bool get _isRecordingContinuous => _goPro.capture.active;

  Future<void> _triggerCapture() async {
    if (_ending || _isPreparing) return;
    try {
      if (_goPro.capture.active) {
        await _goPro.capture.stop();
      } else {
        await _goPro.stopAllPreviews();
        if (mounted) setState(() => _showLiveMonitor = false);
        await _goPro.capture.toggle();
      }
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _recordPhoto(DateTime dispatchTime) async {
    _currentPosition = _trajectory.latestPosition;
    final heading = _orientation.heading;
    final pitch = _orientation.pitch;
    final roll = _orientation.roll;
    _capturePoints.add(
      CapturePoint(
        latitude: _currentPosition?.latitude ?? 0,
        longitude: _currentPosition?.longitude ?? 0,
        altitude: _currentPosition?.altitude ?? 0,
        heading: heading,
        pitch: pitch,
        roll: roll,
        timestamp: dispatchTime,
      ),
    );
    _trajectory.recordCapturePoint(
      _sessionCaptureCount,
      timestamp: dispatchTime,
      heading: heading,
      pitch: pitch,
      roll: roll,
      quaternion: _orientation.quaternion,
    );
    _sessionCaptureCount++;
    _project.captureCount = _sessionCaptureCount;
    _qualityScore = _calculateQualityScore();
    await _projects.updateProject(_project);
    final captures = await _projects.getProjectCapturesPath(_project.id);
    final event = <String, dynamic>{
      ..._trajectory.points.last.toJson(),
      'event_type': _goPro.capture.cameraTimer
          ? 'estimated_camera_timer_shot'
          : 'acknowledged_shutter_dispatch',
      'exposure_timestamp_verified': false,
      'camera_ids': _goPro.capture.cameraIds,
      'run_started_utc': _goPro.capture.runStarted?.toIso8601String(),
      'camera_dispatch_timing': _goPro.capture.lastDispatch,
      'orientation_valid': _orientation.hasSample,
      'orientation_sample_utc': _orientation.sampleTime
          ?.toUtc()
          .toIso8601String(),
    };
    await File('$captures/../shutter_events.jsonl').writeAsString(
      '${jsonEncode(event)}\n',
      mode: FileMode.append,
      flush: true,
    );
    if (mounted) {
      setState(() {});
      HapticFeedback.lightImpact();
      _flashController.forward().then((_) {
        if (mounted) _flashController.reverse();
      });
    }
  }

  Future<void> _syncHotspotCaptures() async {
    if (_goPro.capture.active || _isCapturing) {
      _showError('Stop capture before transferring media');
      return;
    }
    final root = await getApplicationDocumentsDirectory();
    if (!mounted) return;
    await GoProMediaTransferDialog.show(
      context,
      projectCapturesPath:
          '${root.path}/kosmos3d_projects/${_project.id}/captures',
    );
  }

  Future<void> _endSession() async {
    if (_ending || _isPreparing) return;
    _ending = true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const AppText(
          'End Session?',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppText(
              '$_sessionCaptureCount frames captured.\nProject will be saved.',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(
                Icons.wifi_tethering,
                size: 16,
                color: Colors.lightBlueAccent,
              ),
              label: const AppText(
                'Import camera originals',
                style: TextStyle(color: Colors.lightBlueAccent, fontSize: 12),
              ),
              onPressed: () {
                Navigator.pop(ctx, false);
                _syncHotspotCaptures();
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const AppText('Continue'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: AppText(
              'End Session',
              style: TextStyle(color: Theme.of(context).primaryColor),
            ),
          ),
        ],
      ),
    );

    try {
      if (confirmed == true && mounted) {
        if (_goPro.capture.active) await _goPro.capture.stop();
        await _lidar.stopCapture();
        if (_lidar.depthFrameCount > 0) await _lidar.exportPointCloud();
        await _trajectory.stopRecording();
        _sessionTimer.stop();
        if (mounted) {
          setState(() => _allowPop = true);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) Navigator.pop(context);
          });
        }
      }
    } catch (e) {
      _showError(e);
    } finally {
      _ending = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final goPro = context.watch<GoProService>();
    final connectedCams = goPro.devices.where((d) => d.isConnected).toList();
    final screenSize = MediaQuery.of(context).size;
    final primaryColor = Theme.of(context).primaryColor;

    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _endSession();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A0A),
        body: Stack(
          children: [
            SafeArea(
              child: Column(
                children: [
                  // ─── Top Bar ───
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.close,
                            color: Colors.white70,
                            size: 22,
                          ),
                          onPressed: _endSession,
                        ),
                        Expanded(
                          child: AppText(
                            _project.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            _showLiveMonitor
                                ? Icons.view_in_ar
                                : Icons.videocam,
                            color: _showLiveMonitor
                                ? Colors.redAccent
                                : Colors.white70,
                            size: 20,
                          ),
                          tooltip: _showLiveMonitor
                              ? 'Show 3D Scanner HUD'
                              : 'Live Camera Viewfinder',
                          onPressed: () => setState(
                            () => _showLiveMonitor = !_showLiveMonitor,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.wifi_tethering,
                            color: Colors.lightBlueAccent,
                            size: 20,
                          ),
                          tooltip: 'Import from cameras',
                          onPressed: _syncHotspotCaptures,
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: AppText(
                            _elapsedTime,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontFamily: 'monospace',
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ─── Camera Status Strip ───
                  SizedBox(
                    height: 50,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: connectedCams.length,
                      itemBuilder: (context, index) {
                        final cam = connectedCams[index];
                        return Container(
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: primaryColor.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.camera_alt,
                                size: 14,
                                color: primaryColor,
                              ),
                              const SizedBox(width: 6),
                              AppText(
                                cam.name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                ),
                              ),
                              const SizedBox(width: 6),
                              AppText(
                                '${cam.batteryLevel}%',
                                style: TextStyle(
                                  color: cam.batteryLevel > 20
                                      ? Colors.white54
                                      : Colors.redAccent,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 8),

                  // ─── Live Viewfinder or 3D SLAM Visualizer ───
                  Expanded(
                    flex: 3,
                    child: _showLiveMonitor
                        ? Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: CameraLiveMonitor(
                              onClose: () =>
                                  setState(() => _showLiveMonitor = false),
                            ),
                          )
                        : _buildCoverageWidget(primaryColor),
                  ),

                  // ─── AI Capture Hint ───
                  if (_capturePoints.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 4,
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: _coveragePercentage >= 90
                              ? primaryColor.withValues(alpha: 0.15)
                              : Colors.orange.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _coveragePercentage >= 90
                                  ? Icons.check_circle
                                  : Icons.assistant_navigation,
                              size: 16,
                              color: _coveragePercentage >= 90
                                  ? primaryColor
                                  : Colors.orange,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: AppText(
                                _getAiHint(),
                                style: TextStyle(
                                  color: _coveragePercentage >= 90
                                      ? primaryColor
                                      : Colors.orange,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // ─── Capture Counter ───
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AppText(
                          '$_sessionCaptureCount',
                          style: TextStyle(
                            color: primaryColor,
                            fontSize: 48,
                            fontWeight: FontWeight.w200,
                            fontFamily: 'monospace',
                          ),
                        ),
                        const SizedBox(width: 8),
                        AppText(
                          'SHUTTER EVENTS',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.4),
                            fontSize: 12,
                            letterSpacing: 2,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ─── CAPTURE BUTTON ───
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: AnimatedBuilder(
                      animation: _pulseAnimation,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: _isCapturing ? 0.92 : _pulseAnimation.value,
                          child: GestureDetector(
                            onTap: (_isCapturing && !_isRecordingContinuous)
                                ? null
                                : _triggerCapture,
                            child: Container(
                              width: screenSize.width * 0.28,
                              height: screenSize.width * 0.28,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  colors: _isRecordingContinuous
                                      ? [Colors.redAccent, Colors.red]
                                      : [
                                          primaryColor,
                                          primaryColor.withValues(alpha: 0.7),
                                        ],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color:
                                        (_isRecordingContinuous
                                                ? Colors.red
                                                : primaryColor)
                                            .withValues(alpha: 0.35),
                                    blurRadius: 25,
                                    spreadRadius: 6,
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Icon(
                                  _isRecordingContinuous
                                      ? Icons.stop
                                      : (_project.captureMode == 'video'
                                            ? Icons.videocam
                                            : Icons.camera_alt),
                                  size: 36,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: AppText(
                      _goPro.capture.progress,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _goPro.capture.error == null
                            ? Colors.white70
                            : Colors.redAccent,
                      ),
                    ),
                  ),
                  if (_goPro.capture.phase == CapturePhase.fault &&
                      _goPro.capture.active)
                    TextButton(
                      onPressed: _isPreparing ? null : _reconnectAndStop,
                      child: const AppText('Reconnect cameras and retry Stop'),
                    ),
                  if (_goPro.capture.phase == CapturePhase.fault &&
                      !_goPro.capture.active)
                    TextButton(
                      onPressed: _isCapturing ? null : _prepare,
                      child: const AppText('Synchronize again'),
                    ),
                  if ((_project.cameraSettings['Interval'] ?? 'Off') != 'Off')
                    AppText(
                      _goPro.capture.cameraTimer
                          ? 'Camera timers: photo times in the log are estimated from the interval.'
                          : 'Interval is a minimum delay after processing; timing may vary.',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                      ),
                    ),

                  // ─── Bottom Info ───
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 8,
                    ),
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildBottomStat(
                          Icons.camera_alt,
                          '${connectedCams.length}',
                          'Cams',
                        ),
                        _buildBottomStat(
                          Icons.aspect_ratio,
                          _project.captureMode == 'video'
                              ? _project.cameraSettings['Resolution'] ?? '4K'
                              : _project.cameraSettings['Lens'] ?? 'Linear',
                          _project.captureMode == 'video' ? 'Res' : 'Lens',
                        ),
                        _buildBottomStat(
                          Icons.explore,
                          '${context.watch<OrientationService>().heading.toInt()}°',
                          'Heading',
                        ),
                        _buildBottomStat(
                          _coveragePercentage > 80
                              ? Icons.check_circle
                              : Icons.pie_chart,
                          '${_coveragePercentage.toInt()}%',
                          'Heading coverage',
                        ),
                        _buildBottomStat(
                          Icons.star,
                          '${_qualityScore.toInt()}',
                          'Score',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Flash overlay
            AnimatedBuilder(
              animation: _flashAnimation,
              builder: (context, child) {
                return _flashAnimation.value > 0
                    ? Container(
                        color: Colors.white.withValues(
                          alpha: _flashAnimation.value,
                        ),
                      )
                    : const SizedBox.shrink();
              },
            ),
          ],
        ),
      ),
    );
  }

  // ─── Coverage Visualization ─────────────────────────────────

  /// Calculate coverage as percentage of 360° that has been covered
  double get _coveragePercentage {
    if (_capturePoints.isEmpty) return 0;
    // Divide 360° into 36 sectors of 10° each
    final sectors = List<bool>.filled(36, false);
    for (final p in _capturePoints) {
      final sector = (p.heading / 10).floor() % 36;
      sectors[sector] = true;
      // Also mark adjacent sectors (camera has field of view)
      sectors[(sector + 1) % 36] = true;
      sectors[(sector - 1 + 36) % 36] = true;
    }
    return (sectors.where((s) => s).length / 36) * 100;
  }

  Widget _buildCoverageWidget(Color primaryColor) {
    final settings = context.watch<SettingsProvider>();
    final lidar = context.watch<LidarService>();
    if (!settings.coverageVisualizer) {
      return Center(child: AppText(settings.translate('coverage_disabled')));
    }
    if (lidar.isAvailable) return const MeasuredCloudView();
    // No LiDAR: interactive pose/coverage view from GPS + phone orientation.
    final orientation = context.watch<OrientationService>();
    final speed = context.watch<TrajectoryService>().latestPosition?.speed ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Stack(
        children: [
          PointCloudCoverageVisualizer(
            capturePoints: _capturePoints,
            currentHeading: orientation.heading,
            currentPitch: orientation.pitch,
            currentRoll: orientation.roll,
            primaryColor: primaryColor,
            coveragePercentage: _coveragePercentage,
            qualityScore: _qualityScore,
            currentSpeed: speed < 0 ? 0 : speed,
          ),
          Positioned(
            right: 4,
            bottom: 4,
            child: IconButton(
              tooltip: 'Trajectory preview',
              icon: const Icon(Icons.open_in_full, size: 18),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const PointCloudPreviewScreen(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomStat(IconData icon, String value, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Colors.white54),
        const SizedBox(height: 2),
        AppText(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
        AppText(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.4),
            fontSize: 9,
          ),
        ),
      ],
    );
  }

  // ─── QUALITY SCORING ────────────────────────────────────────

  double _calculateQualityScore() {
    if (_capturePoints.length < 2) return 0;
    double score = 0;

    // Coverage contributes 40% of score
    score += (_coveragePercentage / 100) * 40;

    // Overlap consistency contributes 30%
    double overlapScore = 0;
    for (int i = 1; i < _capturePoints.length; i++) {
      final angleDiff =
          (_capturePoints[i].heading - _capturePoints[i - 1].heading).abs();
      final normalizedDiff = angleDiff > 180 ? 360 - angleDiff : angleDiff;
      // Ideal overlap: 15-30 degrees between captures
      if (normalizedDiff >= 10 && normalizedDiff <= 35) {
        overlapScore += 1.0;
      } else if (normalizedDiff < 10) {
        overlapScore += 0.5; // Too close
      } else {
        overlapScore += 0.2; // Too far apart
      }
    }
    score += (overlapScore / (_capturePoints.length - 1)) * 30;

    // Capture density contributes 30% (target: 50+ captures)
    score += min(_capturePoints.length / 50, 1.0) * 30;

    return score.clamp(0, 100);
  }

  /// AI Capture Hint: Analyzes coverage gaps, overlap, speed, and suggests direction.
  String _getAiHint() {
    if (_coveragePercentage >= 95) {
      return 'Heading sweep complete; inspect overlap and surface coverage separately.';
    }
    if (_coveragePercentage >= 90) {
      return 'Most headings sampled; object coverage is not measured.';
    }

    // Check overlap between last captures
    if (_capturePoints.length >= 2) {
      final last = _capturePoints.last;
      final prev = _capturePoints[_capturePoints.length - 2];
      final angleDiff = (last.heading - prev.heading).abs();
      final normalizedDiff = angleDiff > 180 ? 360 - angleDiff : angleDiff;

      if (normalizedDiff > 40) {
        return '⚠️ Large gap (${normalizedDiff.toInt()}°) between last captures. Move slower.';
      }
      if (normalizedDiff < 5) {
        return '↔️ Too similar to previous. Rotate more before next capture.';
      }

      // Check speed (if GPS available)
      if (last.latitude != 0 && prev.latitude != 0) {
        final dt = last.timestamp.difference(prev.timestamp).inSeconds;
        if (dt > 0) {
          final dx = last.latitude - prev.latitude;
          final dy = last.longitude - prev.longitude;
          final dist = sqrt(dx * dx + dy * dy) * 111320; // meters
          final speed = dist / dt; // m/s
          if (speed > 2.0) {
            return '🏃 Moving too fast (${speed.toStringAsFixed(1)} m/s). Slow down for sharp images.';
          }
        }
      }
    }

    // Find the largest gap
    final sectors = List<bool>.filled(36, false);
    for (final p in _capturePoints) {
      final sector = (p.heading / 10).floor() % 36;
      sectors[sector] = true;
      sectors[(sector + 1) % 36] = true;
      sectors[(sector - 1 + 36) % 36] = true;
    }

    int maxGapStart = 0, maxGapLen = 0, curStart = -1, curLen = 0;
    for (int i = 0; i < 72; i++) {
      if (!sectors[i % 36]) {
        if (curStart == -1) curStart = i;
        curLen++;
        if (curLen > maxGapLen) {
          maxGapLen = curLen;
          maxGapStart = curStart;
        }
      } else {
        curStart = -1;
        curLen = 0;
      }
    }

    if (maxGapLen == 0) {
      return 'Headings sampled. Add different heights and inspect overlap.';
    }

    final gapCenter = ((maxGapStart + maxGapLen / 2) % 36) * 10;
    final directions = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    final dirIndex = ((gapCenter + 22.5) / 45).floor() % 8;

    return '🧭 Gap ${directions[dirIndex]} (${gapCenter.toInt()}°). Turn that way and capture.';
  }
}

// ─── COVERAGE HEATMAP PAINTER ───────────────────────────────

class CoverageHeatmapPainter extends CustomPainter {
  final List<CapturePoint> capturePoints;
  final double currentHeading;
  final Color primaryColor;

  CoverageHeatmapPainter({
    required this.capturePoints,
    required this.currentHeading,
    required this.primaryColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2 - 20;

    // Draw concentric rings
    final ringPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (int i = 1; i <= 3; i++) {
      canvas.drawCircle(center, radius * (i / 3), ringPaint);
    }

    // Draw compass lines (N, E, S, W)
    final compassPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.1)
      ..strokeWidth = 0.5;

    for (int deg = 0; deg < 360; deg += 90) {
      final rad = deg * pi / 180;
      canvas.drawLine(
        center,
        Offset(center.dx + radius * sin(rad), center.dy - radius * cos(rad)),
        compassPaint,
      );
    }

    // Draw compass labels
    final textStyle = TextStyle(
      color: Colors.white.withValues(alpha: 0.4),
      fontSize: 10,
    );
    _drawText(
      canvas,
      'N',
      Offset(center.dx - 4, center.dy - radius - 14),
      textStyle,
    );
    _drawText(
      canvas,
      'E',
      Offset(center.dx + radius + 4, center.dy - 5),
      textStyle,
    );
    _drawText(
      canvas,
      'S',
      Offset(center.dx - 4, center.dy + radius + 4),
      textStyle,
    );
    _drawText(
      canvas,
      'W',
      Offset(center.dx - radius - 14, center.dy - 5),
      textStyle,
    );

    // Draw coverage sectors (36 sectors of 10°)
    final sectorCounts = List<int>.filled(36, 0);
    for (final p in capturePoints) {
      final sector = (p.heading / 10).floor() % 36;
      sectorCounts[sector]++;
    }

    final maxCount = sectorCounts.reduce(max).clamp(1, 100);

    for (int i = 0; i < 36; i++) {
      if (sectorCounts[i] == 0) continue;

      final startAngle = (i * 10 - 90) * pi / 180; // -90 to align N to top
      const sweepAngle = 10 * pi / 180;
      final intensity = sectorCounts[i] / maxCount;

      final sectorPaint = Paint()
        ..color = primaryColor.withValues(alpha: 0.1 + intensity * 0.5)
        ..style = PaintingStyle.fill;

      final rect = Rect.fromCircle(center: center, radius: radius);
      canvas.drawArc(rect, startAngle, sweepAngle, true, sectorPaint);
    }

    // Draw capture points as dots
    for (int i = 0; i < capturePoints.length; i++) {
      final p = capturePoints[i];
      final rad = (p.heading - 90) * pi / 180;
      // Place dots at varying distances from center to avoid overlap
      final dist = radius * 0.3 + (i % 5) * (radius * 0.12);
      final dotPos = Offset(
        center.dx + dist * cos(rad),
        center.dy + dist * sin(rad),
      );

      final dotPaint = Paint()
        ..color = primaryColor
        ..style = PaintingStyle.fill;

      canvas.drawCircle(dotPos, 3, dotPaint);
    }

    // Draw current heading arrow
    final arrowRad = (currentHeading - 90) * pi / 180;
    final arrowEnd = Offset(
      center.dx + (radius + 8) * cos(arrowRad),
      center.dy + (radius + 8) * sin(arrowRad),
    );
    final arrowPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.7)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawLine(center, arrowEnd, arrowPaint);

    // Arrow tip
    canvas.drawCircle(
      arrowEnd,
      4,
      Paint()..color = Colors.white.withValues(alpha: 0.7),
    );
  }

  void _drawText(Canvas canvas, String text, Offset offset, TextStyle style) {
    final textSpan = TextSpan(text: text, style: style);
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant CoverageHeatmapPainter oldDelegate) {
    return capturePoints.length != oldDelegate.capturePoints.length ||
        currentHeading != oldDelegate.currentHeading;
  }
}

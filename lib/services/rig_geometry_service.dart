import 'dart:convert';
import 'file_naming.dart';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/trajectory_service.dart';

/// Defines a camera's position and rotation relative to the phone mount.
/// Used to calculate world-space camera poses for Lichtfeld / Reality Capture.
class RigCamera {
  final String cameraId;
  String label; // User-friendly name
  // Position offset from phone mount (meters)
  double offsetX, offsetY, offsetZ;
  // Rotation offset (degrees) — yaw, pitch, roll
  double rotYaw, rotPitch, rotRoll;

  RigCamera({
    required this.cameraId,
    this.label = '',
    this.offsetX = 0,
    this.offsetY = 0,
    this.offsetZ = 0,
    this.rotYaw = 0,
    this.rotPitch = 0,
    this.rotRoll = 0,
  });

  Map<String, dynamic> toJson() => {
    'camera_id': cameraId,
    'label': label,
    'offset': {'x': offsetX, 'y': offsetY, 'z': offsetZ},
    'rotation': {'yaw': rotYaw, 'pitch': rotPitch, 'roll': rotRoll},
  };

  factory RigCamera.fromJson(Map<String, dynamic> json) {
    final offset = json['offset'] as Map<String, dynamic>? ?? {};
    final rot = json['rotation'] as Map<String, dynamic>? ?? {};
    return RigCamera(
      cameraId: json['camera_id'] ?? '',
      label: json['label'] ?? '',
      offsetX: (offset['x'] ?? 0).toDouble(),
      offsetY: (offset['y'] ?? 0).toDouble(),
      offsetZ: (offset['z'] ?? 0).toDouble(),
      rotYaw: (rot['yaw'] ?? 0).toDouble(),
      rotPitch: (rot['pitch'] ?? 0).toDouble(),
      rotRoll: (rot['roll'] ?? 0).toDouble(),
    );
  }
}

/// Manages the rig layout — camera positions relative to phone mount.
/// Exports per-capture world poses for each camera.
class RigGeometryService extends ChangeNotifier {
  final List<RigCamera> _cameras = [];
  String _namingTemplate = defaultNamingTemplate;

  List<RigCamera> get cameras => List.unmodifiable(_cameras);
  String get namingTemplate => _namingTemplate;

  RigGeometryService() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString('naming_template');
    // The old default numbered files per import, which repeats across
    // imports; move it to the date + original-name default.
    _namingTemplate = stored == null || stored == '{project}_{camera}_{index}'
        ? defaultNamingTemplate
        : stored;
    final json = prefs.getString('rig_cameras');
    if (json != null) {
      try {
        final list = jsonDecode(json) as List;
        _cameras.clear();
        _cameras.addAll(
          list.map((e) => RigCamera.fromJson(e as Map<String, dynamic>)),
        );
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'rig_cameras',
      jsonEncode(_cameras.map((c) => c.toJson()).toList()),
    );
    await prefs.setString('naming_template', _namingTemplate);
  }

  void setNamingTemplate(String template) async {
    _namingTemplate = template;
    await _save();
    notifyListeners();
  }

  /// Generate a filename from the template
  String generateFileName({
    required String projectName,
    required String cameraLabel,
    required int index,
    String extension = 'jpg',
  }) {
    return '${_namingTemplate.replaceAll('{project}', projectName).replaceAll('{camera}', cameraLabel).replaceAll('{index}', index.toString().padLeft(4, '0')).replaceAll('{date}', DateTime.now().toIso8601String().split('T')[0]).replaceAll('{time}', DateTime.now().toIso8601String().split('T')[1].split('.')[0].replaceAll(':', ''))}.$extension';
  }

  void addCamera(String cameraId, String label) {
    if (_cameras.any((c) => c.cameraId == cameraId)) return;
    _cameras.add(
      RigCamera(
        cameraId: cameraId,
        label: label.isNotEmpty ? label : 'CAM${_cameras.length + 1}',
      ),
    );
    _save();
    notifyListeners();
  }

  void updateCamera(
    String cameraId, {
    double? x,
    double? y,
    double? z,
    double? yaw,
    double? pitch,
    double? roll,
    String? label,
  }) {
    final idx = _cameras.indexWhere((c) => c.cameraId == cameraId);
    if (idx == -1) return;
    if (x != null) _cameras[idx].offsetX = x;
    if (y != null) _cameras[idx].offsetY = y;
    if (z != null) _cameras[idx].offsetZ = z;
    if (yaw != null) _cameras[idx].rotYaw = yaw;
    if (pitch != null) _cameras[idx].rotPitch = pitch;
    if (roll != null) _cameras[idx].rotRoll = roll;
    if (label != null) _cameras[idx].label = label;
    _save();
    notifyListeners();
  }

  void removeCamera(String cameraId) {
    _cameras.removeWhere((c) => c.cameraId == cameraId);
    _save();
    notifyListeners();
  }

  // ─── EXPORT ────────────────────────────────────────────

  /// Export full session data for Lichtfeld Studio / Reality Capture / COLMAP.
  /// Includes phone trajectory + per-camera world poses at each capture point.
  String exportSessionJson({
    required String projectName,
    required List<TrajectoryPoint> trajectory,
    required List<String> connectedCameraIds,
  }) {
    final captureFrames = <Map<String, dynamic>>[];

    for (final point in trajectory) {
      final phoneHeadingRad = point.heading * pi / 180;

      // Phone world position (simplified — GPS to local meters)
      final refLat = trajectory.isNotEmpty
          ? trajectory[0].latitude
          : point.latitude;
      final refLon = trajectory.isNotEmpty
          ? trajectory[0].longitude
          : point.longitude;
      final phonePosX =
          (point.longitude - refLon) * 111320 * cos(refLat * pi / 180);
      final phonePosY =
          point.altitude - (trajectory.isNotEmpty ? trajectory[0].altitude : 0);
      final phonePosZ = (point.latitude - refLat) * 110540;

      final cameraPoses = <Map<String, dynamic>>[];
      for (final camId in connectedCameraIds) {
        final rigCam = _cameras.firstWhere(
          (c) => c.cameraId == camId,
          orElse: () => RigCamera(cameraId: camId, label: camId),
        );

        // Rotate camera offset by phone heading
        final cosH = cos(phoneHeadingRad);
        final sinH = sin(phoneHeadingRad);
        final worldX =
            phonePosX + rigCam.offsetX * cosH - rigCam.offsetZ * sinH;
        final worldY = phonePosY + rigCam.offsetY;
        final worldZ =
            phonePosZ + rigCam.offsetX * sinH + rigCam.offsetZ * cosH;

        final camYaw = point.heading + rigCam.rotYaw;
        final camPitch = rigCam.rotPitch;
        final camRoll = rigCam.rotRoll;

        cameraPoses.add({
          'camera_id': camId,
          'label': rigCam.label,
          'file_name': generateFileName(
            projectName: projectName,
            cameraLabel: rigCam.label,
            index: point.index,
          ),
          'position': {'x': worldX, 'y': worldY, 'z': worldZ},
          'rotation': {'yaw': camYaw, 'pitch': camPitch, 'roll': camRoll},
          'transform_matrix': _buildTransformMatrix(
            worldX,
            worldY,
            worldZ,
            camYaw,
            camPitch,
            camRoll,
          ),
        });
      }

      captureFrames.add({
        'capture_index': point.index,
        'timestamp': point.timestamp.toIso8601String(),
        'phone': {
          'position': {'x': phonePosX, 'y': phonePosY, 'z': phonePosZ},
          'heading': point.heading,
          'gps': {
            'lat': point.latitude,
            'lon': point.longitude,
            'alt': point.altitude,
          },
          'speed_ms': point.speed,
          'accuracy_m': point.accuracy,
          'pressure_hpa': point.pressure,
          'imu': {
            'accel': {'x': point.accelX, 'y': point.accelY, 'z': point.accelZ},
            'gyro': {'x': point.gyroX, 'y': point.gyroY, 'z': point.gyroZ},
            'mag': {'x': point.magX, 'y': point.magY, 'z': point.magZ},
          },
        },
        'cameras': cameraPoses,
      });
    }

    return const JsonEncoder.withIndent('  ').convert({
      'format': 'kosmos3d_session',
      'version': '2.0',
      'project': projectName,
      'rig': _cameras.map((c) => c.toJson()).toList(),
      'naming_template': _namingTemplate,
      'capture_count': trajectory.length,
      'camera_count': connectedCameraIds.length,
      'frames': captureFrames,
    });
  }

  List<List<double>> _buildTransformMatrix(
    double x,
    double y,
    double z,
    double yawDeg,
    double pitchDeg,
    double rollDeg,
  ) {
    final yaw = yawDeg * pi / 180;
    final pitch = pitchDeg * pi / 180;
    final roll = rollDeg * pi / 180;

    // Rotation matrix: Rz(yaw) * Ry(pitch) * Rx(roll)
    final cy = cos(yaw);
    final sy = sin(yaw);
    final cp = cos(pitch);
    final sp = sin(pitch);
    final cr = cos(roll);
    final sr = sin(roll);

    return [
      [cy * cp, cy * sp * sr - sy * cr, cy * sp * cr + sy * sr, x],
      [sy * cp, sy * sp * sr + cy * cr, sy * sp * cr - cy * sr, y],
      [-sp, cp * sr, cp * cr, z],
      [0, 0, 0, 1],
    ];
  }
}

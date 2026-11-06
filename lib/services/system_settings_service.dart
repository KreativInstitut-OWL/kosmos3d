import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Service to interact with native Android / iOS system settings
class SystemSettingsService {
  static const _channel = MethodChannel(
    'com.kosmos3d.kosmos3d/system_settings',
  );

  static Future<void> joinCameraWifi(String ssid, String password) => _channel
      .invokeMethod('joinCameraWifi', {'ssid': ssid, 'password': password});

  static Future<void> releaseCameraWifi() =>
      _channel.invokeMethod('releaseCameraWifi');

  /// Keeps the app running while a capture session is open, also with the
  /// screen locked (Android foreground service with a notification).
  static Future<void> startCaptureService(String title) async {
    try {
      await _channel.invokeMethod('startCaptureService', {'title': title});
    } catch (e) {
      debugPrint('Capture service not started: $e');
    }
  }

  static Future<void> stopCaptureService() async {
    try {
      await _channel.invokeMethod('stopCaptureService');
    } catch (e) {
      debugPrint('Capture service not stopped: $e');
    }
  }

  static Future<void> keepScreenOn(bool on) async {
    try {
      await _channel.invokeMethod('keepScreenOn', {'on': on});
    } catch (e) {
      debugPrint('Keep screen on failed: $e');
    }
  }

  static Future<void> openWifiSettings() =>
      _channel.invokeMethod('openWifiSettings');

  static Future<String> saveToDownloads(
    String sourcePath, {
    required String relativePath,
  }) async {
    final result = await _channel.invokeMethod<String>('saveToDownloads', {
      'sourcePath': sourcePath,
      'relativePath': relativePath,
    });
    if (result == null) {
      throw StateError('The phone did not confirm the export.');
    }
    return result;
  }

  /// Open the device's native Wi-Fi Hotspot / Tethering settings page
  static Future<void> openHotspotSettings() async {
    try {
      await _channel.invokeMethod('openTetheringSettings');
    } catch (e) {
      debugPrint('Could not open hotspot settings: $e');
    }
  }

  /// Notify the Android MediaScanner about a new media file so it shows in the gallery app
  static Future<void> scanFileToGallery(String filePath) async {
    try {
      await _channel.invokeMethod('scanFileToGallery', {'filePath': filePath});
    } catch (e) {
      debugPrint('Error scanning file to gallery: $e');
    }
  }

  /// Copy an image/video to the phone's public DCIM/KOSMOS3D gallery folder and trigger media scanner
  static Future<String?> saveToDeviceGallery(
    String sourcePath, {
    String albumName = 'KOSMOS3D',
  }) async {
    try {
      final destPath = await _channel.invokeMethod<String>(
        'saveToDeviceGallery',
        {'sourcePath': sourcePath, 'albumName': albumName},
      );
      return destPath;
    } catch (e) {
      debugPrint('Error saving to device gallery: $e');
      return null;
    }
  }
}

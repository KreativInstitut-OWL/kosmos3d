import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_translations.dart';

/// Preset profile for quick camera configuration
class CameraPreset {
  final String name;
  final String icon;
  final Map<String, String> settings;

  const CameraPreset({
    required this.name,
    required this.icon,
    required this.settings,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'icon': icon,
    'settings': settings,
  };

  factory CameraPreset.fromJson(Map<String, dynamic> json) => CameraPreset(
    name: json['name'] as String,
    icon: json['icon'] as String? ?? '📷',
    settings: Map<String, String>.from(json['settings'] as Map),
  );
}

class SettingsProvider extends ChangeNotifier {
  String _currentLanguage = 'en';
  ThemeMode _themeMode = ThemeMode.system;
  List<CameraPreset> _customPresets = [];
  bool _hapticFeedback = true;
  bool _cloudAutoUpload = false;
  bool _serverAutoUpload = false;
  bool _recordBarometer = true;
  int _sensorRate = 50; // ms
  int _gpsRate = 1; // seconds (GPS fixes arrive at ~1 Hz)
  String _captureInterval = '1s';
  // Android phones have no LiDAR; their view is only an estimate from GPS
  // and orientation, so it starts switched off there.
  static final bool _coverageDefault = !Platform.isAndroid;
  bool _coverageVisualizer = _coverageDefault;
  bool get coverageVisualizer => _coverageVisualizer;
  Future<void> setCoverageVisualizer(bool value) async {
    _coverageVisualizer = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('coverage_visualizer', value);
  }

  bool _keepScreenOn = false;
  bool get keepScreenOn => _keepScreenOn;
  Future<void> setKeepScreenOn(bool value) async {
    _keepScreenOn = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('keep_screen_on', value);
  }

  String _hotspotSsid = '';
  String _hotspotPassword = '';

  // Server configuration
  String _serverUrl = '';
  String _serverUsername = '';
  String _serverPassword = '';
  String _serverApiKey = '';

  String get currentLanguage => _currentLanguage;
  ThemeMode get themeMode => _themeMode;
  bool get hapticFeedback => _hapticFeedback;
  bool get autoUpload => _cloudAutoUpload;
  bool get cloudAutoUpload => _cloudAutoUpload;
  bool get serverAutoUpload => _serverAutoUpload;
  bool get recordBarometer => _recordBarometer;
  int get sensorRate => _sensorRate;
  int get gpsRate => _gpsRate;
  String get captureInterval => _captureInterval;
  String get hotspotSsid => _hotspotSsid;
  String get hotspotPassword => _hotspotPassword;

  String get serverUrl => _serverUrl;
  String get serverUsername => _serverUsername;
  String get serverPassword => _serverPassword;
  String get serverApiKey => _serverApiKey;

  // ─── BUILT-IN PRESETS ────────────────────────────────────
  static const List<CameraPreset> builtInPresets = [
    CameraPreset(
      name: 'KIO',
      icon: '🎥',
      settings: {
        'Mode': 'video',
        'Resolution': '5.3K',
        'FPS': '30',
        'Lens': 'Linear',
        'Bitrate': 'High',
        'Hypersmooth': 'Off',
        'Interval': 'Off',
        'Orientation': 'Portrait',
        'Target ISO Min': '200',
        'Target ISO': '200',
        'Target Shutter': '1/500',
        'Target White Balance': '5500K',
        'Target Color': 'Flat',
        'Guidance':
            'KIO standard: 5.3K / 30 fps video, Linear, fixed ISO 200 and 1/500 s, stabilization off. Show the exposure QR to every camera (GoPro Labs) or set ISO and shutter on each camera. Needs good light.',
      },
    ),
    CameraPreset(
      name: 'Outdoor Photo',
      icon: '🌳',
      settings: {
        'Mode': 'photo',
        'Photo Format': 'Standard',
        'Interval': '1s',
        'Interval Timing': 'Camera timer',
        'Lens': 'Linear',
        'Orientation': 'Portrait',
        'Target ISO Min': '100',
        'Target ISO': '200',
        'Target White Balance': '5500K',
        'Target Color': 'Flat',
        'Guidance':
            'Daylight photo scan: 1 s camera timer, Linear, low ISO, fixed daylight white balance. Walk slowly; check the first images for blur.',
      },
    ),
    CameraPreset(
      name: 'Interior Photo',
      icon: '🏠',
      settings: {
        'Mode': 'photo',
        'Photo Format': 'Standard',
        'Interval': '2s',
        'Interval Timing': 'Camera timer',
        'Lens': 'Linear',
        'Orientation': 'Portrait',
        'Target ISO Min': '100',
        'Target ISO': '800',
        'Target White Balance': '4000K',
        'Target Color': 'Flat',
        'Guidance':
            'Indoor photo scan: 2 s interval, Linear, ISO up to 800 and fixed white balance. Add even light and pause briefly for each shot.',
      },
    ),
    CameraPreset(
      name: 'Detail Photo',
      icon: '🔬',
      settings: {
        'Mode': 'photo',
        'Photo Format': 'RAW',
        'Interval': '2s',
        'Interval Timing': 'Camera timer',
        'Lens': 'Linear',
        'Orientation': 'Portrait',
        'Target ISO Min': '100',
        'Target ISO': '400',
        'Target White Balance': '5500K',
        'Target Sharpness': 'Low',
        'Guidance':
            'Close-up objects: RAW + Linear, high overlap, stay beyond the minimum focus distance. Low in-camera sharpening keeps texture natural.',
      },
    ),
    CameraPreset(
      name: 'Video Walk 4K',
      icon: '🎬',
      settings: {
        'Mode': 'video',
        'Resolution': '4K',
        'FPS': '30',
        'Lens': 'Linear',
        'Bitrate': 'High',
        'Hypersmooth': 'Off',
        'Interval': 'Off',
        'Orientation': 'Portrait',
        'Target ISO Min': '100',
        'Target ISO': '400',
        'Target Shutter': '1/240',
        'Target White Balance': '5500K',
        'Target Color': 'Flat',
        'Guidance':
            'Lighter files than KIO: 4K / 30 fps, 1/240 s against motion blur, stabilization off for consistent calibration.',
      },
    ),
  ];

  List<CameraPreset> get allPresets => [...builtInPresets, ..._customPresets];
  List<CameraPreset> get customPresets => _customPresets;

  SettingsProvider() {
    ready = _loadPreferences();
  }
  late final Future<void> ready;

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();

    _currentLanguage = prefs.getString('language') == 'de' ? 'de' : 'en';

    // Theme mode
    final themeStr = prefs.getString('theme_mode') ?? 'system';
    _themeMode = themeStr == 'dark'
        ? ThemeMode.dark
        : themeStr == 'light'
        ? ThemeMode.light
        : ThemeMode.system;

    // Preferences
    _hapticFeedback = prefs.getBool('haptic_feedback') ?? true;
    _cloudAutoUpload =
        prefs.getBool('cloud_auto_upload') ??
        prefs.getBool('auto_upload') ??
        false;
    _serverAutoUpload = prefs.getBool('server_auto_upload') ?? false;
    _recordBarometer = prefs.getBool('record_barometer') ?? true;
    _sensorRate = prefs.getInt('sensor_rate') ?? 50;
    _gpsRate = prefs.getInt('gps_rate') ?? 1;
    _captureInterval = prefs.getString('capture_interval') ?? '1s';
    _hotspotSsid = prefs.getString('hotspot_ssid') ?? '';
    _hotspotPassword = prefs.getString('hotspot_password') ?? '';

    _coverageVisualizer =
        prefs.getBool('coverage_visualizer') ?? _coverageDefault;
    _keepScreenOn = prefs.getBool('keep_screen_on') ?? false;
    // Server configuration
    _serverUrl = prefs.getString('server_url') ?? '';
    _serverUsername = prefs.getString('server_username') ?? '';
    _serverPassword = prefs.getString('server_password') ?? '';
    _serverApiKey = prefs.getString('server_api_key') ?? '';

    // Load custom presets
    final presetsJson = prefs.getString('custom_presets');
    if (presetsJson != null) {
      try {
        final list = jsonDecode(presetsJson) as List;
        _customPresets = list
            .map((e) => CameraPreset.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {}
    }
    notifyListeners();
  }

  // ─── THEME ──────────────────────────────────────────────

  void setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'theme_mode',
      mode == ThemeMode.dark
          ? 'dark'
          : mode == ThemeMode.light
          ? 'light'
          : 'system',
    );
    notifyListeners();
  }

  // ─── LANGUAGE ───────────────────────────────────────────

  void toggleLanguage() async {
    _currentLanguage = _currentLanguage == 'en' ? 'de' : 'en';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language', _currentLanguage);
    notifyListeners();
  }

  String translate(String key) {
    return AppTranslations.get(_currentLanguage, key);
  }

  // ─── APP SETTINGS ──────────────────────────────────────

  void setHapticFeedback(bool value) async {
    _hapticFeedback = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('haptic_feedback', value);
    notifyListeners();
  }

  void setAutoUpload(bool value) async {
    setCloudAutoUpload(value);
  }

  void setCloudAutoUpload(bool value) async {
    _cloudAutoUpload = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('cloud_auto_upload', value);
    await prefs.setBool('auto_upload', value);
    notifyListeners();
  }

  void setServerAutoUpload(bool value) async {
    _serverAutoUpload = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('server_auto_upload', value);
    notifyListeners();
  }

  void setHotspotSsid(String value) async {
    _hotspotSsid = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('hotspot_ssid', value);
    notifyListeners();
  }

  void setHotspotPassword(String value) async {
    _hotspotPassword = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('hotspot_password', value);
    notifyListeners();
  }

  void setServerUrl(String value) async {
    _serverUrl = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_url', value);
    notifyListeners();
  }

  void setServerUsername(String value) async {
    _serverUsername = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_username', value);
    notifyListeners();
  }

  void setServerPassword(String value) async {
    _serverPassword = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_password', value);
    notifyListeners();
  }

  void setServerApiKey(String value) async {
    _serverApiKey = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_api_key', value);
    notifyListeners();
  }

  void setRecordBarometer(bool value) async {
    _recordBarometer = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('record_barometer', value);
    notifyListeners();
  }

  void setSensorRate(int ms) async {
    _sensorRate = ms;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('sensor_rate', ms);
    notifyListeners();
  }

  void setGpsRate(int seconds) async {
    _gpsRate = seconds;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('gps_rate', seconds);
    notifyListeners();
  }

  void setCaptureInterval(String value) async {
    _captureInterval = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('capture_interval', value);
    notifyListeners();
  }

  // ─── PRESET MANAGEMENT ──────────────────────────────────

  Future<void> addCustomPreset(CameraPreset preset) async {
    _customPresets.add(preset);
    await _saveCustomPresets();
    notifyListeners();
  }

  Future<void> removeCustomPreset(int index) async {
    if (index >= 0 && index < _customPresets.length) {
      _customPresets.removeAt(index);
      await _saveCustomPresets();
      notifyListeners();
    }
  }

  Future<void> _saveCustomPresets() async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(_customPresets.map((p) => p.toJson()).toList());
    await prefs.setString('custom_presets', json);
  }

  // ─── DEFAULT SETTINGS ───────────────────────────────────

  Future<Map<String, String>> getDefaultSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('default_camera_settings_v2');
    if (json != null) {
      try {
        return Map<String, String>.from(jsonDecode(json));
      } catch (_) {}
    }
    return builtInPresets[0].settings;
  }

  Future<void> setDefaultSettings(Map<String, String> settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('default_camera_settings_v2', jsonEncode(settings));
    notifyListeners();
  }
}

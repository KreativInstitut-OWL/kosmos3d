import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/camera_device.dart';
import '../models/import_report.dart';
import 'package:crypto/crypto.dart';
import 'gopro_protocol.dart';
import 'capture_coordinator.dart';
import 'system_settings_service.dart';
import 'media_inventory.dart';
import 'gopro_setting_catalog.dart';

/// Open GoPro BLE Protocol UUIDs
class GoProUuids {
  static final wifiSsid = Guid('b5f90002-aa8d-11e3-9046-0002a5d5c51b');
  static final wifiPassword = Guid('b5f90003-aa8d-11e3-9046-0002a5d5c51b');
  static final service = Guid('0000fea6-0000-1000-8000-00805f9b34fb');
  static final commandReq = Guid('b5f90072-aa8d-11e3-9046-0002a5d5c51b');
  static final commandResp = Guid('b5f90073-aa8d-11e3-9046-0002a5d5c51b');
  static final settingReq = Guid('b5f90074-aa8d-11e3-9046-0002a5d5c51b');
  static final settingResp = Guid('b5f90075-aa8d-11e3-9046-0002a5d5c51b');
  static final queryReq = Guid('b5f90076-aa8d-11e3-9046-0002a5d5c51b');
  static final queryResp = Guid('b5f90077-aa8d-11e3-9046-0002a5d5c51b');
}

/// Represents a media file residing on a GoPro's SD card
class GoProMediaItem {
  final String cameraName;
  final String cameraId;
  final String ip;
  final String directory;
  final String filename;
  final String url;
  final int sizeBytes;
  final DateTime? modifiedTime;
  final bool isVideo;

  GoProMediaItem({
    required this.cameraName,
    this.cameraId = '',
    required this.ip,
    required this.directory,
    required this.filename,
    required this.url,
    this.sizeBytes = 0,
    this.modifiedTime,
    this.isVideo = false,
  });

  String get displayName => filename;

  String get formattedSize {
    if (sizeBytes <= 0) return '';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Open GoPro Setting IDs and their value mappings
class GoProSettings {
  // Setting ID 2: Resolution
  static const int resolutionId = 2;
  static const Map<String, int> resolution = {
    '1080p': 9,
    '2.7K': 4,
    '4K': 1,
    '5.3K': 100,
  };

  // Setting ID 3: FPS
  static const int fpsId = 3;
  static const Map<String, int> fps = {'24': 10, '30': 8, '60': 5, '120': 0};

  // Setting ID 121: Digital Lens (Video)
  static const int videoLensId = 121;
  static const Map<String, int> videoLens = {
    'Wide': 0,
    'Linear': 4,
    'SuperView': 3,
  };

  // Setting ID 122: Digital Lens (Photo)
  static const int photoLensId = 122;
  static const Map<String, int> photoLens = {'Wide': 31, 'Linear': 32};

  // Protune IDs are not part of the published Open GoPro setting table.
  // Never send speculative registers for ISO, WB or shutter.
  static const int bitrateId = 182;
  static const Map<String, int> bitrate = {'Standard': 0, 'High': 1};

  // Setting ID 125: Photo Output (Standard, RAW, HDR, SuperPhoto)
  static const int photoOutputId = 125;
  static const Map<String, int> photoOutput = {
    'Standard Photo': 0,
    'Standard': 0,
    'RAW': 1,
    'HDR': 2,
    'SuperPhoto': 3,
    'Super Photo': 3,
  };

  // Setting ID 20: SuperPhoto / Processing Mode
  static const int superPhotoId = 20;
  static const Map<String, int> superPhoto = {
    'Off': 0,
    'Standard Photo': 0,
    'Auto': 1,
    'HDR': 2,
    'SuperPhoto': 3,
    'RAW': 4,
  };

  // Setting ID 30: TimeLapse Interval
  static const int timeLapseIntervalId = 30;
  static const Map<String, int> timeLapseInterval = {
    '0.5s': 0,
    '1s': 1,
    '2s': 2,
    '5s': 3,
    '10s': 4,
    '30s': 5,
    '60s': 6,
  };

  // Setting ID 171: Photo Single Interval
  static const int photoSingleIntervalId = 171;
  static const Map<String, int> photoSingleInterval = {
    'Off': 0,
    '0.5s': 2,
    '1s': 3,
    '2s': 4,
    '5s': 5,
    '10s': 6,
    '30s': 7,
    '60s': 8,
  };

  // Setting ID 97: Photo Timer
  static const int photoTimerId = 97;
  static const Map<String, int> photoTimer = {'Off': 0, '3s': 1, '10s': 2};

  // Setting ID 227: Photo Mode (0=SuperPhoto/Single, 1=Night Photo, 2=Burst)
  static const int photoModeId = 227;

  // Preset Group IDs for mode switching
  static const int presetGroupVideo = 1000;
  static const int presetGroupPhoto = 1001;
  static const int presetGroupTimelapse = 1002;

  // These identify discovered presets; they are NOT legacy mode commands.
  static const int flatModeVideo = 12;
  static const int flatModePhoto = 16;
  static const int flatModeTimelapseVideo = 13;
  static const int flatModeTimelapsePhoto = 20;
  static const int flatModeNightPhoto = 18;
  static const int flatModeNightLapse = 21;
  static const int flatModeBurstPhoto = 19;
}

/// Abstract camera service interface for future extensibility
abstract class CameraServiceInterface {
  List<CameraDevice> get devices;
  bool get isScanning;
  void startScan();
  Future<void> connectToDevice(String id);
  Future<void> triggerShutter(String id);
  Future<void> stopShutter(String id);
  Future<void> applySettingsToDevice(String id, Map<String, String> settings);
}

class GoProService extends ChangeNotifier implements CameraServiceInterface {
  GoProService() {
    capture.addListener(notifyListeners);
    unawaited(loadKnownCameras());
  }
  @visibleForTesting
  GoProService.testConnection(String id, GoProProtocol protocol) {
    capture.addListener(notifyListeners);
    _protocols[id] = protocol;
    _devices.add(CameraDevice(id: id, name: 'Test camera', isConnected: true));
  }
  final Map<String, String> _serials = {};
  final Map<String, String> _models = {};
  String modelFor(String id) => _models[id] ?? 'Unknown model';
  final Map<String, void Function(String)> _settingProgress = {};
  StreamSubscription? _scanSubscription;

  Future<void> _readHardware(String id) async {
    final payload = await _protocol(id).exchange('command', [0x3C]);
    var offset = 2;
    final fields = <List<int>>[];
    for (var i = 0; i < 5; i++) {
      if (offset >= payload.length) {
        throw const FormatException('Missing hardware info');
      }
      final length = payload[offset++];
      if (offset + length > payload.length) {
        throw const FormatException('Truncated hardware info');
      }
      fields.add(payload.sublist(offset, offset + length));
      offset += length;
    }
    final model = utf8.decode(fields[1]);
    _models[id] = model;
    _serials[id] = utf8.decode(fields[4]);
  }

  Future<bool> _associateIp(String ip) async {
    for (final device in _devices.where((d) => d.wifiIpAddress == ip)) {
      device.wifiIpAddress = null;
      device.isWifiConnected = false;
    }
    try {
      final result = await http
          .get(Uri.parse('http://$ip:8080/gopro/camera/info'))
          .timeout(const Duration(seconds: 2));
      if (result.statusCode != 200) return false;
      final data = jsonDecode(result.body) as Map<String, dynamic>;
      final serial = data['serial_number']?.toString();
      if (serial == null || serial.isEmpty) return false;
      final index = _devices.indexWhere(
        (d) => d.isConnected && _serials[d.id] == serial,
      );
      if (index < 0) return false;
      _devices[index] = _devices[index].copyWith(
        isWifiConnected: true,
        wifiIpAddress: ip,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  final CaptureCoordinator capture = CaptureCoordinator();

  /// SHA-256 computed during download, keyed by final file path.
  final Map<String, String> _downloadDigests = {};
  final Map<String, GoProProtocol> _protocols = {};
  final Map<String, List<StreamSubscription>> _subscriptions = {};
  final Map<String, int> _expectedModes = {};
  final Map<String, Map<int, int>> _verified = {};

  Future<void> prepareCapture(String mode, Map<String, String> settings) async {
    if (_isSyncingMedia) throw StateError('Finish importing before capture');
    await stopAllPreviews();
    await capture.prepare(
      devices
          .where((d) => d.isConnected)
          .map((d) => _GoProRigCamera(this, d.id))
          .toList(),
      mode,
      settings,
    );
  }

  GoProProtocol _protocol(String id) =>
      _protocols[id] ??
      (throw StateError('Camera $id is disconnected; reconnect it'));

  Future<Map<int, List<int>>> _query(
    String id,
    int query,
    List<int> ids,
  ) async => decodeTlv(await _protocol(id).exchange('query', [query, ...ids]));

  Future<int> _status(String id, int key) async {
    final values = await _query(id, 0x13, [key]);
    if (values[key]?.isNotEmpty != true) {
      throw StateError('Missing status $key from $id');
    }
    return bigEndian(values[key]!);
  }

  Future<void> _waitIdle(String id) async {
    final deadline = Stopwatch()..start();
    while (deadline.elapsed < const Duration(seconds: 30)) {
      final values = await _query(id, 0x13, [8, 10]);
      if (values[8]?.isNotEmpty != true || values[10]?.isNotEmpty != true) {
        throw StateError('Camera $id did not report busy/encoding status');
      }
      if (bigEndian(values[8]!) == 0 && bigEndian(values[10]!) == 0) return;
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    throw TimeoutException('Camera $id is still processing after 30 seconds');
  }

  Future<void> _verifyReady(String id) async {
    if (_previewCameraId != null || _previewTransition) {
      throw StateError('Stop preview before capturing.');
    }
    await _waitIdle(id);
    if (await _status(id, 89) != _expectedModes[id]) {
      throw StateError('Camera $id changed mode; synchronize again');
    }
    final expected = _verified[id] ?? {};
    if (expected.isNotEmpty) {
      final actual = await _query(id, 0x12, expected.keys.toList());
      for (final entry in expected.entries) {
        if (actual[entry.key] == null ||
            bigEndian(actual[entry.key]!) != entry.value) {
          throw StateError(
            'Camera $id changed setting ${entry.key}; synchronize again',
          );
        }
      }
    }
  }

  Future<void> _configure(
    String id,
    String mode,
    Map<String, String> settings,
    void Function(String) progress,
  ) async {
    // Validate unsupported controls before mutating any camera.
    _validateSettings(settings);
    _verified.remove(id);
    _settingProgress[id] = progress;
    try {
      final index = _devices.indexWhere((d) => d.id == id);
      if (index >= 0) {
        _devices[index] = _devices[index].copyWith(currentSettings: {});
      }
      progress('Stopping and selecting $mode preset');
      await _selectMode(id, mode == 'video' ? 12 : 16);
      progress('Applying and reading back settings');
      await applySettingsToDevice(id, settings, captureMode: mode);
      await _verifyReady(id);
      updateCameraSettings(id, settings);
      progress('Verified');
    } finally {
      _settingProgress.remove(id);
    }
  }

  void _validateSettings(Map<String, String> settings) {
    for (final key in ['ISO Max', 'Shutter', 'White Balance']) {
      if (settings[key] != null && settings[key] != 'Camera preset') {
        throw UnsupportedError(
          '$key cannot be verified with the published Open GoPro API. '
          'Set it on every camera (or via GoPro Labs QR) and select Camera preset.',
        );
      }
    }
  }

  final List<CameraDevice> _devices = [];
  final Map<String, BluetoothDevice> _bleDevices = {};
  final Map<String, Map<String, BluetoothCharacteristic>> _charCache = {};
  bool _isScanning = false;

  // Media sync state
  bool _isSyncingMedia = false;
  bool _cancelImport = false;
  final List<String> galleryFailures = [];
  void cancelImport() {
    _cancelImport = true;
  }

  double _syncProgress = 0.0;
  String _syncStatusMessage = '';

  // Keep-alive and polling timers per device
  final Map<String, Timer> _keepAliveTimers = {};
  final Map<String, Timer> _batteryPollTimers = {};

  @override
  List<CameraDevice> get devices => _devices;
  @override
  bool get isScanning => _isScanning;

  bool get isSyncingMedia => _isSyncingMedia;
  double get syncProgress => _syncProgress;
  String get syncStatusMessage => _syncStatusMessage;

  bool get _isMobilePlatform {
    if (kIsWeb) return false;
    try {
      return Platform.isAndroid || Platform.isIOS;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _requestPermissions() async {
    if (Platform.isAndroid) {
      if (await Permission.bluetoothScan.request().isGranted &&
          await Permission.bluetoothConnect.request().isGranted &&
          await Permission.location.request().isGranted) {
        return true;
      }
      return false;
    } else if (Platform.isIOS) {
      return true;
    }
    return false;
  }

  // ─── SCANNING ──────────────────────────────────────────────

  @override
  void startScan() async {
    if (_isScanning || capture.busy || capture.active) return;

    _isScanning = true;
    // Preserve connected peripherals and their notification subscriptions.
    _devices.removeWhere((d) => !d.isConnected);
    notifyListeners();

    if (_isMobilePlatform) {
      bool hasPermissions = await _requestPermissions();
      if (!hasPermissions) {
        _isScanning = false;
        notifyListeners();
        return;
      }

      try {
        // Right after launch the adapter state is still "unknown"; a scan
        // started then silently returns nothing.
        await FlutterBluePlus.adapterState
            .where((s) => s == BluetoothAdapterState.on)
            .first
            .timeout(const Duration(seconds: 5));

        // Subscribe before starting so early advertisements are not missed.
        await _scanSubscription?.cancel();
        _scanSubscription = FlutterBluePlus.onScanResults.listen((results) {
          for (var r in results) {
            final deviceName = r.device.platformName.isNotEmpty
                ? r.device.platformName
                : r.advertisementData.advName;
            final isGoPro =
                deviceName.startsWith('GoPro') ||
                r.advertisementData.serviceUuids.contains(Guid('fea6'));
            if (deviceName.isNotEmpty && isGoPro) {
              final existing = _devices.any(
                (d) => d.id == r.device.remoteId.str,
              );
              if (!existing) {
                _bleDevices[r.device.remoteId.str] = r.device;
                _devices.add(
                  CameraDevice(
                    id: r.device.remoteId.str,
                    name: deviceName,
                    isConnected: false,
                    batteryLevel: 0,
                    storageRemaining: 'Unknown',
                    isRecording: false,
                  ),
                );
              }
            }
          }
          notifyListeners();
        });

        // Sleeping cameras advertise slowly; 10 s catches them reliably.
        await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
        await FlutterBluePlus.isScanning.where((s) => !s).first;
      } catch (e) {
        debugPrint("BLE Scan Error: $e");
      }
    } else {
      await Future.delayed(const Duration(seconds: 1));
    }

    _isScanning = false;
    await loadKnownCameras();
    notifyListeners();
  }

  // ─── CONNECTION ────────────────────────────────────────────

  @override
  Future<void> connectToDevice(String id) async {
    if (!_isMobilePlatform) {
      final index = _devices.indexWhere((d) => d.id == id);
      if (index != -1) {
        _devices[index] = _devices[index].copyWith(isConnected: true);
        notifyListeners();
      }
      return;
    }

    try {
      final device = _bleDevices[id];
      if (device != null) {
        await device.connect(license: License.free);

        // Request larger MTU on Android for Wi-Fi provisioning credentials
        try {
          if (Platform.isAndroid) {
            await device.requestMtu(512);
          }
        } catch (_) {}

        // Discover services and cache characteristics
        List<BluetoothService> services = await device.discoverServices();
        final chars = <String, BluetoothCharacteristic>{};

        for (var service in services) {
          for (final c in service.characteristics) {
            if (c.characteristicUuid == GoProUuids.wifiSsid) {
              chars['wifiSsid'] = c;
            }
            if (c.characteristicUuid == GoProUuids.wifiPassword) {
              chars['wifiPassword'] = c;
            }
          }
          if (service.serviceUuid == GoProUuids.service) {
            for (var c in service.characteristics) {
              if (c.characteristicUuid == GoProUuids.commandReq) {
                chars['commandReq'] = c;
              }
              if (c.characteristicUuid == GoProUuids.commandResp) {
                chars['commandResp'] = c;
              }
              if (c.characteristicUuid == GoProUuids.settingReq) {
                chars['settingReq'] = c;
              }
              if (c.characteristicUuid == GoProUuids.settingResp) {
                chars['settingResp'] = c;
              }
              if (c.characteristicUuid == GoProUuids.queryReq) {
                chars['queryReq'] = c;
              }
              if (c.characteristicUuid == GoProUuids.queryResp) {
                chars['queryResp'] = c;
              }
            }
          }
        }

        _charCache[id] = chars;

        if (![
          'commandReq',
          'commandResp',
          'settingReq',
          'settingResp',
          'queryReq',
          'queryResp',
        ].every(chars.containsKey)) {
          throw StateError('Device does not expose Open GoPro BLE');
        }
        for (final subscription
            in _subscriptions.remove(id) ?? <StreamSubscription>[]) {
          await subscription.cancel();
        }
        _protocols.remove(id)?.close(StateError('Reconnecting'));
        final protocol = GoProProtocol(
          (channel, packet) =>
              chars['${channel}Req']!.write(packet, withoutResponse: false),
        );
        _protocols[id] = protocol;
        final subscriptions = <StreamSubscription>[];
        _subscriptions[id] = subscriptions;
        for (final channel in ['command', 'query', 'setting']) {
          final response = chars['${channel}Resp']!;
          subscriptions.add(
            response.onValueReceived.listen(
              (value) => protocol.receive(channel, value),
            ),
          );
          await response.setNotifyValue(true);
        }
        subscriptions.add(
          device.connectionState.listen((state) {
            if (state == BluetoothConnectionState.disconnected) {
              protocol.close(StateError('Camera $id disconnected'));
              _protocols.remove(id);
              _expectedModes.remove(id);
              _verified.remove(id);
              _keepAliveTimers.remove(id)?.cancel();
              _batteryPollTimers.remove(id)?.cancel();
              final i = _devices.indexWhere((d) => d.id == id);
              if (i >= 0) {
                _devices[i] = _devices[i].copyWith(isConnected: false);
              }
              notifyListeners();
            }
          }),
        );
        await protocol.exchange('command', [0x50]);
        await _readHardware(id);
        try {
          await syncCameraClock(id);
        } catch (e) {
          debugPrint('Clock sync skipped on $id: $e');
        }
        final index = _devices.indexWhere((d) => d.id == id);
        if (index >= 0) {
          _devices[index] = _devices[index].copyWith(isConnected: true);
        }
        notifyListeners();

        // Register for push status updates (battery + storage)
        await _registerStatusNotifications(id);

        // Initial battery + storage query
        await queryBatteryAndStorage(id);

        // Start keep-alive timer (every 28s, GoPro timeout is ~60s)
        _startKeepAlive(id);

        // Start battery polling timer (every 30s)
        _startBatteryPolling(id);

        await _rememberCamera(id);
        if (_keepAwake) {
          try {
            await _holdAwake(id);
          } catch (e) {
            debugPrint('Keep awake skipped on $id: $e');
          }
        }
      }
    } catch (e) {
      await disconnectDevice(id);
      debugPrint("Connection Error: $e");
      rethrow;
    }
  }

  Future<void> _registerStatusNotifications(String id) async {
    await _protocol(id).exchange('query', [0x53, 70, 54]);
  }

  Future<void> queryBatteryAndStorage(String id) async {
    if (capture.busy || capture.active) return;
    try {
      await refreshStatus(id);
    } catch (e) {
      debugPrint('Status query failed: $e');
    }
  }

  void _startKeepAlive(String id) {
    _keepAliveTimers[id]?.cancel();
    _keepAliveTimers[id] = Timer.periodic(const Duration(seconds: 3), (
      _,
    ) async {
      if (capture.busy && capture.phase != CapturePhase.synchronizing) return;
      try {
        await _protocol(id).exchange('setting', [91, 1, 66]);
      } catch (e) {
        debugPrint('Keep alive failed: $e');
      }
    });
  }

  void _startBatteryPolling(String id) {
    _batteryPollTimers[id]?.cancel();
    _batteryPollTimers[id] = Timer.periodic(
      const Duration(seconds: 30),
      (_) => queryBatteryAndStorage(id),
    );
  }

  /// Restores the camera's own auto power-off, then disconnects.
  Future<void> releaseAndDisconnect(String id) async {
    try {
      await _releaseAwake(id);
    } catch (e) {
      debugPrint('Auto power-off not restored on $id: $e');
    }
    await disconnectDevice(id);
  }

  /// Disconnect a device cleanly
  Future<void> disconnectDevice(String id) async {
    _protocols.remove(id)?.close(StateError('Disconnected'));
    _verified.remove(id);
    _expectedModes.remove(id);
    for (final subscription
        in _subscriptions.remove(id) ?? <StreamSubscription>[]) {
      await subscription.cancel();
    }
    _keepAliveTimers[id]?.cancel();
    _keepAliveTimers.remove(id);
    _batteryPollTimers[id]?.cancel();
    _batteryPollTimers.remove(id);

    if (_isMobilePlatform) {
      try {
        await _bleDevices[id]?.disconnect();
      } catch (e) {
        debugPrint("Disconnect error: $e");
      }
    }

    final index = _devices.indexWhere((d) => d.id == id);
    if (index != -1) {
      _devices[index] = _devices[index].copyWith(
        isConnected: false,
        batteryLevel: 0,
      );
    }
    _charCache.remove(id);
    notifyListeners();
  }

  // ─── MODE SWITCHING ────────────────────────────────────────

  Future<void> requestExternalControl(String id) async {
    final response = await _protocol(id).exchange(
      'command',
      [0xF1, 0x69, 8, 2],
      protobuf: true,
      responseAction: 0xE9,
    );
    if (decodeProto(response.sublist(2))[1]?.first != 1) {
      throw StateError('Camera $id denied external control');
    }
  }

  Future<void> setPresetGroup(String id, int groupId) async {
    await _protocol(
      id,
    ).exchange('command', [0x3E, 2, (groupId >> 8) & 255, groupId & 255]);
    await _waitIdle(id);
    if (await _status(id, 96) != groupId) {
      throw StateError('Preset group did not settle on $id');
    }
  }

  Future<void> _selectMode(String id, int mode) async {
    await stopShutter(id);
    await requestExternalControl(id);
    // Discover preset IDs on this camera/firmware. Never use a guessed preset ID.
    final response = await _protocol(id).exchange(
      'query',
      [0xF5, 0x72, 24, 1, 32, 1],
      protobuf: true,
      responseAction: 0xF2,
    );
    final matching = decodePresets(
      response.sublist(2),
    ).where((p) => p.mode == mode).toList();
    if (matching.isEmpty) {
      throw UnsupportedError(
        'Camera $id has no available preset for mode $mode; enable Pro controls on camera',
      );
    }
    await setPresetGroup(id, matching.first.group);
    final activePreset = await _status(id, 97);
    final preset =
        matching.where((p) => p.id == activePreset).firstOrNull ??
        matching.first;
    await _protocol(id).exchange('command', [
      0x40,
      4,
      (preset.id >> 24) & 255,
      (preset.id >> 16) & 255,
      (preset.id >> 8) & 255,
      preset.id & 255,
    ]);
    await _waitIdle(id);
    if (await _status(id, 89) != mode || await _status(id, 97) != preset.id) {
      throw StateError('Camera $id did not enter the requested preset');
    }
    _expectedModes[id] = mode;
    _verified[id] = {};
  }

  Future<void> setPhotoFormat(String id, String format) async {
    final value = GoProSettings.photoOutput[format];
    if (value == null) {
      throw UnsupportedError('Unsupported single photo format: $format');
    }
    await _writeSetting(id, 125, value);
  }

  Future<void> setPhotoMode(
    String id, {
    String photoFormat = 'SuperPhoto',
  }) async {
    await _selectMode(id, 16);
    await setPhotoFormat(id, photoFormat);
  }

  Future<void> setVideoMode(String id) => _selectMode(id, 12);
  Future<void> setTimeLapseMode(String id) => _selectMode(id, 20);
  Future<void> setAllCamerasMode(
    String mode, {
    String photoFormat = 'SuperPhoto',
  }) async {
    if (capture.active || capture.busy) throw StateError('Capture is busy');
    for (final cam in _devices.where((d) => d.isConnected).toList()) {
      if (mode == 'video') {
        await setVideoMode(cam.id);
      } else if (mode == 'timelapse') {
        await setTimeLapseMode(cam.id);
      } else {
        await setPhotoMode(cam.id, photoFormat: photoFormat);
      }
    }
  }

  Future<List<int>> _capabilities(String id, int setting) async =>
      (await _capabilityMap(id, [setting]))[setting] ?? [];

  /// Supported options per setting in the camera's current preset.
  Future<Map<int, List<int>>> _capabilityMap(String id, List<int> ids) async {
    final raw = decodeTlvMulti(
      await _protocol(id).exchange('query', [0x32, ...ids]),
    );
    return {
      for (final e in raw.entries)
        e.key: [
          for (final v in e.value)
            if (v.isNotEmpty) bigEndian(v),
        ],
    };
  }

  Future<void> _writeSetting(String id, int settingId, int value) async {
    const labels = <int, String>{
      2: 'Resolution',
      3: 'Frame rate',
      234: 'Frame rate',
      121: 'Video lens',
      122: 'Photo lens',
      125: 'Photo output',
      171: 'Photo interval',
      172: 'Interval duration',
      97: 'Photo timer',
      177: 'Night photo',
      182: 'Bitrate',
      156: 'Video duration',
      167: 'HindSight',
      168: 'Scheduled capture',
    };
    _settingProgress[id]?.call(
      'Applying ${labels[settingId] ?? 'camera option'}; awaiting confirmation',
    );
    await _waitIdle(id);
    if (!(await _capabilities(id, settingId)).contains(value)) {
      throw UnsupportedError(
        'Camera $id does not support setting $settingId=$value in this preset',
      );
    }
    await _protocol(id).exchange('setting', [settingId, 1, value]);
    await _waitIdle(id);
    final readback = await _query(id, 0x12, [settingId]);
    if (readback[settingId] == null ||
        bigEndian(readback[settingId]!) != value) {
      throw StateError('Camera $id did not confirm setting $settingId=$value');
    }
    (_verified[id] ??= {})[settingId] = value;
  }

  // ─── RIG-WIDE SETTINGS (catalog driven) ───────────────────

  /// Options this camera accepts for each catalog setting in its current preset.
  /// Settings the model does not know are simply absent.
  Future<Map<int, List<int>>> readSupportedSettings(String id) async {
    if (capture.active || capture.busy) throw StateError('Stop capture first');
    await _waitIdle(id);
    final ids = [for (final spec in goProSettingCatalog) spec.id];
    final result = <int, List<int>>{};
    // Small batches keep each BLE response within one reassembled message.
    for (var i = 0; i < ids.length; i += 12) {
      final batch = ids.sublist(i, (i + 12).clamp(0, ids.length));
      result.addAll(await _capabilityMap(id, batch));
    }
    result.removeWhere((_, options) => options.isEmpty);
    return result;
  }

  /// Current value of each requested setting on one camera.
  Future<Map<int, int>> readSettingValues(String id, List<int> ids) async {
    final out = <int, int>{};
    for (var i = 0; i < ids.length; i += 12) {
      final batch = ids.sublist(i, (i + 12).clamp(0, ids.length));
      final values = await _query(id, 0x12, batch);
      for (final e in values.entries) {
        if (e.value.isNotEmpty) out[e.key] = bigEndian(e.value);
      }
    }
    return out;
  }

  /// Options every connected camera supports: the only values that keep a
  /// mixed rig identical.
  Future<Map<int, List<int>>> commonSupportedSettings() async {
    final cameras = _devices.where((d) => d.isConnected).toList();
    if (cameras.isEmpty) {
      throw StateError('Connect GoPros over Bluetooth first');
    }
    Map<int, List<int>>? common;
    for (final camera in cameras) {
      final supported = await readSupportedSettings(camera.id);
      common = common == null
          ? supported
          : {
              for (final e in common.entries)
                if (supported[e.key] != null)
                  e.key: e.value.where(supported[e.key]!.contains).toList(),
            };
    }
    common!.removeWhere((_, options) => options.isEmpty);
    return common;
  }

  /// Writes one setting to every connected camera, verifying each by read-back.
  /// Returns camera name → null on success, or the error text.
  Future<Map<String, String?>> applySettingToAll(
    int settingId,
    int value,
  ) async {
    if (capture.active || capture.busy) throw StateError('Stop capture first');
    final results = <String, String?>{};
    for (final camera in _devices.where((d) => d.isConnected).toList()) {
      try {
        await _writeSetting(camera.id, settingId, value);
        results[camera.name] = null;
      } catch (e) {
        results[camera.name] = '$e';
      }
    }
    notifyListeners();
    return results;
  }

  /// Sets the camera clock to the phone's local time (with UTC offset), so
  /// file timestamps of all cameras line up. Falls back to the older command.
  Future<void> syncCameraClock(String id) async {
    final now = DateTime.now();
    final date = [
      (now.year >> 8) & 255,
      now.year & 255,
      now.month,
      now.day,
      now.hour,
      now.minute,
      now.second,
    ];
    final offset = now.timeZoneOffset.inMinutes;
    try {
      await _protocol(id).exchange('command', [
        0x0F,
        10,
        ...date,
        (offset >> 8) & 255,
        offset & 255,
        0,
      ]);
    } on GoProRejected {
      await _protocol(id).exchange('command', [0x0D, 7, ...date]);
    }
  }

  Future<void> syncAllCameraClocks() async {
    for (final camera in _devices.where((d) => d.isConnected).toList()) {
      await syncCameraClock(camera.id);
    }
  }

  // ─── HOTSPOT / TETHERING & MEDIA TRANSFER ─────────────────

  Future<({String ssid, String password})> readWifiCredentials(
    String id,
  ) async {
    if (capture.active || capture.busy) throw StateError('Stop capture first');
    final chars = _charCache[id];
    if (chars?['wifiSsid'] == null || chars?['wifiPassword'] == null) {
      throw StateError('Reconnect this GoPro to read its Wi-Fi credentials');
    }
    String decode(List<int> bytes) =>
        utf8.decode(bytes).replaceAll('\u0000', '').trim();
    final ssid = decode(await chars!['wifiSsid']!.read());
    final password = decode(await chars['wifiPassword']!.read());
    if (ssid.isEmpty || password.length < 8) {
      throw StateError('Invalid camera Wi-Fi credentials');
    }
    return (ssid: ssid, password: password);
  }

  Future<void> joinCameraWifi(String id) async {
    final credentials = await readWifiCredentials(id);
    await stopAllPreviews();
    await _protocol(id).exchange('command', [0x17, 1, 1]);
    var apReady = false;
    for (var i = 0; i < 15; i++) {
      if (await _status(id, 69) == 1) {
        apReady = true;
        break;
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    if (!apReady) throw StateError('Camera Wi-Fi did not become ready');
    await SystemSettingsService.joinCameraWifi(
      credentials.ssid,
      credentials.password,
    );
    for (var attempt = 0; attempt < 15; attempt++) {
      // Every direct AP has the same IP. Match its serial before trusting it.
      for (var i = 0; i < _devices.length; i++) {
        _devices[i].wifiIpAddress = null;
        _devices[i].isWifiConnected = false;
      }
      if (await _associateIp('10.5.5.9') &&
          _devices.any((c) => c.id == id && c.isWifiConnected)) {
        notifyListeners();
        return;
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    throw StateError(
      'Wi-Fi joined, but the selected camera identity could not be verified',
    );
  }

  Future<ImportReport> importAllConnectedCameras(
    String destination, {
    bool saveToGallery = false,
    void Function(String)? onStatus,
    bool Function(GoProMediaItem item)? include,
  }) async {
    if (_isSyncingMedia || capture.active || capture.busy) {
      throw StateError('Stop capture and other transfers first');
    }
    final cameras = _devices
        .where((c) => c.isConnected)
        .toList(growable: false);
    if (cameras.isEmpty) {
      throw StateError('Connect GoPros over Bluetooth first');
    }
    _isSyncingMedia = true;
    _cancelImport = false;
    galleryFailures.clear();
    notifyListeners();
    final results = <CameraImportResult>[];
    try {
      for (var i = 0; i < cameras.length; i++) {
        final camera = cameras[i];
        if (_cancelImport) {
          results.add(
            CameraImportResult(
              camera.id,
              camera.name,
              error: 'Import cancelled',
            ),
          );
          continue;
        }
        var found = 0;
        try {
          onStatus?.call(
            '${i + 1}/${cameras.length}: joining ${camera.name}. Approve the phone Wi-Fi prompt.',
          );
          await joinCameraWifi(camera.id);
          final items = (await fetchAllMediaItemsFromAllCameras(
            cameraId: camera.id,
          )).where(include ?? (_) => true).toList();
          found = items.length;
          final count = await transferMediaItems(
            items,
            targetCapturesDirectory: destination,
            saveToNativeGallery: saveToGallery,
            onProgress: (n, total, fraction, message) {
              _syncProgress =
                  (i + (total == 0 ? 1 : (n - 1 + fraction) / total)) /
                  cameras.length;
              onStatus?.call('${camera.name}: $message ($n/$total)');
              notifyListeners();
            },
          );
          results.add(
            CameraImportResult(
              camera.id,
              camera.name,
              found: found,
              imported: count,
              error: count == found
                  ? null
                  : '${found - count} files need retry',
            ),
          );
        } catch (e) {
          results.add(
            CameraImportResult(
              camera.id,
              camera.name,
              found: found,
              error: '$e',
            ),
          );
        } finally {
          try {
            await SystemSettingsService.releaseCameraWifi();
          } catch (_) {}
        }
      }
    } finally {
      _isSyncingMedia = false;
      notifyListeners();
    }
    return ImportReport(results, destination);
  }

  /// Discovers IP addresses of GoPros connected to the phone's hotspot subnet or direct AP.
  /// Automatically inspects active network interfaces to find the real subnet.
  Future<List<String>> discoverGoProIps({List<String>? targetSubnets}) async {
    final List<String> subnets = [];

    // Auto-detect local active subnets from device network interfaces
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final parts = addr.address.split('.');
          if (parts.length == 4) {
            final detectedSubnet = '${parts[0]}.${parts[1]}.${parts[2]}';
            if (!subnets.contains(detectedSubnet) &&
                detectedSubnet != '127.0.0') {
              subnets.add(detectedSubnet);
            }
          }
        }
      }
    } catch (e) {
      debugPrint("NetworkInterface discovery notice: $e");
    }

    // Add fallback subnets
    final fallbackList = targetSubnets ?? <String>[];
    if (targetSubnets == null) subnets.clear();
    for (final s in fallbackList) {
      if (!subnets.contains(s)) subnets.add(s);
    }

    final List<String> discovered = [];
    _syncStatusMessage = 'Scanning network for connected GoPros...';
    notifyListeners();

    // 1. Quick check direct GoPro AP mode at 10.5.5.9
    try {
      final uri = Uri.parse('http://10.5.5.9:8080/gopro/camera/state');
      final res = await http
          .get(uri)
          .timeout(const Duration(milliseconds: 700));
      if (res.statusCode == 200) {
        discovered.add('10.5.5.9');
        debugPrint('Found GoPro at Direct AP IP: 10.5.5.9');
        await _associateIp('10.5.5.9');
      }
    } catch (_) {}

    // 2. Scan subnets concurrently
    for (final subnet in subnets) {
      final futures = <Future<void>>[];
      for (int i = 2; i <= 254; i++) {
        final ip = '$subnet.$i';
        futures.add(() async {
          try {
            final uri = Uri.parse('http://$ip:8080/gopro/camera/state');
            final response = await http
                .get(uri)
                .timeout(const Duration(milliseconds: 650));
            if (response.statusCode == 200) {
              discovered.add(ip);
              debugPrint('Found GoPro at IP: $ip');

              await _associateIp(ip);
            }
          } catch (_) {}
        }());

        if (futures.length >= 35) {
          await Future.wait(futures);
          futures.clear();
          if (discovered.length >=
                  _devices.where((d) => d.isConnected).length &&
              _devices.isNotEmpty) {
            break;
          }
        }
      }
      if (futures.isNotEmpty) await Future.wait(futures);
      if (discovered.isNotEmpty) break;
    }

    notifyListeners();
    return discovered;
  }

  /// Fetch list of all media on a GoPro SD card over HTTP
  Future<Map<String, dynamic>?> fetchMediaList(String ip) async {
    try {
      final uri = Uri.parse('http://$ip:8080/gopro/media/list');
      final res = await http.get(uri).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('Error fetching media list from $ip: $e');
    }
    return null;
  }

  /// Get the most recently captured photo or video file details
  Future<Map<String, String>?> getLastCapturedMedia(String ip) async {
    final mediaList = await fetchMediaList(ip);
    if (mediaList == null || !mediaList.containsKey('media')) return null;

    final mediaDirs = mediaList['media'] as List<dynamic>?;
    if (mediaDirs == null || mediaDirs.isEmpty) return null;

    final lastDir = mediaDirs.last as Map<String, dynamic>;
    final dirName = lastDir['d'] as String? ?? '100GOPRO';
    final files = lastDir['fs'] as List<dynamic>?;
    if (files == null || files.isEmpty) return null;

    final lastFile = files.last as Map<String, dynamic>;
    final fileName = lastFile['n'] as String;

    return {
      'directory': dirName,
      'filename': fileName,
      'url': 'http://$ip:8080/videos/DCIM/$dirName/$fileName',
    };
  }

  String? _previewCameraId;
  bool _previewTransition = false;
  String? get previewCameraId => _previewCameraId;

  Future<bool> startLiveStream(String id) async {
    if (_previewTransition ||
        capture.active ||
        capture.busy ||
        _isSyncingMedia) {
      throw StateError('Stop capture and transfers before opening preview.');
    }
    if (_previewCameraId != null && _previewCameraId != id) {
      throw StateError(
        'Close the current preview before choosing another camera.',
      );
    }
    final candidates = _devices.where((d) => d.id == id && d.isConnected);
    if (candidates.isEmpty) throw StateError('Camera disconnected');
    final ip = candidates.first.wifiIpAddress;
    if (ip == null || ip.isEmpty) {
      throw StateError('Join this camera’s Wi-Fi, then discover its address.');
    }
    _previewTransition = true;
    _previewCameraId = id; // Retain ownership if the HTTP outcome is uncertain.
    try {
      final response = await http
          .get(Uri.parse('http://$ip:8080/gopro/camera/stream/start?port=8554'))
          .timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) {
        throw HttpException('Preview returned HTTP ${response.statusCode}');
      }
      return true;
    } finally {
      _previewTransition = false;
      notifyListeners();
    }
  }

  Future<bool> stopLiveStream(String id) async {
    final candidates = _devices.where((d) => d.id == id);
    if (candidates.isEmpty || candidates.first.wifiIpAddress == null) {
      return false;
    }
    try {
      final ip = candidates.first.wifiIpAddress;
      final response = await http
          .get(Uri.parse('http://$ip:8080/gopro/camera/stream/stop'))
          .timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return false;
      if (_previewCameraId == id) _previewCameraId = null;
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> stopAllPreviews() async {
    if (_previewTransition) {
      throw StateError('Wait for the preview connection to finish.');
    }
    final id = _previewCameraId;
    if (id != null && !await stopLiveStream(id)) {
      throw StateError(
        'Preview Stop was not confirmed. Reconnect camera Wi-Fi and retry.',
      );
    }
  }

  Future<bool> setLivePreviewMode(
    String id, {
    required bool multiStream,
  }) async => false;

  /// A saved-media thumbnail is not a live preview.
  Future<String?> getLivePreviewFrameUrl(String id) async {
    final candidates = _devices.where((d) => d.id == id);
    if (candidates.isEmpty) return null;
    final ip = candidates.first.wifiIpAddress;
    if (ip == null) return null;
    final media = await getLastCapturedMedia(ip);
    if (media == null) return null;
    return Uri.http('$ip:8080', '/gopro/media/thumbnail', {
      'path': '${media['directory']}/${media['filename']}',
    }).toString();
  }

  /// Test GoPro HTTP Connection and measure latency
  Future<Map<String, dynamic>> testCameraHttpConnection(String ip) async {
    final stopwatch = Stopwatch()..start();
    try {
      final uri = Uri.parse('http://$ip:8080/gopro/camera/state');
      final res = await http
          .get(uri)
          .timeout(const Duration(milliseconds: 1500));
      stopwatch.stop();
      if (res.statusCode == 200) {
        return {
          'success': true,
          'latencyMs': stopwatch.elapsedMilliseconds,
          'statusCode': res.statusCode,
          'data': jsonDecode(res.body),
        };
      }
    } catch (e) {
      stopwatch.stop();
      return {
        'success': false,
        'latencyMs': stopwatch.elapsedMilliseconds,
        'error': e.toString(),
      };
    }
    return {'success': false, 'latencyMs': stopwatch.elapsedMilliseconds};
  }

  /// Download to a partial file; only rename once length and stream complete.
  Future<bool> downloadMediaFile(
    String ip,
    String directory,
    String filename,
    String targetFilePath, {
    Function(double progress)? onProgress,
    void Function(String status)? onStatus,
    int? expectedBytes,
  }) async {
    if (![
      directory,
      filename,
    ].every((s) => RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(s) && s != '..')) {
      throw ArgumentError('Invalid camera media path');
    }
    final client = http.Client();
    final partial = File('$targetFilePath.part');
    IOSink? sink;
    var keepPartial = true;
    try {
      // Resume an interrupted download (multi-GB video chapters) with Range.
      final resumeFrom = await partial.exists() ? await partial.length() : 0;
      final request = http.Request(
        'GET',
        Uri.parse('http://$ip:8080/videos/DCIM/$directory/$filename'),
      );
      if (resumeFrom > 0) request.headers['Range'] = 'bytes=$resumeFrom-';
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 15));
      final resumed = resumeFrom > 0 && response.statusCode == 206;
      if (response.statusCode != 200 && !resumed) {
        throw HttpException('HTTP ${response.statusCode}');
      }
      await partial.parent.create(recursive: true);
      // Checksum while downloading, so a 10 GB video is never read twice.
      final digestSink = _DigestSink();
      final hasher = sha256.startChunkedConversion(digestSink);
      if (resumed) {
        onStatus?.call('Checking the part already downloaded');
        await for (final chunk in partial.openRead()) {
          hasher.add(chunk);
        }
      }
      sink = partial.openWrite(
        mode: resumed ? FileMode.append : FileMode.write,
      );
      var received = resumed ? resumeFrom : 0;
      final length = response.contentLength == null
          ? (expectedBytes ?? 0)
          : response.contentLength! + (resumed ? resumeFrom : 0);
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 30),
      )) {
        if (_cancelImport) throw StateError('Import cancelled');
        sink.add(chunk);
        hasher.add(chunk);
        received += chunk.length;
        if (length > 0) onProgress?.call((received / length).clamp(0, 1));
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (received == 0 ||
          (length > 0 && received != length) ||
          (expectedBytes != null &&
              expectedBytes > 0 &&
              received != expectedBytes)) {
        // Wrong size after a full transfer: the partial file is not trustworthy.
        keepPartial = false;
        throw const FormatException('Incomplete media download');
      }
      hasher.close();
      await partial.rename(targetFilePath);
      _downloadDigests[targetFilePath] = digestSink.value.toString();
      return true;
    } catch (e) {
      debugPrint('Download failed ($filename): $e');
      return false;
    } finally {
      await sink?.close();
      client.close();
      if (!keepPartial && await partial.exists()) await partial.delete();
    }
  }

  /// Sync captures from ALL connected GoPros over Hotspot Wi-Fi directly to the project's capture folder
  Future<int> syncCapturesFromAllCameras(
    String targetCapturesDirectory, {
    Function(int current, int total, String status)? onProgress,
  }) async {
    if (_isSyncingMedia || capture.active || capture.busy) {
      throw StateError('Stop capture before transferring media');
    }
    _isSyncingMedia = true;
    _syncProgress = 0;
    notifyListeners();
    try {
      final items = await fetchAllMediaItemsFromAllCameras();
      final count = await transferMediaItems(
        items,
        targetCapturesDirectory: targetCapturesDirectory,
        onProgress: (current, total, fraction, status) {
          _syncProgress = total == 0 ? 0 : (current - 1 + fraction) / total;
          _syncStatusMessage = status;
          notifyListeners();
          onProgress?.call(current, total, status);
        },
      );
      _syncStatusMessage = 'Downloaded $count of ${items.length} files';
      _syncProgress = items.isEmpty ? 0 : count / items.length;
      return count;
    } finally {
      _isSyncingMedia = false;
      notifyListeners();
    }
  }

  /// Browse and list all media files from all connected GoPros on Wi-Fi
  Future<List<GoProMediaItem>> fetchAllMediaItemsFromAllCameras({
    String? cameraId,
  }) async {
    final connectedCameras = _devices.where((d) => d.isConnected).toList();
    if (connectedCameras.isEmpty) return [];

    if (cameraId == null &&
        connectedCameras.any(
          (c) => c.wifiIpAddress == null || c.wifiIpAddress!.isEmpty,
        )) {
      await discoverGoProIps();
    }

    final camerasWithIp = _devices
        .where(
          (d) =>
              d.isConnected &&
              (cameraId == null || d.id == cameraId) &&
              d.wifiIpAddress != null &&
              d.wifiIpAddress!.isNotEmpty,
        )
        .toList();
    final List<GoProMediaItem> allItems = [];

    for (final cam in camerasWithIp) {
      final ip = cam.wifiIpAddress!;
      if (!await _associateIp(ip) ||
          !_devices.any((c) => c.id == cam.id && c.wifiIpAddress == ip)) {
        throw StateError(
          'Camera identity changed on Wi-Fi. Join ${cam.name} again.',
        );
      }
      final mediaList = await fetchMediaList(ip);
      if (mediaList == null || !mediaList.containsKey('media')) {
        throw StateError('Could not read the SD card on ${cam.name}');
      }

      final mediaDirs = mediaList['media'] as List<dynamic>?;
      if (mediaDirs == null) continue;

      for (final dir in mediaDirs) {
        final dirName = dir['d'] as String? ?? '100GOPRO';
        final files = dir['fs'] as List<dynamic>?;
        if (files == null) continue;

        for (final f in expandMediaEntries(files)) {
          final filename = f['n'] as String? ?? '';
          final size = (f['s'] is int)
              ? f['s'] as int
              : int.tryParse(f['s']?.toString() ?? '0') ?? 0;
          final modTimeSec = (f['mod'] is int)
              ? f['mod'] as int
              : int.tryParse(f['mod']?.toString() ?? '0') ?? 0;
          final createTime = modTimeSec > 0
              ? DateTime.fromMillisecondsSinceEpoch(modTimeSec * 1000)
              : null;
          final isVid = filename.toLowerCase().endsWith('.mp4');

          allItems.add(
            GoProMediaItem(
              cameraName: cam.name,
              cameraId: cam.id,
              ip: ip,
              directory: dirName,
              filename: filename,
              url: 'http://$ip:8080/videos/DCIM/$dirName/$filename',
              sizeBytes: size,
              modifiedTime: createTime,
              isVideo: isVid,
            ),
          );
        }
      }
    }

    // Sort newest first
    allItems.sort((a, b) {
      if (a.modifiedTime != null && b.modifiedTime != null) {
        return b.modifiedTime!.compareTo(a.modifiedTime!);
      }
      return b.filename.compareTo(a.filename);
    });

    return allItems;
  }

  /// Download a list of media items to target folder and optionally save to native phone gallery (DCIM/KOSMOS3D)
  Future<int> transferMediaItems(
    List<GoProMediaItem> items, {
    required String targetCapturesDirectory,
    bool saveToNativeGallery = true,
    Function(int current, int total, double fileProgress, String status)?
    onProgress,
  }) async {
    if (capture.active || capture.busy) {
      throw StateError('Stop capture before importing files.');
    }
    if (!_isSyncingMedia) {
      _cancelImport = false;
      galleryFailures.clear();
    }
    await stopAllPreviews();
    final targetDir = Directory(targetCapturesDirectory);
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    int successCount = 0;
    final total = items.length;

    for (int i = 0; i < items.length; i++) {
      if (_cancelImport) break;
      final item = items[i];
      final status = 'Downloading ${item.filename} from ${item.cameraName}...';
      onProgress?.call(i + 1, total, 0.0, status);

      if (![item.directory, item.filename].every(
        (s) =>
            RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(s) && s != '.' && s != '..',
      )) {
        throw FormatException('Invalid media filename');
      }
      final identity =
          (_serials[item.cameraId] ??
                  (item.cameraId.isEmpty ? item.ip : item.cameraId))
              .replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      final safeDirectory = item.directory.replaceAll(
        RegExp(r'[^A-Za-z0-9_-]'),
        '_',
      );
      final localName = '${identity}_${safeDirectory}_${item.filename}';
      final savePath = '${targetDir.path}/$localName';
      final existing = File(savePath);
      final receipt = File('$savePath.receipt.json');
      var verified = false;
      if (await existing.exists() && await receipt.exists()) {
        try {
          // Photos are re-hashed (cheap). Multi-GB videos are matched by size
          // and camera timestamp: re-hashing them on every import took minutes.
          final info = jsonDecode(await receipt.readAsString());
          final length = await existing.length();
          verified =
              info['bytes'] == length &&
              info['sourceModified'] == item.modifiedTime?.toIso8601String() &&
              (length > 256 * 1024 * 1024 ||
                  info['sha256'] ==
                      (await sha256.bind(existing.openRead()).first)
                          .toString());
        } catch (_) {}
      }
      if (verified &&
          await existing.exists() &&
          (item.sizeBytes <= 0 || await existing.length() == item.sizeBytes)) {
        successCount++;
        if (saveToNativeGallery) {
          await _exportGallery(receipt, savePath, item.filename);
        }
        onProgress?.call(
          i + 1,
          total,
          1,
          'Already downloaded: ${item.filename}',
        );
        continue;
      }
      final ok = await downloadMediaFile(
        item.ip,
        item.directory,
        item.filename,
        savePath,
        expectedBytes: item.sizeBytes,
        onProgress: (prog) {
          onProgress?.call(i + 1, total, prog, status);
        },
      );

      if (ok) {
        final digest =
            _downloadDigests.remove(savePath) ??
            (await sha256.bind(existing.openRead()).first).toString();
        final tempReceipt = File('${receipt.path}.part');
        await tempReceipt.writeAsString(
          jsonEncode({
            'cameraId': item.cameraId,
            'serial': _serials[item.cameraId],
            'source': '${item.directory}/${item.filename}',
            'sourceModified': item.modifiedTime?.toIso8601String(),
            'bytes': await existing.length(),
            'sha256': digest,
            'importedAt': DateTime.now().toUtc().toIso8601String(),
          }),
          flush: true,
        );
        await tempReceipt.rename(receipt.path);
        successCount++;
        // Copy to native phone gallery if enabled
        if (saveToNativeGallery) {
          await _exportGallery(receipt, savePath, item.filename);
        }
      }
    }

    return successCount;
  }

  Future<void> _exportGallery(
    File receipt,
    String path,
    String filename,
  ) async {
    final info =
        jsonDecode(await receipt.readAsString()) as Map<String, dynamic>;
    if (info['galleryExported'] == true) return;
    final saved = await SystemSettingsService.saveToDeviceGallery(path);
    if (saved == null) galleryFailures.add(filename);
    info['galleryExported'] = saved != null;
    final temp = File('${receipt.path}.part');
    await temp.writeAsString(jsonEncode(info), flush: true);
    await temp.rename(receipt.path);
  }

  @override
  Future<void> applySettingsToDevice(
    String id,
    Map<String, String> settings, {
    String captureMode = 'photo',
  }) async {
    _validateSettings(settings);
    final photo = captureMode == 'photo';
    if (photo) {
      await setPhotoFormat(
        id,
        settings['Photo Format'] ?? settings['Photo Output'] ?? 'SuperPhoto',
      );
      // App-paced intervals: do not arm an autonomous camera interval as well.
      // Only where "off" (0) is an offered value: HERO13 lists 172 in the
      // single-photo preset but without 0.
      final timerValue = _cameraTimerValue(settings);
      final capabilities = await _capabilityMap(id, [171, 172, 97, 177]);
      for (final key in [97, 177]) {
        if (capabilities[key]?.contains(0) == true) {
          await _writeSetting(id, key, 0);
        }
      }
      if (timerValue == null) {
        for (final key in [171, 172]) {
          if (capabilities[key]?.contains(0) == true) {
            await _writeSetting(id, key, 0);
          }
        }
      } else {
        if (capabilities[171]?.contains(timerValue) != true) {
          throw UnsupportedError(
            'Camera $id has no ${settings['Interval']} photo interval timer; '
            'choose app timing',
          );
        }
        await _writeSetting(id, 171, timerValue);
        // Run length: unlimited if offered, else the longest (Stop ends it).
        final durations = (await _capabilityMap(id, [172]))[172] ?? [];
        if (durations.isNotEmpty) {
          await _writeSetting(
            id,
            172,
            durations.contains(0)
                ? 0
                : durations.reduce((a, b) => a > b ? a : b),
          );
        }
      }
    } else {
      if (settings['Resolution'] != null) {
        await _writeSetting(
          id,
          2,
          GoProSettings.resolution[settings['Resolution']] ??
              (throw ArgumentError('Resolution')),
        );
      }
      if (settings['FPS'] != null) {
        final fps =
            GoProSettings.fps[settings['FPS']] ?? (throw ArgumentError('FPS'));
        // HERO13 reports frame rate as setting 234; older models use 3.
        final options = await _capabilityMap(id, [3, 234]);
        final key = options[3]?.contains(fps) == true
            ? 3
            : options[234]?.contains(fps) == true
            ? 234
            : 3;
        await _writeSetting(id, key, fps);
      }
      if (settings['Bitrate'] != null) {
        await _writeSetting(
          id,
          182,
          GoProSettings.bitrate[settings['Bitrate']] ??
              (throw ArgumentError('Bitrate')),
        );
      }
      // Continuous recording: no duration limit (100) and HindSight off (4).
      final capabilities = await _capabilityMap(id, [156, 167]);
      for (final entry in const {156: 100, 167: 4}.entries) {
        if (capabilities[entry.key]?.contains(entry.value) == true) {
          await _writeSetting(id, entry.key, entry.value);
        }
      }
    }
    final lens = settings['Lens'];
    if (lens != null) {
      final key = photo ? 122 : 121;
      final supported = await _capabilities(id, key);
      final candidates = photo
          ? (lens == 'Linear'
                ? [32, 28, 10]
                : lens == 'Wide'
                ? [31, 27, 0]
                : <int>[])
          : [GoProSettings.videoLens[lens] ?? -1];
      final value = candidates.where(supported.contains).firstOrNull;
      if (value == null) {
        throw UnsupportedError(
          'Camera $id cannot use $lens in the selected mode',
        );
      }
      await _writeSetting(id, key, value);
    }
  }

  /// Setting 171 value when the interval runs on the camera timer, else null.
  static int? _cameraTimerValue(Map<String, String> settings) {
    if (settings['Interval Timing'] != cameraTimerTiming) return null;
    final seconds = double.tryParse(
      (settings['Interval'] ?? '').replaceAll('s', ''),
    );
    if (seconds == null) return null;
    // Keyed by milliseconds: doubles cannot be const map keys.
    return const {
      500: 2,
      1000: 3,
      2000: 4,
      3000: 10,
      5000: 5,
      10000: 6,
      30000: 7,
      60000: 8,
      120000: 9,
    }[(seconds * 1000).round()];
  }

  Future<void> applySettingsToCurrentMode(
    String id,
    Map<String, String> settings,
  ) async {
    if (capture.active || capture.busy) {
      throw StateError('Stop the active rig first');
    }
    _validateSettings(settings);
    final mode = await _status(id, 89);
    if (mode != 12 && mode != 16) {
      throw StateError('Select Single Photo or Video before applying settings');
    }
    await applySettingsToDevice(
      id,
      settings,
      captureMode: mode == 12 ? 'video' : 'photo',
    );
    updateCameraSettings(id, settings);
  }

  Future<void> applySettingsToAll(
    Map<String, String> settings, {
    String captureMode = 'photo',
  }) => prepareCapture(captureMode, settings);

  @override
  Future<void> triggerShutter(String id) async {
    await _protocol(id).exchange('command', [1, 1, 1]);
    if (_expectedModes[id] == 12 && await _status(id, 10) != 1) {
      throw StateError('Camera $id did not confirm video recording');
    }
  }

  @override
  Future<void> stopShutter(String id) async {
    await _protocol(id).exchange('command', [1, 1, 0]);
    await _waitIdle(id);
  }

  Future<void> triggerAllShutters() => capture.toggle();
  Future<void> stopAllShutters() => capture.stop();

  // ─── RIG STATUS ────────────────────────────────────────────

  /// Open GoPro status IDs shown in the rig control screen.
  static const statusIds = [
    70, // battery %
    54, // SD remaining KB
    34, // photos remaining
    35, // video remaining (s)
    38, // photos on card
    39, // videos on card
    33, // SD state
    6, // overheating
    85, // too cold
    68, // GPS lock
    8, // busy
    10, // encoding
    89, // flat mode
    69, // AP enabled
  ];

  final Map<String, Map<int, int>> _cameraStatus = {};

  /// Last status read per camera (see [statusIds]).
  Map<int, int> statusOf(String id) => _cameraStatus[id] ?? const {};

  /// Reads every status in [statusIds] that the camera reports.
  Future<Map<int, int>> refreshStatus(String id) async {
    final values = await _query(id, 0x13, statusIds);
    final status = {
      for (final e in values.entries)
        if (e.value.isNotEmpty) e.key: bigEndian(e.value),
    };
    _cameraStatus[id] = status;
    final index = _devices.indexWhere((d) => d.id == id);
    if (index >= 0) {
      final kb = status[54];
      _devices[index] = _devices[index].copyWith(
        batteryLevel: status[70],
        storageRemaining: kb == null
            ? null
            : '${(kb / 1048576).toStringAsFixed(1)} GB',
        isRecording: status[10] == 1,
      );
    }
    notifyListeners();
    return status;
  }

  Iterable<String> get connectedIds =>
      _devices.where((d) => d.isConnected).map((d) => d.id);

  /// Runs [action] on every camera in [ids] (all connected when null) and
  /// collects failures instead of stopping at the first one.
  Future<List<String>> forCameras(
    Future<void> Function(String id) action, {
    Iterable<String>? ids,
  }) async {
    if (capture.active || capture.busy) {
      throw StateError('Stop the capture session first');
    }
    final targets = (ids ?? connectedIds).toList();
    if (targets.isEmpty) throw StateError('Connect a camera first');
    final failures = <String>[];
    await Future.wait(
      targets.map((id) async {
        try {
          await action(id);
        } catch (e) {
          failures.add('${nameOf(id)}: $e');
        }
        try {
          await refreshStatus(id);
        } catch (_) {}
      }),
    );
    return failures;
  }

  String nameOf(String id) =>
      _devices.where((d) => d.id == id).firstOrNull?.displayName ?? id;

  // ─── CAPTURE CONTROL ───────────────────────────────────────

  /// Photo (16), video (12) or time-lapse (13) on one camera.
  Future<void> selectMode(String id, int mode) => _selectMode(id, mode);

  Future<void> startCapture(String id) async {
    await _waitIdle(id);
    await triggerShutter(id);
  }

  /// HiLight tag in the running video (camera must be recording).
  Future<void> addHiLightTag(String id) async {
    if (await _status(id, 10) != 1) {
      throw StateError('HiLight works while the camera records video');
    }
    await _protocol(id).exchange('command', [0x18]);
  }

  // ─── CAMERA OPTIONS ────────────────────────────────────────

  /// Camera access point on/off (needed for imports and live view).
  Future<void> setWifiAp(String id, bool enabled) async {
    await _protocol(id).exchange('command', [0x17, 1, enabled ? 1 : 0]);
    for (var i = 0; i < 10; i++) {
      if ((await _status(id, 69) == 1) == enabled) return;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    throw StateError('Camera Wi-Fi did not switch ${enabled ? 'on' : 'off'}');
  }

  /// GPS (setting 83) on/off, read back.
  Future<void> setGps(String id, bool enabled) =>
      _writeSetting(id, 83, enabled ? 1 : 0);

  // ─── KEEP AWAKE ────────────────────────────────────────────

  bool _keepAwake = true;
  bool get keepAwake => _keepAwake;

  /// Auto power-off value each camera had before KOSMOS set it to Never.
  final Map<String, int> _autoOffBefore = {};

  Future<void> setKeepAwake(bool enabled) async {
    _keepAwake = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('keep_cameras_awake', enabled);
    notifyListeners();
    final failures = await forCameras(
      (id) => enabled ? _holdAwake(id) : _releaseAwake(id),
    );
    if (failures.isNotEmpty) throw StateError(failures.join('\n'));
  }

  /// Sets auto power-off (setting 59) to Never and remembers the old value.
  Future<void> _holdAwake(String id) async {
    final options = await _capabilities(id, 59);
    if (!options.contains(0)) return;
    final current = (await readSettingValues(id, [59]))[59];
    if (current == null || current == 0) return;
    final serial = _serials[id] ?? id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('auto_off_$serial', current);
    _autoOffBefore[id] = current;
    await _writeSetting(id, 59, 0);
  }

  /// Restores the auto power-off value from before [_holdAwake].
  Future<void> _releaseAwake(String id) async {
    final serial = _serials[id] ?? id;
    final prefs = await SharedPreferences.getInstance();
    final before =
        _autoOffBefore.remove(id) ?? prefs.getInt('auto_off_$serial');
    if (before == null || _protocols[id] == null) return;
    await _writeSetting(id, 59, before);
    await prefs.remove('auto_off_$serial');
  }

  // ─── STORAGE ───────────────────────────────────────────────

  /// Deletes every file on the SD card over the camera Wi-Fi (Open GoPro
  /// "Delete All Files", HERO9 and newer), then confirms the card is empty.
  Future<void> eraseSdCard(String id) async {
    if (capture.active || capture.busy || _isSyncingMedia) {
      throw StateError('Stop capture and imports first');
    }
    _isSyncingMedia = true;
    notifyListeners();
    try {
      await joinCameraWifi(id);
      final ip = _devices.firstWhere((d) => d.id == id).wifiIpAddress!;
      final response = await http
          .get(
            Uri.parse(
              'http://$ip:8080/gp/gpControl/command/storage/delete/all',
            ),
          )
          .timeout(const Duration(seconds: 60));
      if (response.statusCode != 200) {
        throw HttpException('Camera answered ${response.statusCode}');
      }
      for (var i = 0; i < 30; i++) {
        final counts = await _query(id, 0x13, [38, 39]);
        if (bigEndian(counts[38] ?? [0]) == 0 &&
            bigEndian(counts[39] ?? [0]) == 0) {
          return;
        }
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      throw StateError('Camera still reports files after erasing');
    } finally {
      try {
        await SystemSettingsService.releaseCameraWifi();
      } catch (_) {}
      _isSyncingMedia = false;
      notifyListeners();
    }
  }

  /// Erases cameras one after another (each needs its own Wi-Fi).
  Future<List<String>> eraseSdCards(Iterable<String> ids) async {
    final failures = <String>[];
    for (final id in ids.toList()) {
      try {
        await eraseSdCard(id);
      } catch (e) {
        failures.add('${nameOf(id)}: $e');
      }
      try {
        await refreshStatus(id);
      } catch (_) {}
    }
    return failures;
  }

  // ─── POWER ─────────────────────────────────────────────────

  /// Sleep keeps Bluetooth listening: the camera wakes when KOSMOS connects.
  Future<void> sleepCamera(String id) async {
    await _releaseAwake(id).catchError((_) {});
    await _protocol(id).exchange('command', [0x05]);
    await disconnectDevice(id);
  }

  /// Power down switches the camera fully off; turn it on by hand.
  Future<void> powerDown(String id) async {
    await _releaseAwake(id).catchError((_) {});
    await _protocol(id).exchange('command', [0x04]);
    await disconnectDevice(id);
  }

  // ─── KNOWN CAMERAS ─────────────────────────────────────────

  static const _knownKey = 'known_cameras';

  /// Adds previously connected cameras to the list so they can be woken
  /// and connected without a scan.
  Future<void> loadKnownCameras() async {
    if (!_isMobilePlatform) return;
    final prefs = await SharedPreferences.getInstance();
    _keepAwake = prefs.getBool('keep_cameras_awake') ?? true;
    final known = prefs.getStringList(_knownKey) ?? [];
    for (final entry in known) {
      final split = entry.indexOf('|');
      if (split <= 0) continue;
      final id = entry.substring(0, split), name = entry.substring(split + 1);
      if (_devices.any((d) => d.id == id)) continue;
      _bleDevices[id] = BluetoothDevice.fromId(id);
      _devices.add(CameraDevice(id: id, name: name, batteryLevel: 0));
    }
    notifyListeners();
  }

  Future<void> _rememberCamera(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final known =
        (prefs.getStringList(_knownKey) ?? [])
            .where((e) => !e.startsWith('$id|'))
            .toList()
          ..add('$id|${nameOf(id)}');
    await prefs.setStringList(_knownKey, known);
  }

  Future<void> forgetCamera(String id) async {
    if (_protocols[id] != null) await disconnectDevice(id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _knownKey,
      (prefs.getStringList(_knownKey) ?? [])
          .where((e) => !e.startsWith('$id|'))
          .toList(),
    );
    _devices.removeWhere((d) => d.id == id);
    _bleDevices.remove(id);
    notifyListeners();
  }

  /// Connects (and so wakes) every listed camera that is not connected.
  Future<List<String>> connectAll() async {
    final failures = <String>[];
    for (final camera in _devices.where((d) => !d.isConnected).toList()) {
      try {
        await connectToDevice(camera.id);
      } catch (e) {
        failures.add('${camera.displayName}: $e');
      }
    }
    return failures;
  }

  // ─── LEGACY COMPAT ────────────────────────────────────────

  Future<void> toggleRecording(String id, bool start) async {
    if (capture.active || capture.busy) {
      throw StateError('Use the capture screen to control the active rig');
    }
    if (start) {
      await startCapture(id);
    } else {
      await stopShutter(id);
    }
    await refreshStatus(id);
  }

  void updateCameraSettings(String id, Map<String, String> newSettings) {
    final index = _devices.indexWhere((d) => d.id == id);
    if (index != -1) {
      final updatedSettings = Map<String, String>.from(
        _devices[index].currentSettings,
      )..addAll(newSettings);
      _devices[index] = _devices[index].copyWith(
        currentSettings: updatedSettings,
      );
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    capture.removeListener(notifyListeners);
    capture.dispose();
    for (final p in _protocols.values) {
      p.close(StateError('Service disposed'));
    }
    for (final subs in _subscriptions.values) {
      for (final sub in subs) {
        sub.cancel();
      }
    }
    for (final timer in _keepAliveTimers.values) {
      timer.cancel();
    }
    for (final timer in _batteryPollTimers.values) {
      timer.cancel();
    }
    super.dispose();
  }
}

class _GoProRigCamera implements RigCamera {
  _GoProRigCamera(this.service, this.id);
  final GoProService service;
  @override
  final String id;
  @override
  Future<void> configure(
    String mode,
    Map<String, String> settings,
    void Function(String) progress,
  ) => service._configure(id, mode, settings, progress);
  @override
  Future<void> verifyReady() => service._verifyReady(id);
  @override
  Future<void> start() => service.triggerShutter(id);
  @override
  Future<void> stop() => service.stopShutter(id);
}

/// Receives the single digest from a chunked SHA-256 conversion.
class _DigestSink implements Sink<Digest> {
  late Digest value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

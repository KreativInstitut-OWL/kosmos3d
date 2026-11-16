import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kosmos3d/models/camera_device.dart';
import 'package:kosmos3d/services/gopro_service.dart';

class ImportRig extends GoProService {
  final joined = <String>[];
  ImportRig() {
    devices.addAll(
      [
        'one',
        'two',
        'three',
      ].map((id) => CameraDevice(id: id, name: id, isConnected: true)),
    );
  }
  @override
  Future<void> joinCameraWifi(String id) async {
    joined.add(id);
    if (id == 'two') throw StateError('Join declined');
  }

  @override
  Future<List<GoProMediaItem>> fetchAllMediaItemsFromAllCameras({
    String? cameraId,
  }) async => [
    GoProMediaItem(
      cameraName: cameraId!,
      cameraId: cameraId,
      ip: '127.0.0.1',
      directory: '100GOPRO',
      filename: 'photo.JPG',
      url: '',
    ),
  ];
  @override
  Future<int> transferMediaItems(
    List<GoProMediaItem> items, {
    required String targetCapturesDirectory,
    bool saveToNativeGallery = true,
    String? projectName,
    Function(int, int, double, String)? onProgress,
  }) async => items.length;
}

class DownloadRig extends GoProService {
  int requests = 0;
  @override
  Future<bool> downloadMediaFile(
    String ip,
    String directory,
    String filename,
    String targetFilePath, {
    Function(double)? onProgress,
    void Function(String)? onStatus,
    int? expectedBytes,
  }) async {
    requests++;
    await File(targetFilePath).writeAsBytes([1, 2, 3, 4]);
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'bulk import reports failed camera, continues, and releases each network',
    () async {
      var releases = 0;
      const channel = MethodChannel('com.kosmos3d.kosmos3d/system_settings');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'releaseCameraWifi') releases++;
            return null;
          });
      final rig = ImportRig();
      final report = await rig.importAllConnectedCameras('unused');
      expect(rig.joined, ['one', 'two', 'three']);
      expect(report.imported, 2);
      expect(report.complete, false);
      expect(report.cameras[1].error, contains('Join declined'));
      expect(releases, 3);
      expect(rig.isSyncingMedia, false);
      rig.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    },
  );

  test(
    'same-sized corrupted local original is downloaded again using its receipt hash',
    () async {
      final dir = await Directory.systemTemp.createTemp('kosmos-import-test');
      final service = DownloadRig();
      final item = GoProMediaItem(
        cameraName: 'Camera',
        cameraId: 'stable-id',
        ip: '127.0.0.1',
        directory: '100GOPRO',
        filename: 'GP010001.JPG',
        url: '',
        sizeBytes: 4,
      );
      try {
        Future<int> run() => service.transferMediaItems(
          [item],
          targetCapturesDirectory: dir.path,
          saveToNativeGallery: false,
        );
        expect(await run(), 1);
        expect(await run(), 1);
        expect(service.requests, 1);
        final file = File('${dir.path}/stable-id_100GOPRO_GP010001.JPG');
        await file.writeAsBytes([9, 9, 9, 9]);
        expect(await run(), 1);
        expect(service.requests, 2);
        expect(await file.readAsBytes(), [1, 2, 3, 4]);
        expect(dir.listSync().where((f) => f.path.endsWith('.part')), isEmpty);
      } finally {
        service.dispose();
        await dir.delete(recursive: true);
      }
    },
  );
}

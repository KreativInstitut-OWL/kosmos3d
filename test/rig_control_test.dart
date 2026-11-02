import 'package:flutter_test/flutter_test.dart';
import 'package:kosmos3d/services/gopro_protocol.dart';
import 'package:kosmos3d/services/gopro_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Camera that answers statuses, settings, capabilities and commands.
class ControlCamera {
  final values = <int, int>{59: 4};
  final status = <int, int>{
    70: 81,
    54: 52428800,
    34: 1200,
    38: 7,
    39: 2,
    33: 0,
  };
  final commands = <int>[];
  final writes = <int, int>{};
  late final GoProProtocol protocol;
  final decoder = GoProPacketDecoder();
  ControlCamera() {
    protocol = GoProProtocol((channel, packet) async {
      final request = decoder.add(packet);
      if (request == null) return;
      final id = request[0];
      final reply = <int>[id, 0];
      if (channel == 'command') {
        commands.add(id);
      } else if (channel == 'setting') {
        values[id] = request[2];
        writes[id] = request[2];
      } else if (id == 0x13) {
        for (final s in request.skip(1)) {
          final v = status[s] ?? 0;
          reply.addAll([
            s,
            4,
            (v >> 24) & 255,
            (v >> 16) & 255,
            (v >> 8) & 255,
            v & 255,
          ]);
        }
      } else if (id == 0x12) {
        for (final s in request.skip(1)) {
          reply.addAll([s, 1, values[s] ?? 0]);
        }
      } else if (id == 0x32) {
        for (final s in request.skip(1)) {
          for (final option in s == 59 ? [0, 4] : <int>[]) {
            reply.addAll([s, 1, option]);
          }
        }
      }
      for (final part in GoProProtocol.packetize(reply)) {
        protocol.receive(channel, part);
      }
    });
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('status refresh decodes battery, storage and card counts', () async {
    final camera = ControlCamera();
    final service = GoProService.testConnection('a', camera.protocol);
    addTearDown(service.dispose);
    final status = await service.refreshStatus('a');
    expect(status[70], 81);
    expect(status[34], 1200);
    expect(service.devices.single.batteryLevel, 81);
    expect(service.devices.single.storageRemaining, '50.0 GB');
  });

  test('keep awake sets auto power-off to Never and restores it', () async {
    final camera = ControlCamera();
    final service = GoProService.testConnection('a', camera.protocol);
    addTearDown(service.dispose);
    await service.setKeepAwake(true);
    expect(camera.values[59], 0);
    expect(service.keepAwake, isTrue);
    await service.setKeepAwake(false);
    expect(camera.values[59], 4);
  });

  test(
    'sleep sends the Open GoPro sleep command (0x05), not power down',
    () async {
      final camera = ControlCamera();
      final service = GoProService.testConnection('a', camera.protocol);
      addTearDown(service.dispose);
      await service.sleepCamera('a');
      expect(camera.commands, contains(0x05));
      expect(camera.commands, isNot(contains(0x04)));
      expect(service.devices.single.isConnected, isFalse);
    },
  );

  test('HiLight is refused when the camera is not recording', () async {
    final camera = ControlCamera();
    final service = GoProService.testConnection('a', camera.protocol);
    addTearDown(service.dispose);
    await expectLater(service.addHiLightTag('a'), throwsStateError);
    expect(camera.commands, isNot(contains(0x18)));
  });
}

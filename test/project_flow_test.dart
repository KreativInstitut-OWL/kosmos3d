import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kosmos3d/models/camera_device.dart';
import 'package:kosmos3d/models/scan_project.dart';
import 'package:kosmos3d/providers/settings_provider.dart';
import 'package:kosmos3d/screens/project_flow.dart';
import 'package:kosmos3d/services/gopro_service.dart';
import 'package:kosmos3d/services/project_service.dart';

class FakeRig extends GoProService {
  final gate = Completer<void>();
  int prepares = 0;
  final _cams = [CameraDevice(id: 'cam1', name: 'GoPro 1', isConnected: true)];
  @override
  List<CameraDevice> get devices => _cams;
  @override
  Future<void> prepareCapture(String mode, Map<String, String> settings) async {
    prepares++;
    await gate.future;
  }
}

class FakeProjects extends ProjectService {
  FakeProjects() : super(loadOnStart: false);
  int creates = 0;
  @override
  Future<ScanProject> createProject(
    String name, {
    String captureMode = 'photo',
    bool smartCapture = false,
    Map<String, String>? cameraSettings,
  }) async {
    creates++;
    throw StateError('disk full');
  }
}

void main() {
  testWidgets(
    'double tap locks synchronization and project creation; error unlocks',
    (tester) async {
      SharedPreferences.setMockInitialValues({'language': 'en'});
      final rig = FakeRig();
      final projects = FakeProjects();
      final settings = SettingsProvider();
      addTearDown(rig.dispose);
      addTearDown(projects.dispose);
      addTearDown(settings.dispose);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<GoProService>.value(value: rig),
            ChangeNotifierProvider<ProjectService>.value(value: projects),
            ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          ],
          child: const MaterialApp(home: ProjectFlowScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Test scan');
      await tester.pumpAndSettle();
      for (var i = 0; i < 2; i++) {
        tester.widget<Stepper>(find.byType(Stepper)).onStepContinue!();
        await tester.pumpAndSettle();
      }
      final start = find.text('Start Capture');
      await tester.ensureVisible(start);
      await tester.pumpAndSettle();
      await tester.tap(start);
      await tester.pump();
      // The button is replaced by progress, so a second tap cannot land.
      expect(find.text('Start Capture'), findsNothing);
      tester.widget<Stepper>(find.byType(Stepper)).onStepContinue!();
      await tester.pump();
      expect(rig.prepares, 1);
      expect(projects.creates, 0);
      expect(
        find.byWidgetPredicate((w) => w is AbsorbPointer && w.absorbing),
        findsWidgets,
      );
      rig.gate.complete();
      await tester.pumpAndSettle();
      expect(projects.creates, 1);
      expect(find.textContaining('disk full'), findsOneWidget);
      expect(find.text('Start Capture'), findsWidgets);
    },
  );
}

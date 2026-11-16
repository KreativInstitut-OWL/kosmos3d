import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_text.dart';
import '../models/camera_device.dart';
import '../screens/device_manager.dart';
import '../screens/rig_control_screen.dart';
import '../services/capture_coordinator.dart';
import '../services/gopro_service.dart';
import 'camera_live_monitor.dart';

/// Horizontal strip of the rig's cameras. Tap a camera for its quick actions;
/// the last chip opens the full camera manager. Usable on any screen.
class CameraBar extends StatelessWidget {
  const CameraBar({super.key, this.dark = false, this.showManage = true});

  /// White text for dark backgrounds (capture screen).
  final bool dark;
  final bool showManage;

  @override
  Widget build(BuildContext context) {
    final goPro = context.watch<GoProService>();
    final cams = goPro.devices.where((d) => d.isConnected).toList();
    final primary = Theme.of(context).primaryColor;
    final ink = dark ? Colors.white : Theme.of(context).colorScheme.onSurface;
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          if (cams.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: AppText(
                  'No camera connected',
                  style: TextStyle(color: Colors.orange.shade400, fontSize: 13),
                ),
              ),
            ),
          for (final cam in cams)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ActionChip(
                avatar: Icon(
                  goPro.isLocating(cam.id)
                      ? Icons.notifications_active
                      : Icons.camera_alt,
                  size: 16,
                  color: primary,
                ),
                label: AppText(
                  '${cam.displayName}  ${cam.batteryLevel}%',
                  style: TextStyle(
                    fontSize: 12,
                    color: cam.batteryLevel <= 20 ? Colors.redAccent : ink,
                  ),
                ),
                backgroundColor: ink.withValues(alpha: 0.06),
                side: BorderSide(color: primary.withValues(alpha: 0.35)),
                onPressed: () => showCameraSheet(context, cam.id),
              ),
            ),
          if (showManage)
            ActionChip(
              avatar: Icon(Icons.add_link, size: 16, color: ink),
              label: AppText(
                cams.isEmpty ? 'Connect cameras' : 'Manage',
                style: TextStyle(fontSize: 12, color: ink),
              ),
              backgroundColor: ink.withValues(alpha: 0.06),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DeviceManagerScreen()),
              ),
            ),
        ],
      ),
    );
  }
}

/// Quick actions for one camera, all on one sheet.
Future<void> showCameraSheet(BuildContext context, String id) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _CameraSheet(id: id),
    );

class _CameraSheet extends StatefulWidget {
  const _CameraSheet({required this.id});
  final String id;

  @override
  State<_CameraSheet> createState() => _CameraSheetState();
}

class _CameraSheetState extends State<_CameraSheet> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, {String? done}) async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      if (done != null)
        messenger.showSnackBar(SnackBar(content: AppText(done)));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: AppText(describeError(e)),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rename(GoProService goPro, CameraDevice cam) async {
    final controller = TextEditingController(text: cam.customName ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const AppText('Rename camera'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: cam.name,
            helperText: 'Shown in this app. Empty = camera name.',
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const AppText('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const AppText('Save'),
          ),
        ],
      ),
    );
    if (name != null) await goPro.renameCamera(cam.id, name);
  }

  @override
  Widget build(BuildContext context) {
    final goPro = context.watch<GoProService>();
    final cam = goPro.devices.where((d) => d.id == widget.id).firstOrNull;
    if (cam == null) return const SizedBox(height: 120);
    final locating = goPro.isLocating(cam.id);
    final rigBusy = goPro.capture.active || goPro.capture.busy;

    Widget action(
      IconData icon,
      String label,
      VoidCallback? onTap, {
      Color? color,
    }) => SizedBox(
      width: 96,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 10),
          foregroundColor: color,
        ),
        onPressed: _busy ? null : onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22),
            const SizedBox(height: 4),
            AppText(
              label,
              style: const TextStyle(fontSize: 11),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppText(
                        cam.displayName,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      AppText(
                        '${goPro.modelFor(cam.id)} · ${cam.name} · '
                        'Battery ${cam.batteryLevel}%',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Rename',
                  icon: const Icon(Icons.edit),
                  onPressed: () => _rename(goPro, cam),
                ),
              ],
            ),
            if (_busy) const LinearProgressIndicator(),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                action(
                  locating
                      ? Icons.notifications_off
                      : Icons.notifications_active,
                  locating ? 'Stop locate' : 'Locate',
                  () => _run(
                    () => goPro.setLocate(cam.id, !locating),
                    done: locating ? null : 'Camera beeps until you stop it',
                  ),
                  color: locating ? Colors.orange : null,
                ),
                action(Icons.live_tv, 'Live view', () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => LiveViewScreen(cameraId: cam.id),
                    ),
                  );
                }),
                action(
                  Icons.photo_camera,
                  'Photo mode',
                  rigBusy
                      ? null
                      : () => _run(
                          () => goPro.selectMode(cam.id, 16),
                          done: 'Photo mode',
                        ),
                ),
                action(
                  Icons.videocam,
                  'Video mode',
                  rigBusy
                      ? null
                      : () => _run(
                          () => goPro.selectMode(cam.id, 12),
                          done: 'Video mode',
                        ),
                ),
                action(
                  cam.isRecording ? Icons.stop : Icons.circle,
                  cam.isRecording ? 'Stop' : 'Test shot',
                  rigBusy
                      ? null
                      : () => _run(
                          () => goPro.toggleRecording(cam.id, !cam.isRecording),
                        ),
                  color: cam.isRecording ? Colors.redAccent : null,
                ),
                action(
                  Icons.bedtime_outlined,
                  'Sleep',
                  rigBusy
                      ? null
                      : () => _run(
                          () => goPro.sleepCamera(cam.id),
                          done: 'Camera sleeps',
                        ),
                ),
                action(
                  Icons.link_off,
                  'Disconnect',
                  rigBusy
                      ? null
                      : () => _run(() => goPro.releaseAndDisconnect(cam.id)),
                  color: Colors.orange,
                ),
                action(Icons.tune, 'All controls', () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => RigControlScreen(only: cam.id),
                    ),
                  );
                }),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-screen live view of one camera, to judge framing and brightness.
class LiveViewScreen extends StatelessWidget {
  const LiveViewScreen({super.key, this.cameraId});
  final String? cameraId;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      title: const AppText('Live view'),
    ),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: CameraLiveMonitor(
          initialId: cameraId,
          onClose: () => Navigator.pop(context),
        ),
      ),
    ),
  );
}

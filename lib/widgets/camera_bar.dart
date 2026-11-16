import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_text.dart';
import '../models/camera_device.dart';
import '../screens/device_manager.dart';
import '../screens/rig_control_screen.dart';
import '../screens/rig_settings_screen.dart';
import '../screens/settings.dart' show HotspotDialog;
import '../services/capture_coordinator.dart';
import '../services/gopro_service.dart';
import 'camera_live_monitor.dart';

/// The rig's cameras in one row: "Connect cameras" on the left, then each
/// connected camera (tap for its panel) or "No camera connected".
class CameraBar extends StatelessWidget {
  const CameraBar({super.key, this.dark = false});

  /// White text for dark backgrounds (capture screen).
  final bool dark;

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
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ActionChip(
              avatar: Icon(Icons.add_link, size: 16, color: ink),
              label: AppText(
                'Connect cameras',
                style: TextStyle(fontSize: 12, color: ink),
              ),
              backgroundColor: ink.withValues(alpha: 0.06),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DeviceManagerScreen()),
              ),
            ),
          ),
          if (cams.isEmpty)
            Center(
              child: AppText(
                'No camera connected',
                style: TextStyle(color: Colors.orange.shade400, fontSize: 13),
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
        ],
      ),
    );
  }
}

/// The full camera panel in a bottom sheet.
Future<void> showCameraSheet(BuildContext context, String id) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: CameraPanel(id: id, showHeader: true),
        ),
      ),
    );

/// Every action for one camera, grouped, with live status. Toggles that are
/// on (Wi-Fi, GPS, locate, recording, current mode) are highlighted.
class CameraPanel extends StatefulWidget {
  const CameraPanel({super.key, required this.id, this.showHeader = false});
  final String id;
  final bool showHeader;

  @override
  State<CameraPanel> createState() => _CameraPanelState();
}

class _CameraPanelState extends State<CameraPanel> {
  bool _busy = false;
  Timer? _poll;
  GoProService? _goPro;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_goPro == null) {
      _goPro = context.read<GoProService>();
      _refresh();
      _poll = Timer.periodic(const Duration(seconds: 6), (_) => _refresh());
    }
  }

  void _refresh() {
    final goPro = _goPro!;
    if (_busy || goPro.capture.busy || goPro.isSyncingMedia) return;
    final cam = goPro.devices.where((d) => d.id == widget.id).firstOrNull;
    if (cam == null || !cam.isConnected) return;
    unawaited(goPro.refreshPanel(widget.id).catchError((_) {}));
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action, {String? done}) async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      if (done != null) {
        messenger.showSnackBar(SnackBar(content: AppText(done)));
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: AppText(describeError(e)),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
      _refresh();
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

  Future<bool> _confirm(String title, String text) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: AppText(title),
          content: AppText(text),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const AppText('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const AppText('OK'),
            ),
          ],
        ),
      ) ==
      true;

  @override
  Widget build(BuildContext context) {
    final goPro = context.watch<GoProService>();
    final cam = goPro.devices.where((d) => d.id == widget.id).firstOrNull;
    if (cam == null) return const SizedBox(height: 80);
    final status = goPro.statusOf(cam.id);
    final settings = goPro.panelSettingsOf(cam.id);
    final wifiOn = status[69] == 1;
    final gpsOn = settings[83] == 1;
    final gpsLock = status[68] == 1;
    final recording = status[10] == 1 || cam.isRecording;
    final locating = goPro.isLocating(cam.id);
    final mode = status[89];
    final rigBusy = goPro.capture.active || goPro.capture.busy;
    final primary = Theme.of(context).primaryColor;

    Widget chip(IconData icon, String text, {bool on = false, Color? color}) {
      final c = color ?? (on ? primary : Theme.of(context).hintColor);
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: c.withValues(alpha: on ? 0.18 : 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: c.withValues(alpha: on ? 0.7 : 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: c),
            const SizedBox(width: 4),
            AppText(text, style: TextStyle(fontSize: 11, color: c)),
          ],
        ),
      );
    }

    Widget button(
      IconData icon,
      String label,
      VoidCallback? onTap, {
      bool on = false,
      Color? color,
    }) {
      final c = on ? primary : color;
      return SizedBox(
        width: 74,
        height: 64,
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
            foregroundColor: c,
            backgroundColor: on ? primary.withValues(alpha: 0.16) : null,
            side: BorderSide(
              color: (c ?? Theme.of(context).dividerColor).withValues(
                alpha: on ? 0.9 : 0.4,
              ),
              width: on ? 1.6 : 1,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onPressed: _busy ? null : onTap,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20),
              const SizedBox(height: 3),
              AppText(
                label,
                style: const TextStyle(fontSize: 10),
                textAlign: TextAlign.center,
                maxLines: 2,
              ),
            ],
          ),
        ),
      );
    }

    Widget group(String title, List<Widget> buttons) => Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppText(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              letterSpacing: 1.1,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).hintColor,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: buttons),
        ],
      ),
    );

    void open(Widget page) =>
        Navigator.push(context, MaterialPageRoute(builder: (_) => page));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.showHeader)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppText(
                cam.displayName,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              AppText(
                '${goPro.modelFor(cam.id)} · ${cam.name}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: LinearProgressIndicator(),
          ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            chip(
              Icons.battery_std,
              '${cam.batteryLevel}%',
              color: cam.batteryLevel <= 20 ? Colors.redAccent : null,
            ),
            if (cam.storageRemaining != 'Unknown')
              chip(Icons.sd_card, '${cam.storageRemaining} free'),
            chip(
              mode == 12
                  ? Icons.videocam
                  : mode == 16
                  ? Icons.photo_camera
                  : Icons.timelapse,
              mode == 12
                  ? 'Video'
                  : mode == 16
                  ? 'Photo'
                  : mode == null
                  ? 'Mode ?'
                  : 'Time-lapse',
              on: mode != null,
            ),
            chip(Icons.wifi, wifiOn ? 'Wi-Fi on' : 'Wi-Fi off', on: wifiOn),
            chip(
              gpsLock ? Icons.gps_fixed : Icons.gps_not_fixed,
              !gpsOn
                  ? 'GPS off'
                  : gpsLock
                  ? 'GPS lock'
                  : 'GPS on',
              on: gpsOn,
            ),
            if (recording)
              chip(
                Icons.fiber_manual_record,
                'Recording',
                on: true,
                color: Colors.redAccent,
              ),
            if (goPro.exposureOf(cam.id).isNotEmpty)
              chip(Icons.exposure, goPro.exposureOf(cam.id), on: true),
            if (status[6] == 1)
              chip(Icons.thermostat, 'Hot', on: true, color: Colors.orange),
          ],
        ),
        group('Capture', [
          button(
            Icons.videocam,
            'Video',
            rigBusy ? null : () => _run(() => goPro.selectMode(cam.id, 12)),
            on: mode == 12,
          ),
          button(
            Icons.photo_camera,
            'Photo',
            rigBusy ? null : () => _run(() => goPro.selectMode(cam.id, 16)),
            on: mode == 16,
          ),
          button(
            Icons.timelapse,
            'Time-lapse',
            rigBusy ? null : () => _run(() => goPro.selectMode(cam.id, 13)),
            on: mode != null && mode != 12 && mode != 16,
          ),
          button(
            recording ? Icons.stop : Icons.fiber_manual_record,
            recording ? 'Stop' : 'Shutter',
            rigBusy
                ? null
                : () => _run(() => goPro.toggleRecording(cam.id, !recording)),
            on: recording,
            color: Colors.redAccent,
          ),
          button(
            Icons.star_outline,
            'HiLight',
            recording ? () => _run(() => goPro.addHiLightTag(cam.id)) : null,
          ),
          button(
            Icons.live_tv,
            'Live view',
            () => open(LiveViewScreen(cameraId: cam.id)),
          ),
        ]),
        group('Camera', [
          button(
            locating ? Icons.notifications_off : Icons.notifications_active,
            locating ? 'Stop locate' : 'Locate',
            () => _run(() => goPro.setLocate(cam.id, !locating)),
            on: locating,
          ),
          button(
            Icons.wifi,
            wifiOn ? 'Wi-Fi on' : 'Wi-Fi off',
            () => _run(() => goPro.toggleWifiAp(cam.id, !wifiOn)),
            on: wifiOn,
          ),
          button(
            Icons.gps_fixed,
            gpsOn ? 'GPS on' : 'GPS off',
            () => _run(() => goPro.setGps(cam.id, !gpsOn)),
            on: gpsOn,
          ),
          button(
            Icons.schedule,
            'Sync clock',
            () => _run(
              () => goPro.syncCameraClock(cam.id),
              done: 'Clock set to phone time',
            ),
          ),
          button(Icons.edit, 'Rename', () => _rename(goPro, cam)),
          button(
            Icons.key,
            'Wi-Fi password',
            () => showDialog(
              context: context,
              builder: (_) => const HotspotDialog(),
            ),
          ),
          button(
            Icons.tune,
            'All settings',
            () => open(const RigSettingsScreen()),
          ),
        ]),
        group('Power & storage', [
          button(
            Icons.bedtime_outlined,
            'Sleep',
            rigBusy
                ? null
                : () => _run(
                    () => goPro.sleepCamera(cam.id),
                    done: 'Camera sleeps. Tap it to wake it.',
                  ),
          ),
          button(
            Icons.power_settings_new,
            'Power off',
            rigBusy
                ? null
                : () async {
                    if (await _confirm(
                      'Power off ${cam.displayName}?',
                      'It must be switched on by hand again.',
                    )) {
                      await _run(() => goPro.powerDown(cam.id));
                    }
                  },
            color: Colors.redAccent,
          ),
          button(
            Icons.link_off,
            'Disconnect',
            rigBusy
                ? null
                : () => _run(() => goPro.releaseAndDisconnect(cam.id)),
            color: Colors.orange,
          ),
          button(
            Icons.sd_card_alert_outlined,
            'Erase SD',
            rigBusy ? null : () => open(RigControlScreen(only: cam.id)),
            color: Colors.redAccent,
          ),
        ]),
      ],
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

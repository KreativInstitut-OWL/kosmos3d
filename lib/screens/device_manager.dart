import '../l10n/app_text.dart';
import 'rig_settings_screen.dart';
import 'rig_control_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/camera_device.dart';
import '../widgets/glass_card.dart';
import '../services/gopro_service.dart';
import '../services/system_settings_service.dart';
import '../providers/settings_provider.dart';
import '../widgets/gopro_media_transfer_dialog.dart';
import '../widgets/camera_live_monitor.dart';
import 'settings.dart';

class DeviceManagerScreen extends StatefulWidget {
  const DeviceManagerScreen({super.key});

  @override
  State<DeviceManagerScreen> createState() => _DeviceManagerScreenState();
}

class _DeviceManagerScreenState extends State<DeviceManagerScreen> {
  bool _connectingAll = false;

  /// Runs a camera action and shows its error (or [done]) instead of failing
  /// silently.
  Future<void> _guard(Future<void> Function() action, {String? done}) async {
    final messenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    try {
      await action();
      if (done != null) {
        messenger.showSnackBar(SnackBar(content: AppText(done)));
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: AppText('$e'), backgroundColor: errorColor),
      );
    }
  }

  Future<void> _connectAll(GoProService goPro) async {
    setState(() => _connectingAll = true);
    try {
      final failures = await goPro.connectAll();
      if (mounted && failures.isNotEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: AppText(failures.join('\n'))));
      }
    } finally {
      if (mounted) setState(() => _connectingAll = false);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final goPro = context.read<GoProService>();
      if (!goPro.isScanning && !goPro.devices.any((d) => d.isConnected)) {
        _checkLocationAndScan(goPro);
      }
    });
  }

  Future<void> _checkLocationAndScan(GoProService goPro) async {
    if (await Permission.location.serviceStatus.isDisabled) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            title: const AppText(
              'Location Services Required',
              style: TextStyle(color: Colors.white),
            ),
            content: const AppText(
              'Android requires Location / GPS to be ON for Bluetooth scanning.\n\nPull down your quick settings and turn on Location.',
              style: TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: AppText(
                  'OK',
                  style: TextStyle(color: Theme.of(context).primaryColor),
                ),
              ),
            ],
          ),
        );
      }
      return;
    }
    goPro.startScan();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final goPro = context.watch<GoProService>();
    final cameras = goPro.devices;

    return Scaffold(
      appBar: AppBar(
        title: const AppText('Cameras'),
        actions: [
          IconButton(
            tooltip: 'Live viewfinder',
            icon: const Icon(Icons.videocam_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => Scaffold(
                  appBar: AppBar(title: const AppText('Viewfinder')),
                  body: const SingleChildScrollView(
                    padding: EdgeInsets.all(20),
                    child: CameraLiveMonitor(),
                  ),
                ),
              ),
            ),
          ),
          if (cameras.any((c) => c.isConnected))
            IconButton(
              icon: const Icon(Icons.settings_remote),
              tooltip: 'Rig control',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const RigControlScreen()),
              ),
            ),
          if (cameras.any((c) => c.isConnected))
            IconButton(
              icon: const Icon(Icons.tune),
              tooltip: 'All camera settings',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const RigSettingsScreen()),
              ),
            ),
          IconButton(
            icon: goPro.isScanning
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Theme.of(context).primaryColor,
                    ),
                  )
                : const Icon(Icons.refresh),
            onPressed: goPro.isScanning
                ? null
                : () => _checkLocationAndScan(goPro),
            tooltip: settings.translate('scanning'),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (!cameras.any((c) => c.isConnected))
              Container(
                margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).primaryColor.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 18,
                      color: Theme.of(context).primaryColor,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: AppText(
                        'No system Bluetooth pairing needed! Just make sure your GoPros have Wireless Connections enabled, then tap Scan → tap a camera to connect.',
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).primaryColor.withValues(alpha: 0.8),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            // ─── Camera List ───
            Expanded(
              child: cameras.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.bluetooth_searching,
                            size: 64,
                            color: Theme.of(context).textTheme.bodyLarge?.color
                                ?.withValues(alpha: 0.2),
                          ),
                          const SizedBox(height: 16),
                          AppText(
                            goPro.isScanning
                                ? settings.translate('scanning')
                                : settings.translate('no_cameras_found'),
                            style: TextStyle(
                              color: Theme.of(context)
                                  .textTheme
                                  .bodyLarge
                                  ?.color
                                  ?.withValues(alpha: 0.5),
                              fontSize: 16,
                            ),
                          ),
                          if (!goPro.isScanning) ...[
                            const SizedBox(height: 12),
                            ElevatedButton.icon(
                              onPressed: () => _checkLocationAndScan(goPro),
                              icon: const Icon(Icons.search),
                              label: const AppText('Scan for Devices'),
                            ),
                            const SizedBox(height: 24),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 32,
                              ),
                              child: AppText(
                                '📋 Before your first scan:\n'
                                '1. Mount your phone on the rig\n'
                                '2. Power on all GoPro cameras\n'
                                '3. Enable Wireless Connections on each GoPro\n'
                                '4. Tap "Scan for Devices" above\n'
                                '5. Tap each camera to connect',
                                style: TextStyle(
                                  color: Theme.of(context)
                                      .textTheme
                                      .bodyLarge
                                      ?.color
                                      ?.withValues(alpha: 0.35),
                                  fontSize: 13,
                                  height: 1.6,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    )
                  : ListView(
                      physics: const BouncingScrollPhysics(
                        parent: AlwaysScrollableScrollPhysics(),
                      ),
                      // Room for the floating navigation bar.
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
                      children: [
                        // ─── Hotspot Tethering & Wi-Fi Sync Banner (When connected cameras exist) ───
                        if (cameras.any((c) => c.isConnected))
                          Container(
                            margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.blue.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                InkWell(
                                  onTap: () => showDialog(
                                    context: context,
                                    builder: (_) => const HotspotDialog(),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.wifi_tethering,
                                        size: 20,
                                        color: Colors.lightBlueAccent,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const AppText(
                                              'Camera networks',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13,
                                              ),
                                            ),
                                            AppText(
                                              'Wi-Fi passwords, one-tap join and import from every camera',
                                              style: TextStyle(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurface
                                                    .withValues(alpha: 0.7),
                                                fontSize: 11,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const Icon(Icons.chevron_right, size: 18),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 4,
                                  children: [
                                    TextButton.icon(
                                      onPressed: () =>
                                          GoProMediaTransferDialog.show(
                                            context,
                                          ),
                                      icon: const Icon(
                                        Icons.download_for_offline,
                                        size: 16,
                                      ),
                                      label: const AppText('Transfer'),
                                      style: TextButton.styleFrom(
                                        foregroundColor: Theme.of(
                                          context,
                                        ).primaryColor,
                                      ),
                                    ),
                                    TextButton.icon(
                                      onPressed: () => showDialog(
                                        context: context,
                                        builder: (_) => const HotspotDialog(),
                                      ),
                                      icon: const Icon(Icons.key, size: 16),
                                      label: const AppText('Wi-Fi passwords'),
                                      style: TextButton.styleFrom(
                                        foregroundColor: Colors.lightBlueAccent,
                                      ),
                                    ),
                                    TextButton.icon(
                                      onPressed: () =>
                                          SystemSettingsService.openHotspotSettings(),
                                      icon: const Icon(
                                        Icons.settings,
                                        size: 16,
                                      ),
                                      label: const AppText('Hotspot settings'),
                                    ),
                                  ],
                                ),
                                if (goPro.isSyncingMedia ||
                                    goPro.syncStatusMessage.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  AppText(
                                    goPro.syncStatusMessage,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.lightBlueAccent,
                                    ),
                                  ),
                                  if (goPro.isSyncingMedia) ...[
                                    const SizedBox(height: 4),
                                    LinearProgressIndicator(
                                      value: goPro.syncProgress > 0
                                          ? goPro.syncProgress
                                          : null,
                                    ),
                                  ],
                                ],
                              ],
                            ),
                          ),

                        if (cameras.where((c) => !c.isConnected).length > 1)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: FilledButton.icon(
                              onPressed: _connectingAll
                                  ? null
                                  : () => _connectAll(goPro),
                              icon: const Icon(Icons.bluetooth_connected),
                              label: AppText(
                                'Connect all ({n})'.replaceAll(
                                  '{n}',
                                  '${cameras.where((c) => !c.isConnected).length}',
                                ),
                              ),
                            ),
                          ),
                        for (final cam in cameras)
                          _buildCameraCard(context, cam, goPro, settings),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraCard(
    BuildContext context,
    CameraDevice cam,
    GoProService goPro,
    SettingsProvider settings,
  ) {
    final isGoPro = cam.name.toLowerCase().contains('gopro');
    final primaryColor = Theme.of(context).primaryColor;

    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── Header: Name + Connection Status ───
            InkWell(
              onTap: cam.isConnected
                  ? null
                  : () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: AppText(
                            '${settings.translate('connecting')} ${cam.name}...',
                          ),
                        ),
                      );
                      _guard(
                        () => goPro.connectToDevice(cam.id),
                        done: '${cam.name} connected',
                      );
                    },
              onLongPress: cam.isConnected
                  ? null
                  : () => _guard(
                      () => goPro.forgetCamera(cam.id),
                      done: '${cam.name} removed from this phone',
                    ),
              borderRadius: BorderRadius.circular(8),
              child: Row(
                children: [
                  // Camera icon with connection indicator
                  Stack(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: cam.isConnected
                              ? primaryColor.withValues(alpha: 0.15)
                              : Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          isGoPro ? Icons.camera_alt : Icons.bluetooth,
                          color: cam.isConnected
                              ? primaryColor
                              : Theme.of(context).textTheme.bodyMedium?.color
                                    ?.withValues(alpha: 0.38),
                          size: 24,
                        ),
                      ),
                      if (cam.isConnected)
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: primaryColor,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFF1A1A1A),
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  // Name & status
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AppText(
                          cam.name,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: Theme.of(context).textTheme.bodyLarge?.color,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (cam.isConnected)
                          AppText(
                            goPro.modelFor(cam.id),
                            style: const TextStyle(fontSize: 11),
                          ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            AppText(
                              cam.isConnected
                                  ? 'Connected (BLE)'
                                  : 'Tap to connect or wake · hold to forget',
                              style: TextStyle(
                                color: cam.isConnected
                                    ? primaryColor
                                    : Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.color
                                          ?.withValues(alpha: 0.38),
                                fontSize: 12,
                                fontWeight: cam.isConnected
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                            if (cam.isConnected &&
                                cam.wifiIpAddress != null) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.green.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: Colors.green.withValues(alpha: 0.4),
                                  ),
                                ),
                                child: AppText(
                                  'Wi-Fi: ${cam.wifiIpAddress}',
                                  style: const TextStyle(
                                    color: Colors.greenAccent,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Battery indicator (only when connected)
                  if (cam.isConnected) _buildBatteryWidget(cam, primaryColor),
                ],
              ),
            ),

            // ─── Connected Camera Details ───
            if (cam.isConnected) ...[
              const SizedBox(height: 12),
              // Current settings chips
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: cam.currentSettings.entries.map((e) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                    child: AppText(
                      '${e.key}: ${e.value}',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              // Action buttons
              Row(
                children: [
                  _buildActionButton(
                    icon: Icons.photo_camera,
                    label: 'Photo',
                    onTap: () => _guard(
                      () => goPro.selectMode(cam.id, 16),
                      done: 'Switched to Photo mode',
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildActionButton(
                    icon: Icons.videocam,
                    label: 'Video',
                    onTap: () => _guard(
                      () => goPro.selectMode(cam.id, 12),
                      done: 'Switched to Video mode',
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildActionButton(
                    icon: cam.isRecording ? Icons.stop : Icons.circle,
                    label: cam.isRecording ? 'Stop' : 'Shutter',
                    color: cam.isRecording ? Colors.redAccent : null,
                    onTap: () => _guard(
                      () => goPro.toggleRecording(cam.id, !cam.isRecording),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildActionButton(
                    icon: Icons.settings_remote,
                    label: 'Controls',
                    color: primaryColor,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => RigControlScreen(only: cam.id),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _buildActionButton(
                    icon: Icons.link_off,
                    label: settings.translate('disconnect'),
                    color: Colors.orange,
                    onTap: () =>
                        _guard(() => goPro.releaseAndDisconnect(cam.id)),
                  ),
                  const SizedBox(width: 8),
                  _buildActionButton(
                    icon: Icons.key,
                    label: 'Wi-Fi password',
                    color: Colors.lightBlueAccent,
                    onTap: () => showDialog(
                      context: context,
                      builder: (_) => const HotspotDialog(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildActionButton(
                    icon: Icons.bedtime_outlined,
                    label: 'Sleep',
                    onTap: () => _guard(
                      () => goPro.sleepCamera(cam.id),
                      done: 'Camera sleeps. Tap it to wake it.',
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBatteryWidget(CameraDevice cam, Color primaryColor) {
    final batteryColor = cam.batteryLevel > 50
        ? primaryColor
        : cam.batteryLevel > 20
        ? Colors.orange
        : Colors.redAccent;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: batteryColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            cam.batteryLevel > 80
                ? Icons.battery_full
                : cam.batteryLevel > 50
                ? Icons.battery_5_bar
                : cam.batteryLevel > 20
                ? Icons.battery_3_bar
                : Icons.battery_alert,
            size: 16,
            color: batteryColor,
          ),
          const SizedBox(width: 4),
          AppText(
            '${cam.batteryLevel}%',
            style: TextStyle(
              color: batteryColor,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
    Color? color,
  }) {
    final base = Theme.of(context).colorScheme.onSurface;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: (color ?? base).withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: (color ?? base).withValues(alpha: 0.15)),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 18,
                color: color ?? base.withValues(alpha: 0.75),
              ),
              const SizedBox(height: 2),
              AppText(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: color ?? base.withValues(alpha: 0.65),
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

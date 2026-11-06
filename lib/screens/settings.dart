import '../l10n/app_text.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'package:provider/provider.dart';
import '../widgets/glass_card.dart';
import 'device_manager.dart';
import 'camera_networks_screen.dart';
import 'rig_settings_screen.dart';
import '../providers/settings_provider.dart';
import '../services/cloud_storage_service.dart';
import '../services/rig_geometry_service.dart';
import '../services/lidar_service.dart';
import '../services/gopro_service.dart';
import '../services/upload_service.dart';
import '../l10n/ui_dictionary.dart';
import '../services/system_settings_service.dart';
import '../widgets/gopro_media_transfer_dialog.dart';
import '../widgets/camera_live_monitor.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final cloud = context.watch<CloudStorageService>();
    final rig = context.watch<RigGeometryService>();
    final lidar = context.watch<LidarService>();

    return Scaffold(
      appBar: AppBar(title: AppText(settings.translate('settings'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            SwitchListTile(
              title: AppText(settings.translate('coverage_viewer')),
              subtitle: AppText(settings.translate('coverage_viewer_desc')),
              value: settings.coverageVisualizer,
              onChanged: settings.setCoverageVisualizer,
            ),
            // ─── APPEARANCE ─────────────────────────────
            _buildSectionHeader(context, 'Appearance'),
            GlassCard(
              margin: const EdgeInsets.only(bottom: 12),
              child: Column(
                children: [
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    leading: const Icon(Icons.brightness_6, size: 24),
                    title: const AppText(
                      'Theme',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: SegmentedButton<ThemeMode>(
                        segments: const [
                          ButtonSegment(
                            value: ThemeMode.system,
                            icon: Icon(Icons.phone_android, size: 16),
                          ),
                          ButtonSegment(
                            value: ThemeMode.dark,
                            icon: Icon(Icons.dark_mode, size: 16),
                          ),
                          ButtonSegment(
                            value: ThemeMode.light,
                            icon: Icon(Icons.light_mode, size: 16),
                          ),
                        ],
                        selected: {settings.themeMode},
                        onSelectionChanged: (v) =>
                            settings.setThemeMode(v.first),
                        style: ButtonStyle(
                          visualDensity: VisualDensity.compact,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ),
                  ),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    leading: AppText(
                      settings.currentLanguage == 'en' ? '🇬🇧' : '🇩🇪',
                      style: const TextStyle(fontSize: 24),
                    ),
                    title: AppText(
                      settings.translate('language'),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: AppText(
                      settings.currentLanguage == 'en' ? 'English' : 'Deutsch',
                    ),
                    trailing: Switch(
                      value: settings.currentLanguage == 'de',
                      activeThumbColor: Theme.of(context).primaryColor,
                      onChanged: (_) => settings.toggleLanguage(),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ─── DEVICE MANAGER ─────────────────────────
            _buildSectionHeader(context, settings.translate('device_manager')),
            _buildSettingCard(
              context,
              title: settings.translate('device_manager'),
              subtitle: settings.translate('manage_gopros'),
              icon: Icons.camera_alt,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DeviceManagerScreen()),
              ),
            ),
            const SizedBox(height: 8),
            _buildSettingCard(
              context,
              title: 'All camera settings',
              subtitle:
                  'Every GoPro setting the connected cameras share, applied to all',
              icon: Icons.tune,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const RigSettingsScreen()),
              ),
            ),
            const SizedBox(height: 8),
            _buildSettingCard(
              context,
              title: 'Live Camera Monitor',
              subtitle: 'Live preview, one camera at a time over its Wi-Fi',
              icon: Icons.videocam,
              onTap: () {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => Padding(
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.of(context).viewInsets.bottom,
                      top: 40, // padding for safe area
                    ),
                    child: CameraLiveMonitor(
                      onClose: () => Navigator.pop(context),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),

            // ─── SCANNING PRESETS ───────────────────────
            _buildSectionHeader(
              context,
              settings.translate('scanning_presets'),
            ),
            ...settings.allPresets.map(
              (preset) => GlassCard(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  leading: AppText(
                    preset.icon,
                    style: const TextStyle(fontSize: 24),
                  ),
                  title: AppText(
                    preset.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  subtitle: AppText(
                    '${preset.settings['Mode'] == 'photo' ? preset.settings['Photo Format'] : '${preset.settings['Resolution']} · ${preset.settings['FPS']}fps'} · ${preset.settings['Lens']}',
                    style: TextStyle(
                      color: Theme.of(
                        context,
                      ).textTheme.bodySmall?.color?.withValues(alpha: 0.5),
                      fontSize: 12,
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () => _showPresetDetail(context, preset, settings),
                ),
              ),
            ),
            _buildSettingCard(
              context,
              title: settings.translate('create_preset'),
              subtitle: settings.translate('create_preset_desc'),
              icon: Icons.add_circle_outline,
              onTap: () => _showCreatePresetDialog(context, settings),
            ),
            const SizedBox(height: 16),

            // ─── SENSOR SETTINGS ────────────────────────
            _buildSectionHeader(context, 'Sensor & Capture'),
            GlassCard(
              margin: const EdgeInsets.only(bottom: 12),
              child: Column(
                children: [
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    leading: const Icon(Icons.timer_outlined, size: 22),
                    title: const AppText(
                      'Capture Interval',
                      style: TextStyle(fontSize: 14),
                    ),
                    subtitle: AppText(
                      settings.captureInterval == 'Off'
                          ? 'Manual trigger only'
                          : 'Continuous timelapse',
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: DropdownButton<String>(
                      value: settings.captureInterval,
                      underline: const SizedBox(),
                      items: const [
                        DropdownMenuItem(value: 'Off', child: AppText('Off')),
                        DropdownMenuItem(value: '0.5s', child: AppText('0.5s')),
                        DropdownMenuItem(value: '1s', child: AppText('1s')),
                        DropdownMenuItem(value: '2s', child: AppText('2s')),
                        DropdownMenuItem(value: '5s', child: AppText('5s')),
                      ],
                      onChanged: (v) {
                        if (v != null) settings.setCaptureInterval(v);
                      },
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    secondary: const Icon(Icons.vibration, size: 22),
                    title: const AppText(
                      'Haptic Feedback',
                      style: TextStyle(fontSize: 14),
                    ),
                    subtitle: const AppText(
                      'Vibrate on capture events',
                      style: TextStyle(fontSize: 12),
                    ),
                    value: settings.hapticFeedback,
                    activeThumbColor: Theme.of(context).primaryColor,
                    onChanged: (v) => settings.setHapticFeedback(v),
                  ),
                  SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    secondary: const Icon(Icons.light_mode_outlined, size: 22),
                    title: const AppText(
                      'Keep screen on',
                      style: TextStyle(fontSize: 14),
                    ),
                    subtitle: const AppText(
                      'During capture the screen never locks. Capture keeps running with the screen locked either way, until you tap Stop.',
                      style: TextStyle(fontSize: 12),
                    ),
                    value: settings.keepScreenOn,
                    activeThumbColor: Theme.of(context).primaryColor,
                    onChanged: (v) => settings.setKeepScreenOn(v),
                  ),
                  SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    secondary: const Icon(Icons.speed, size: 22),
                    title: const AppText(
                      'Barometer (Altitude)',
                      style: TextStyle(fontSize: 14),
                    ),
                    subtitle: const AppText(
                      'Record pressure sensor for elevation',
                      style: TextStyle(fontSize: 12),
                    ),
                    value: settings.recordBarometer,
                    activeThumbColor: Theme.of(context).primaryColor,
                    onChanged: (v) => settings.setRecordBarometer(v),
                  ),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    leading: const Icon(Icons.sensors, size: 22),
                    title: const AppText(
                      'IMU Sample Rate',
                      style: TextStyle(fontSize: 14),
                    ),
                    subtitle: AppText(
                      '${settings.sensorRate}ms (${(1000 / settings.sensorRate).round()} Hz)',
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: DropdownButton<int>(
                      value: settings.sensorRate,
                      underline: const SizedBox(),
                      items: const [
                        DropdownMenuItem(
                          value: 20,
                          child: AppText('20ms (50Hz)'),
                        ),
                        DropdownMenuItem(
                          value: 50,
                          child: AppText('50ms (20Hz)'),
                        ),
                        DropdownMenuItem(
                          value: 100,
                          child: AppText('100ms (10Hz)'),
                        ),
                      ],
                      onChanged: (v) {
                        if (v != null) settings.setSensorRate(v);
                      },
                    ),
                  ),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    leading: const Icon(Icons.gps_fixed, size: 22),
                    title: const AppText(
                      'GPS Poll Rate',
                      style: TextStyle(fontSize: 14),
                    ),
                    subtitle: AppText(
                      'Every ${settings.gpsRate}s',
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: DropdownButton<int>(
                      value: settings.gpsRate,
                      underline: const SizedBox(),
                      items: const [
                        DropdownMenuItem(value: 1, child: AppText('1s (fast)')),
                        DropdownMenuItem(
                          value: 2,
                          child: AppText('2s (normal)'),
                        ),
                        DropdownMenuItem(
                          value: 5,
                          child: AppText('5s (battery)'),
                        ),
                      ],
                      onChanged: (v) {
                        if (v != null) settings.setGpsRate(v);
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ─── RIG GEOMETRY & NAMING ──────────────────
            _buildSectionHeader(context, 'Rig Layout & File Naming'),
            GlassCard(
              margin: const EdgeInsets.only(bottom: 12),
              child: Column(
                children: [
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    leading: const Icon(Icons.text_fields, size: 22),
                    title: const AppText(
                      'Naming Template',
                      style: TextStyle(fontSize: 14),
                    ),
                    subtitle: AppText(
                      rig.namingTemplate,
                      style: const TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                    trailing: const Icon(Icons.edit, size: 18),
                    onTap: () => _showNamingDialog(context, rig),
                  ),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    leading: const Icon(Icons.view_in_ar, size: 22),
                    title: AppText(
                      'Camera Positions (${rig.cameras.length})',
                      style: const TextStyle(fontSize: 14),
                    ),
                    subtitle: const AppText(
                      'Define rig offsets for each camera',
                      style: TextStyle(fontSize: 12),
                    ),
                    trailing: const Icon(Icons.chevron_right, size: 20),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const RigLayoutScreen(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (lidar.isAvailable) ...[
              GlassCard(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  leading: Icon(
                    Icons.radar,
                    size: 28,
                    color: Theme.of(context).primaryColor,
                  ),
                  title: const AppText(
                    'LiDAR Scanner',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  subtitle: AppText(
                    lidar.isCapturing
                        ? 'Capturing (${lidar.depthFrameCount} frames)'
                        : 'Available — auto-captures with photos',
                  ),
                  trailing: Icon(
                    Icons.check_circle,
                    color: Theme.of(context).primaryColor,
                    size: 20,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),

            // ─── NETWORK & HOTSPOT ──────────────────────
            _buildSectionHeader(context, 'Network & Tethering'),
            GlassCard(
              margin: const EdgeInsets.only(bottom: 12),
              child: Column(
                children: [
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    leading: Icon(
                      Icons.wifi_tethering,
                      size: 28,
                      color: Theme.of(context).primaryColor,
                    ),
                    title: const AppText(
                      'Camera networks',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: AppText(
                      'Direct Wi-Fi, passwords and hotspot compatibility',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.settings, size: 20),
                          tooltip: 'Open Device Hotspot Settings',
                          onPressed: () =>
                              SystemSettingsService.openHotspotSettings(),
                        ),
                        const Icon(Icons.chevron_right, size: 20),
                      ],
                    ),
                    onTap: () => showDialog(
                      context: context,
                      builder: (_) => const HotspotDialog(),
                    ),
                  ),
                  Divider(height: 1, color: context.ink(0.1)),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    leading: Icon(
                      Icons.download_for_offline,
                      size: 26,
                      color: Theme.of(context).primaryColor,
                    ),
                    title: const AppText(
                      'Import all camera originals',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: const AppText(
                      'Join cameras one at a time; optionally export to Photos / Gallery',
                      style: TextStyle(fontSize: 12),
                    ),
                    trailing: const Icon(Icons.chevron_right, size: 20),
                    onTap: () => GoProMediaTransferDialog.show(context),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            _buildSectionHeader(context, settings.translate('cloud_storage')),
            _buildSettingCard(
              context,
              title: 'Storage server',
              subtitle: cloud.isConfigured
                  ? settings.translate('cloud_configured')
                  : settings.translate('cloud_not_configured'),
              icon: Icons.cloud,
              onTap: () => showDialog(
                context: context,
                builder: (_) => const CloudStorageDialog(),
              ),
            ),
            GlassCard(
              margin: const EdgeInsets.only(bottom: 12),
              child: SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                secondary: const Icon(Icons.cloud_upload, size: 22),
                title: const AppText(
                  'Auto-upload to storage server',
                  style: TextStyle(fontSize: 14),
                ),
                subtitle: const AppText(
                  'Upload the project after each session',
                  style: TextStyle(fontSize: 12),
                ),
                value: settings.cloudAutoUpload,
                activeThumbColor: Theme.of(context).primaryColor,
                onChanged: cloud.isConfigured
                    ? (v) => settings.setCloudAutoUpload(v)
                    : null,
              ),
            ),
            const SizedBox(height: 16),

            // ─── GAUSSIAN SPLAT PROCESSING SERVER ──────────
            _buildSectionHeader(context, 'KOSMOS receiver (your computer)'),
            GlassCard(
              margin: const EdgeInsets.only(bottom: 12),
              child: Column(
                children: [
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    leading: const Icon(Icons.cloud_sync, size: 28),
                    title: const AppText(
                      'Processing Server',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: AppText(
                      settings.serverUrl.isNotEmpty
                          ? settings.serverUrl
                          : 'Configure remote COLMAP / 3DGS server',
                      style: TextStyle(
                        color: Theme.of(context).primaryColor,
                        fontSize: 12,
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.settings, size: 20),
                          tooltip: 'Configure Server',
                          onPressed: () => showDialog(
                            context: context,
                            builder: (_) => const _ServerConfigDialog(),
                          ),
                        ),
                      ],
                    ),
                    onTap: () => showDialog(
                      context: context,
                      builder: (_) => const _ServerConfigDialog(),
                    ),
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 2,
                    ),
                    secondary: const Icon(
                      Icons.cloud_upload_outlined,
                      size: 22,
                    ),
                    title: const AppText(
                      'Auto-Upload Captures',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: const AppText(
                      'Automatically upload session photos to server for 3D reconstruction',
                      style: TextStyle(fontSize: 12),
                    ),
                    value: settings.serverAutoUpload,
                    onChanged: (val) => settings.setServerAutoUpload(val),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ─── ABOUT ─────────────────────────────────
            _buildSectionHeader(context, 'About'),
            GlassCard(
              margin: const EdgeInsets.only(bottom: 12),
              child: Column(
                children: [
                  const ListTile(
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    leading: Icon(Icons.info_outline, size: 22),
                    title: AppText(
                      'KOSMOS 3D',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: AppText(
                      'Version 2.0.0 · Sam Wiemann · kreativ.institute',
                    ),
                  ),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    leading: const Icon(Icons.school, size: 22),
                    title: const AppText(
                      'KIO Kreativ Institut',
                      style: TextStyle(fontSize: 14),
                    ),
                    subtitle: const AppText(
                      'Gaussian Splatting Rig Controller',
                      style: TextStyle(fontSize: 12),
                    ),
                    trailing: const Icon(Icons.open_in_new, size: 16),
                    onTap: () {},
                  ),
                  const ListTile(
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    leading: Icon(Icons.phone_iphone, size: 22),
                    title: AppText(
                      'Supported Sensors',
                      style: TextStyle(fontSize: 14),
                    ),
                    subtitle: AppText(
                      'Accelerometer • Gyroscope • Magnetometer\nBarometer • GPS • Compass',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPresetDetail(
    BuildContext context,
    CameraPreset preset,
    SettingsProvider settings,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            AppText(preset.icon, style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 8),
            AppText(
              preset.name,
              style: TextStyle(color: context.ink(), fontSize: 16),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: preset.settings.entries
              .map(
                (e) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      AppText(
                        e.key,
                        style: TextStyle(
                          color: context.ink(0.54),
                          fontSize: 13,
                        ),
                      ),
                      AppText(
                        e.value,
                        style: TextStyle(
                          color: context.ink(),
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const AppText('Close'),
          ),
          ElevatedButton(
            onPressed: () {
              settings.setDefaultSettings(preset.settings);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: AppText('${preset.name} set as default'),
                  backgroundColor: Theme.of(context).primaryColor,
                ),
              );
            },
            child: const AppText('Set as Default'),
          ),
        ],
      ),
    );
  }

  void _showCreatePresetDialog(
    BuildContext context,
    SettingsProvider settings,
  ) {
    final nameCtrl = TextEditingController();
    String resolution = '4K', fps = '30', lens = 'Linear';
    String isoMax = '400', shutter = 'Auto', wb = '5500K', bitrate = 'High';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: AppText(
            'Create Preset',
            style: TextStyle(color: context.ink()),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  style: TextStyle(color: context.ink()),
                  decoration: InputDecoration(
                    labelText: 'Preset Name',
                    labelStyle: TextStyle(color: context.ink(0.54)),
                  ),
                ),
                const SizedBox(height: 12),
                _dropdownRow(ctx, 'Resolution', resolution, [
                  '1080p',
                  '2.7K',
                  '4K',
                  '5.3K',
                ], (v) => setState(() => resolution = v)),
                _dropdownRow(ctx, 'FPS', fps, [
                  '24',
                  '30',
                  '60',
                  '120',
                ], (v) => setState(() => fps = v)),
                _dropdownRow(ctx, 'Lens', lens, [
                  'Linear',
                  'Wide',
                  'SuperView',
                ], (v) => setState(() => lens = v)),
                _dropdownRow(ctx, 'Target ISO (manual)', isoMax, [
                  '100',
                  '200',
                  '400',
                  '800',
                  '1600',
                ], (v) => setState(() => isoMax = v)),
                _dropdownRow(ctx, 'Target shutter (manual)', shutter, [
                  'Auto',
                  '1/60',
                  '1/120',
                  '1/240',
                  '1/480',
                ], (v) => setState(() => shutter = v)),
                _dropdownRow(ctx, 'Target white balance (manual)', wb, [
                  'Auto',
                  '3200K',
                  '4000K',
                  '5500K',
                  '6500K',
                ], (v) => setState(() => wb = v)),
                _dropdownRow(ctx, 'Bitrate', bitrate, [
                  'Standard',
                  'High',
                ], (v) => setState(() => bitrate = v)),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const AppText('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (nameCtrl.text.trim().isEmpty) return;
                settings.addCustomPreset(
                  CameraPreset(
                    name: nameCtrl.text.trim(),
                    icon: '⭐',
                    settings: {
                      'Resolution': resolution,
                      'FPS': fps,
                      'Lens': lens,
                      'Mode': 'video',
                      'ISO Max': 'Camera preset',
                      'Target ISO': isoMax,
                      'Shutter': 'Camera preset',
                      'Target Shutter': shutter,
                      'White Balance': 'Camera preset',
                      'Target White Balance': wb,
                      'Bitrate': bitrate,
                    },
                  ),
                );
                Navigator.pop(ctx);
              },
              child: const AppText('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dropdownRow(
    BuildContext context,
    String label,
    String value,
    List<String> options,
    ValueChanged<String> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: AppText(
              label,
              style: TextStyle(color: context.ink(0.54), fontSize: 12),
            ),
          ),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: value,
                isExpanded: true,
                style: TextStyle(color: context.ink(), fontSize: 13),
                items: options
                    .map((o) => DropdownMenuItem(value: o, child: AppText(o)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) onChanged(v);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0, left: 4.0),
      child: AppText(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: Theme.of(context).primaryColor,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildSettingCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Icon(icon, size: 28),
        title: AppText(
          title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: AppText(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }

  void _showNamingDialog(BuildContext context, RigGeometryService rig) {
    final ctrl = TextEditingController(text: rig.namingTemplate);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const AppText('File Naming Template'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(labelText: 'Template'),
            ),
            const SizedBox(height: 12),
            AppText(
              'Available variables:',
              style: TextStyle(
                color: Theme.of(ctx).primaryColor,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            const AppText(
              '{project} — Project name\n{camera} — Camera label\n{index} — Capture number (0001)\n{date} — Date (2026-04-30)\n{time} — Time (143025)',
              style: TextStyle(fontSize: 11, height: 1.6),
            ),
            const SizedBox(height: 8),
            AppText(
              'Preview: ${rig.generateFileName(projectName: "MyScan", cameraLabel: "CAM1", index: 1)}',
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const AppText('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              rig.setNamingTemplate(ctrl.text.trim());
              Navigator.pop(ctx);
            },
            child: const AppText('Save'),
          ),
        ],
      ),
    );
  }
}

/// Screen for configuring camera rig positions
class RigLayoutScreen extends StatelessWidget {
  const RigLayoutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final rig = context.watch<RigGeometryService>();
    final goPro = context.watch<GoProService>();

    return Scaffold(
      appBar: AppBar(title: const AppText('Rig Camera Layout')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Theme.of(context).primaryColor.withValues(alpha: 0.2),
              ),
            ),
            child: const AppText(
              'Define each camera\'s position relative to the phone mount (center of rig).\n'
              'X = left/right, Y = up/down, Z = forward/back (meters).\n'
              'Rotation: yaw, pitch, roll (degrees).',
              style: TextStyle(fontSize: 12),
            ),
          ),
          // Auto-add connected cameras that aren't in rig yet
          if (goPro.devices
              .where((d) => d.isConnected)
              .any((d) => !rig.cameras.any((c) => c.cameraId == d.id)))
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ElevatedButton.icon(
                icon: const Icon(Icons.add),
                label: const AppText('Add Connected Cameras'),
                onPressed: () {
                  for (final cam in goPro.devices.where((d) => d.isConnected)) {
                    rig.addCamera(cam.id, cam.name);
                  }
                },
              ),
            ),
          ...rig.cameras.map(
            (cam) => GlassCard(
              margin: const EdgeInsets.only(bottom: 12),
              child: ExpansionTile(
                leading: const Icon(Icons.videocam),
                title: AppText(
                  cam.label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                subtitle: AppText(
                  'Offset: (${cam.offsetX}, ${cam.offsetY}, ${cam.offsetZ})m',
                  style: const TextStyle(fontSize: 11),
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Column(
                      children: [
                        _offsetRow(
                          context,
                          'Label',
                          cam.label,
                          (v) => rig.updateCamera(cam.cameraId, label: v),
                        ),
                        _numRow(
                          context,
                          'X (left/right)',
                          cam.offsetX,
                          (v) => rig.updateCamera(cam.cameraId, x: v),
                        ),
                        _numRow(
                          context,
                          'Y (up/down)',
                          cam.offsetY,
                          (v) => rig.updateCamera(cam.cameraId, y: v),
                        ),
                        _numRow(
                          context,
                          'Z (fwd/back)',
                          cam.offsetZ,
                          (v) => rig.updateCamera(cam.cameraId, z: v),
                        ),
                        _numRow(
                          context,
                          'Yaw°',
                          cam.rotYaw,
                          (v) => rig.updateCamera(cam.cameraId, yaw: v),
                        ),
                        _numRow(
                          context,
                          'Pitch°',
                          cam.rotPitch,
                          (v) => rig.updateCamera(cam.cameraId, pitch: v),
                        ),
                        _numRow(
                          context,
                          'Roll°',
                          cam.rotRoll,
                          (v) => rig.updateCamera(cam.cameraId, roll: v),
                        ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          icon: const Icon(
                            Icons.delete,
                            color: Colors.redAccent,
                            size: 16,
                          ),
                          label: const AppText(
                            'Remove',
                            style: TextStyle(
                              color: Colors.redAccent,
                              fontSize: 12,
                            ),
                          ),
                          onPressed: () => rig.removeCamera(cam.cameraId),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _offsetRow(
    BuildContext context,
    String label,
    String value,
    ValueChanged<String> onChanged,
  ) {
    final ctrl = TextEditingController(text: value);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: AppText(label, style: const TextStyle(fontSize: 12)),
          ),
          Expanded(
            child: TextField(
              controller: ctrl,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 6,
                ),
              ),
              onSubmitted: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _numRow(
    BuildContext context,
    String label,
    double value,
    ValueChanged<double> onChanged,
  ) {
    final ctrl = TextEditingController(text: value.toStringAsFixed(3));
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: AppText(label, style: const TextStyle(fontSize: 12)),
          ),
          Expanded(
            child: TextField(
              controller: ctrl,
              style: const TextStyle(fontSize: 13),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 6,
                ),
              ),
              onSubmitted: (v) {
                final d = double.tryParse(v);
                if (d != null) onChanged(d);
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─── CLOUD STORAGE DIALOG ───────────────────────────────────

class CloudStorageDialog extends StatefulWidget {
  const CloudStorageDialog({super.key});

  @override
  State<CloudStorageDialog> createState() => _CloudStorageDialogState();
}

/// Common S3-compatible providers; the endpoint is only a starting point.
const _storageProviders = <String, ({String endpoint, String region})>{
  'Backblaze B2 (EU Central)': (
    endpoint: 'https://s3.eu-central-003.backblazeb2.com',
    region: 'eu-central-003',
  ),
  'Amazon S3 (Frankfurt)': (
    endpoint: 'https://s3.eu-central-1.amazonaws.com',
    region: 'eu-central-1',
  ),
  'Wasabi (Amsterdam)': (
    endpoint: 'https://s3.eu-central-1.wasabisys.com',
    region: 'eu-central-1',
  ),
  'Cloudflare R2': (
    endpoint: 'https://ACCOUNT-ID.r2.cloudflarestorage.com',
    region: 'auto',
  ),
  'MinIO / own server': (endpoint: 'https://minio.example.org', region: ''),
};

class _CloudStorageDialogState extends State<CloudStorageDialog> {
  final _keyIdCtrl = TextEditingController();
  final _appKeyCtrl = TextEditingController();
  final _bucketCtrl = TextEditingController();
  final _endpointCtrl = TextEditingController();
  final _regionCtrl = TextEditingController();
  final _prefixCtrl = TextEditingController(text: 'kosmos3d');
  bool _obscureKey = true;
  bool _hasSecret = false;
  bool _isTesting = false;
  bool _isSaving = false;
  String? _testResult;
  bool _testOk = false;

  @override
  void initState() {
    super.initState();
    _loadCreds();
  }

  Future<void> _loadCreds() async {
    final cloud = context.read<CloudStorageService>();
    await cloud.ready;
    final creds = await cloud.getDisplayCredentials();
    if (!mounted) return;
    setState(() {
      _keyIdCtrl.text = creds['keyId'] ?? '';
      _bucketCtrl.text = creds['bucketName'] ?? '';
      _endpointCtrl.text = creds['endpoint'] ?? '';
      _regionCtrl.text = creds['region'] ?? '';
      _prefixCtrl.text = creds['prefix'] ?? 'kosmos3d';
      _hasSecret = creds['hasSecret'] == 'true';
    });
  }

  Future<void> _store() => context.read<CloudStorageService>().saveCredentials(
    keyId: _keyIdCtrl.text,
    applicationKey: _appKeyCtrl.text,
    bucketName: _bucketCtrl.text,
    endpoint: _endpointCtrl.text,
    region: _regionCtrl.text,
    prefix: _prefixCtrl.text,
  );

  Future<void> _testConnection() async {
    setState(() {
      _isTesting = true;
      _testResult = null;
    });
    final cloud = context.read<CloudStorageService>();
    await _store();
    final ok = await cloud.testConnection();
    if (!mounted) return;
    setState(() {
      _isTesting = false;
      _testOk = ok;
      _hasSecret = _hasSecret || _appKeyCtrl.text.isNotEmpty;
      _testResult = ok
          ? 'Connected. Bucket is reachable and the key is valid.'
          : cloud.lastError ?? 'Connection failed';
    });
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    await _store();
    if (!mounted) return;
    setState(() => _isSaving = false);
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const AppText('Storage server saved'),
        backgroundColor: Theme.of(context).primaryColor,
      ),
    );
  }

  @override
  void dispose() {
    _keyIdCtrl.dispose();
    _appKeyCtrl.dispose();
    _bucketCtrl.dispose();
    _endpointCtrl.dispose();
    _regionCtrl.dispose();
    _prefixCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(
      context,
    ).textTheme.bodyMedium?.color?.withValues(alpha: 0.6);
    return AlertDialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      title: AppText(
        'Storage server (S3-compatible)',
        style: TextStyle(
          color: Theme.of(context).textTheme.bodyLarge?.color,
          fontSize: 16,
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppText(
              'Works with any S3-compatible storage. Use a key limited to one bucket with read, list and write access.',
              style: TextStyle(color: muted, fontSize: 12),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              isExpanded: true,
              decoration: InputDecoration(
                labelText: _tr('Quick fill'),
                isDense: true,
              ),
              items: [
                for (final name in _storageProviders.keys)
                  DropdownMenuItem(value: name, child: Text(_tr(name))),
              ],
              onChanged: (name) {
                final p = _storageProviders[name];
                if (p == null) return;
                setState(() {
                  _endpointCtrl.text = p.endpoint;
                  _regionCtrl.text = p.region;
                });
              },
            ),
            const SizedBox(height: 10),
            _field('Endpoint URL', _endpointCtrl, Icons.language),
            const SizedBox(height: 10),
            _field('Region (optional)', _regionCtrl, Icons.map),
            const SizedBox(height: 10),
            _field('Bucket', _bucketCtrl, Icons.folder),
            const SizedBox(height: 10),
            _field('Access key ID', _keyIdCtrl, Icons.key),
            const SizedBox(height: 10),
            _field(
              _hasSecret
                  ? 'Secret key (saved, leave empty to keep)'
                  : 'Secret key',
              _appKeyCtrl,
              Icons.lock,
              obscure: _obscureKey,
              suffix: IconButton(
                icon: Icon(
                  _obscureKey ? Icons.visibility_off : Icons.visibility,
                  size: 18,
                ),
                onPressed: () => setState(() => _obscureKey = !_obscureKey),
              ),
            ),
            const SizedBox(height: 10),
            _field('Folder in bucket', _prefixCtrl, Icons.create_new_folder),
            const SizedBox(height: 8),
            AppText(
              'Projects upload to bucket/folder/<project>_<id>/ with the same structure as on the phone. Files already on the server are skipped.',
              style: TextStyle(color: muted, fontSize: 11),
            ),
            if (_testResult != null) ...[
              const SizedBox(height: 12),
              AppText(
                _testResult!,
                style: TextStyle(
                  color: _testOk ? Colors.greenAccent : Colors.redAccent,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const AppText('Cancel'),
        ),
        TextButton(
          onPressed: _isTesting ? null : _testConnection,
          child: _isTesting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const AppText('Test'),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const AppText('Save'),
        ),
      ],
    );
  }

  String _tr(String text) => UiDictionary.translate(
    context.read<SettingsProvider>().currentLanguage,
    text,
  );

  Widget _field(
    String label,
    TextEditingController ctrl,
    IconData icon, {
    bool obscure = false,
    Widget? suffix,
  }) {
    return TextField(
      controller: ctrl,
      obscureText: obscure,
      autocorrect: false,
      enableSuggestions: false,
      style: TextStyle(
        color: Theme.of(context).textTheme.bodyLarge?.color,
        fontSize: 13,
      ),
      decoration: InputDecoration(
        labelText: _tr(label),
        labelStyle: TextStyle(
          color: Theme.of(
            context,
          ).textTheme.bodyMedium?.color?.withValues(alpha: 0.5),
          fontSize: 12,
        ),
        prefixIcon: Icon(
          icon,
          color: Theme.of(
            context,
          ).textTheme.bodyMedium?.color?.withValues(alpha: 0.4),
          size: 18,
        ),
        suffixIcon: suffix,
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(
            color:
                Theme.of(
                  context,
                ).textTheme.bodyMedium?.color?.withValues(alpha: 0.2) ??
                Colors.grey,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: Theme.of(context).primaryColor),
          borderRadius: BorderRadius.circular(8),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        isDense: true,
      ),
    );
  }
}

// ─── HOTSPOT DIALOG ──────────────────────────────────────────

/// Kept as a dialog entry point for existing call sites.
class HotspotDialog extends StatelessWidget {
  const HotspotDialog({super.key});
  @override
  Widget build(BuildContext context) =>
      const Dialog.fullscreen(child: CameraNetworksScreen());
}

class _ServerConfigDialog extends StatefulWidget {
  const _ServerConfigDialog();

  @override
  State<_ServerConfigDialog> createState() => _ServerConfigDialogState();
}

class _ServerConfigDialogState extends State<_ServerConfigDialog> {
  late final TextEditingController _urlCtrl;
  late final TextEditingController _userCtrl;
  late final TextEditingController _passCtrl;
  late final TextEditingController _apiKeyCtrl;
  bool _testingConnection = false;
  String? _testResult;
  bool _isSuccess = false;
  bool _obscurePass = true;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsProvider>();
    _urlCtrl = TextEditingController(text: settings.serverUrl);
    _userCtrl = TextEditingController(text: settings.serverUsername);
    _passCtrl = TextEditingController(text: settings.serverPassword);
    _apiKeyCtrl = TextEditingController(text: settings.serverApiKey);
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _apiKeyCtrl.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    setState(() {
      _testingConnection = true;
      _testResult = null;
    });

    final settings = context.read<SettingsProvider>();
    settings.setServerUrl(_urlCtrl.text.trim());
    settings.setServerUsername(_userCtrl.text.trim());
    settings.setServerPassword(_passCtrl.text.trim());
    settings.setServerApiKey(_apiKeyCtrl.text.trim());

    final upload = context.read<UploadService>();
    final success = await upload.testConnection();

    if (mounted) {
      setState(() {
        _testingConnection = false;
        _isSuccess = success;
        _testResult = success
            ? '✓ Connected successfully!'
            : '✗ Connection failed: ${upload.lastError ?? "Unreachable"}';
      });
    }
  }

  void _save() {
    final settings = context.read<SettingsProvider>();
    settings.setServerUrl(_urlCtrl.text.trim());
    settings.setServerUsername(_userCtrl.text.trim());
    settings.setServerPassword(_passCtrl.text.trim());
    settings.setServerApiKey(_apiKeyCtrl.text.trim());

    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const AppText('Server configuration saved'),
        backgroundColor: Theme.of(context).primaryColor,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      title: Row(
        children: [
          Icon(Icons.cloud_sync, color: Theme.of(context).primaryColor),
          const SizedBox(width: 8),
          AppText(
            'Processing Server',
            style: TextStyle(
              color: Theme.of(context).textTheme.bodyLarge?.color,
              fontSize: 16,
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppText(
              'Configure file uploads here. Reconstruction requires a separate processing service.',
              style: TextStyle(
                color: Theme.of(
                  context,
                ).textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _urlCtrl,
              style: TextStyle(
                color: Theme.of(context).textTheme.bodyLarge?.color,
                fontSize: 13,
              ),
              decoration: const InputDecoration(
                labelText: 'Server URL',
                hintText: 'https://files.example.org',
                prefixIcon: Icon(Icons.link, size: 20),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _apiKeyCtrl,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              style: TextStyle(
                color: Theme.of(context).textTheme.bodyLarge?.color,
                fontSize: 13,
              ),
              decoration: const InputDecoration(
                labelText: 'API Key (Optional)',
                prefixIcon: Icon(Icons.key, size: 20),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _userCtrl,
                    style: TextStyle(
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                      fontSize: 13,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Username',
                      prefixIcon: Icon(Icons.person, size: 18),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _passCtrl,
                    obscureText: _obscurePass,
                    style: TextStyle(
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                      fontSize: 13,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock, size: 18),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePass
                              ? Icons.visibility_off
                              : Icons.visibility,
                          size: 18,
                        ),
                        onPressed: () =>
                            setState(() => _obscurePass = !_obscurePass),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Test status
            if (_testResult != null)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _isSuccess
                      ? Colors.green.withValues(alpha: 0.15)
                      : Colors.red.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _isSuccess ? Colors.green : Colors.red,
                    width: 0.5,
                  ),
                ),
                child: AppText(
                  _testResult!,
                  style: TextStyle(
                    color: _isSuccess ? Colors.greenAccent : Colors.redAccent,
                    fontSize: 11,
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        OutlinedButton.icon(
          onPressed: _testingConnection ? null : _testConnection,
          icon: _testingConnection
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.wifi_find, size: 16),
          label: const AppText('Test', style: TextStyle(fontSize: 12)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const AppText('Cancel'),
        ),
        ElevatedButton(onPressed: _save, child: const AppText('Save')),
      ],
    );
  }
}

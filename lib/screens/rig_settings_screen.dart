import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_text.dart';
import '../services/gopro_service.dart';
import '../services/gopro_setting_catalog.dart';
import '../widgets/glass_card.dart';
import '../widgets/gaussian_labs_qr.dart';

/// Every Open GoPro setting the connected cameras share, applied to the
/// whole rig at once and verified by read-back on each camera.
class RigSettingsScreen extends StatefulWidget {
  const RigSettingsScreen({super.key});

  @override
  State<RigSettingsScreen> createState() => _RigSettingsScreenState();
}

class _RigSettingsScreenState extends State<RigSettingsScreen> {
  Map<int, List<int>> _common = {};
  final Map<String, Map<int, int>> _values = {};
  bool _loading = false;
  int? _applying;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final service = context.read<GoProService>();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final common = await service.commonSupportedSettings();
      _values.clear();
      for (final camera in service.devices.where((d) => d.isConnected)) {
        _values[camera.name] = await service.readSettingValues(
          camera.id,
          common.keys.toList(),
        );
      }
      _common = common;
    } catch (e) {
      _error = '$e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _apply(int settingId, int value) async {
    final service = context.read<GoProService>();
    setState(() => _applying = settingId);
    try {
      final results = await service.applySettingToAll(settingId, value);
      final failed = results.entries.where((e) => e.value != null).toList();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: failed.isEmpty ? null : Colors.redAccent,
          content: AppText(
            failed.isEmpty
                ? 'Applied to {n} cameras'.replaceAll(
                    '{n}',
                    '${results.length}',
                  )
                : failed.map((e) => '${e.key}: ${e.value}').join('\n'),
          ),
        ),
      );
      // Some settings change which options are available for others.
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _applying = null);
    }
  }

  Future<void> _syncClocks() async {
    final service = context.read<GoProService>();
    try {
      await service.syncAllCameraClocks();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: AppText('Camera clocks set to phone time')),
      );
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.65);
    final cameraNames = _values.keys.toList();
    final specs = goProSettingCatalog
        .where((s) => _common.containsKey(s.id))
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const AppText('All camera settings'),
        actions: [
          IconButton(
            tooltip: 'Read again',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AppText(
            'Shows only options that every connected camera supports in its current mode, so the rig stays identical. Changing a value writes it to every camera and reads it back. Switch mode (photo/video) first: options depend on it.',
            style: TextStyle(color: muted, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _syncClocks,
                icon: const Icon(Icons.schedule, size: 16),
                label: const AppText('Sync camera clocks'),
              ),
              OutlinedButton.icon(
                onPressed: () => showExposureLabsQr(context),
                icon: const Icon(Icons.qr_code, size: 16),
                label: const AppText('Exposure via Labs QR (older cameras)'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          AppText(
            'ISO, shutter, white balance, EV, color and sharpness are set per project (Camera settings step) over Bluetooth on HERO10 and newer. The Labs QR is a fallback for older cameras.',
            style: TextStyle(color: muted, fontSize: 11),
          ),
          const SizedBox(height: 16),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            AppText(_error!, style: const TextStyle(color: Colors.redAccent)),
          for (final spec in specs) _settingTile(spec, cameraNames, muted),
        ],
      ),
    );
  }

  Widget _settingTile(
    GoProSettingSpec spec,
    List<String> cameraNames,
    Color muted,
  ) {
    final options = _common[spec.id]!;
    final current = {
      for (final name in cameraNames) name: _values[name]?[spec.id],
    };
    final distinct = current.values.whereType<int>().toSet();
    final mismatch = distinct.length > 1;
    final value = distinct.length == 1 && options.contains(distinct.first)
        ? distinct.first
        : null;
    String label(int v) => spec.values[v] ?? 'Value $v';
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: AppText(
                  spec.name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              if (_applying == spec.id)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                DropdownButton<int>(
                  value: value,
                  hint: AppText(mismatch ? 'Cameras differ' : 'Choose'),
                  onChanged: _applying != null
                      ? null
                      : (v) {
                          if (v != null) _apply(spec.id, v);
                        },
                  items: [
                    for (final option in options)
                      DropdownMenuItem(
                        value: option,
                        child: AppText(label(option)),
                      ),
                  ],
                ),
            ],
          ),
          if (mismatch)
            AppText(
              current.entries
                  .map(
                    (e) =>
                        '${e.key}: ${e.value == null ? '–' : label(e.value!)}',
                  )
                  .join(' · '),
              style: const TextStyle(color: Colors.orangeAccent, fontSize: 11),
            ),
        ],
      ),
    );
  }
}

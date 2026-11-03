import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../l10n/app_text.dart';
import '../services/gopro_service.dart';
import '../widgets/glass_card.dart';
import 'rig_settings_screen.dart';

/// Everything the app can do to the cameras without touching them: status,
/// mode, shutter, Wi-Fi, GPS, keep-awake, clocks, erase and power.
/// Actions apply to the cameras ticked at the top.
class RigControlScreen extends StatefulWidget {
  const RigControlScreen({super.key, this.only});

  /// Start with only this camera selected.
  final String? only;

  @override
  State<RigControlScreen> createState() => _RigControlScreenState();
}

class _RigControlScreenState extends State<RigControlScreen> {
  final Set<String> _selected = {};
  String? _running;
  String? _result;
  bool _resultIsError = false;

  @override
  void initState() {
    super.initState();
    final service = context.read<GoProService>();
    _selected.addAll(
      widget.only != null ? [widget.only!] : service.connectedIds,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    final service = context.read<GoProService>();
    for (final id in service.connectedIds.toList()) {
      try {
        await service.refreshStatus(id);
      } catch (_) {}
    }
  }

  Iterable<String> _targets(GoProService service) =>
      _selected.where(service.connectedIds.contains);

  Future<void> _run(
    String label,
    Future<List<String>> Function(GoProService s, List<String> ids) action, {
    String? done,
  }) async {
    if (_running != null) return;
    final service = context.read<GoProService>();
    final ids = _targets(service).toList();
    if (ids.isEmpty) {
      _show('Select at least one connected camera', true);
      return;
    }
    setState(() {
      _running = label;
      _result = null;
    });
    try {
      final failures = await action(service, ids);
      _show(
        failures.isEmpty ? (done ?? '$label: done') : failures.join('\n'),
        failures.isNotEmpty,
      );
    } catch (e) {
      _show('$e', true);
    } finally {
      if (mounted) setState(() => _running = null);
    }
  }

  void _show(String text, bool error) {
    if (!mounted) return;
    setState(() {
      _result = text;
      _resultIsError = error;
    });
  }

  Future<List<String>> _each(
    GoProService s,
    List<String> ids,
    Future<void> Function(String id) action,
  ) => s.forCameras(action, ids: ids);

  /// Time-lapse is flat mode 13 (video) on current models, 20 on older ones.
  Future<void> _timeLapse(GoProService s, String id) async {
    try {
      await s.selectMode(id, 13);
    } on UnsupportedError {
      await s.selectMode(id, 20);
    }
  }

  Future<bool> _confirm(String title, String text, {String? typed}) async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: AppText(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppText(text),
              if (typed != null) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  autofocus: true,
                  onChanged: (_) => update(() {}),
                  decoration: InputDecoration(
                    labelText: 'Type {word} to confirm'.replaceAll(
                      '{word}',
                      typed,
                    ),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const AppText('Cancel'),
            ),
            FilledButton(
              onPressed: typed == null || controller.text.trim() == typed
                  ? () => Navigator.pop(ctx, true)
                  : null,
              child: AppText(title),
            ),
          ],
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
    return ok == true;
  }

  void _labsFormatQr() => showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const AppText('Low-level format (GoPro Labs)'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AppText(
            'Only needed for a corrupted card. Requires GoPro Labs firmware; each camera asks for a confirmation on its own screen.',
          ),
          const SizedBox(height: 12),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(12),
            child: QrImageView(data: '!FORMAT', size: 220),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const AppText('Done'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final service = context.watch<GoProService>();
    final connected = service.devices.where((d) => d.isConnected).toList();
    final busy = _running != null;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final selectedCount = _targets(service).length;

    Widget action(
      IconData icon,
      String label,
      VoidCallback onTap, {
      Color? color,
    }) => SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        ),
        onPressed: busy || selectedCount == 0 ? null : onTap,
        icon: Icon(icon, size: 18, color: color),
        label: AppText(
          label,
          maxLines: 2,
          textAlign: TextAlign.center,
          style: TextStyle(color: color),
        ),
      ),
    );

    Widget section(String title, List<Widget> children, {String? note}) =>
        GlassCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppText(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              if (note != null) ...[
                const SizedBox(height: 6),
                AppText(note, style: TextStyle(color: muted, fontSize: 12)),
              ],
              const SizedBox(height: 12),
              // Two buttons per row, measured from the real card width.
              LayoutBuilder(
                builder: (context, box) => Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final child in children)
                      child is SwitchListTile
                          ? child
                          : SizedBox(
                              width: (box.maxWidth - 8) / 2,
                              child: child,
                            ),
                  ],
                ),
              ),
            ],
          ),
        );

    final status = _running != null || _result != null
        ? Material(
            elevation: 8,
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                child: Row(
                  children: [
                    if (_running != null)
                      const Padding(
                        padding: EdgeInsets.only(right: 12),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    Expanded(
                      child: AppText(
                        _running != null ? '$_running…' : _result!,
                        style: TextStyle(
                          color: _running != null
                              ? null
                              : _resultIsError
                              ? Theme.of(context).colorScheme.error
                              : Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                    if (_running == null)
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => setState(() => _result = null),
                        icon: const Icon(Icons.close),
                      ),
                  ],
                ),
              ),
            ),
          )
        : null;
    return Scaffold(
      bottomNavigationBar: status,
      appBar: AppBar(
        title: const AppText('Rig control'),
        actions: [
          IconButton(
            tooltip: 'Refresh status',
            onPressed: busy ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: connected.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: AppText(
                  'Connect a camera first. Sleeping cameras wake when you tap Connect all in Cameras.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
              children: [
                for (final cam in connected)
                  _StatusTile(
                    name: cam.displayName,
                    model: service.modelFor(cam.id),
                    status: service.statusOf(cam.id),
                    selected: _selected.contains(cam.id),
                    onChanged: busy
                        ? null
                        : (v) => setState(
                            () => v
                                ? _selected.add(cam.id)
                                : _selected.remove(cam.id),
                          ),
                  ),
                const SizedBox(height: 8),
                section(
                  'Mode and shutter',
                  [
                    action(
                      Icons.photo_camera,
                      'Photo',
                      () => _run(
                        'Photo mode',
                        (s, ids) => _each(s, ids, (id) => s.selectMode(id, 16)),
                      ),
                    ),
                    action(
                      Icons.videocam,
                      'Video',
                      () => _run(
                        'Video mode',
                        (s, ids) => _each(s, ids, (id) => s.selectMode(id, 12)),
                      ),
                    ),
                    action(
                      Icons.timelapse,
                      'Time-lapse',
                      () => _run(
                        'Time-lapse mode',
                        (s, ids) => _each(s, ids, (id) => _timeLapse(s, id)),
                      ),
                    ),
                    action(
                      Icons.fiber_manual_record,
                      'Start',
                      () => _run(
                        'Starting',
                        (s, ids) => _each(s, ids, s.startCapture),
                      ),
                      color: Colors.redAccent,
                    ),
                    action(
                      Icons.stop,
                      'Stop',
                      () => _run(
                        'Stopping',
                        (s, ids) => _each(s, ids, s.stopShutter),
                      ),
                    ),
                    action(
                      Icons.bookmark_add_outlined,
                      'HiLight',
                      () => _run(
                        'HiLight',
                        (s, ids) => _each(s, ids, s.addHiLightTag),
                      ),
                    ),
                  ],
                  note:
                      'For scans use a project: it verifies settings and logs every shot.',
                ),
                section('Camera', [
                  action(
                    Icons.tune,
                    'All settings',
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const RigSettingsScreen(),
                      ),
                    ),
                  ),
                  action(
                    Icons.schedule,
                    'Sync clocks',
                    () => _run(
                      'Setting clocks',
                      (s, ids) => _each(s, ids, s.syncCameraClock),
                    ),
                  ),
                  action(
                    Icons.wifi,
                    'Wi-Fi on',
                    () => _run(
                      'Camera Wi-Fi on',
                      (s, ids) => _each(s, ids, (id) => s.setWifiAp(id, true)),
                    ),
                  ),
                  action(
                    Icons.wifi_off,
                    'Wi-Fi off',
                    () => _run(
                      'Camera Wi-Fi off',
                      (s, ids) => _each(s, ids, (id) => s.setWifiAp(id, false)),
                    ),
                  ),
                  action(
                    Icons.gps_fixed,
                    'GPS on',
                    () => _run(
                      'GPS on',
                      (s, ids) => _each(s, ids, (id) => s.setGps(id, true)),
                    ),
                  ),
                  action(
                    Icons.gps_off,
                    'GPS off',
                    () => _run(
                      'GPS off',
                      (s, ids) => _each(s, ids, (id) => s.setGps(id, false)),
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: service.keepAwake,
                    onChanged: busy
                        ? null
                        : (v) => _run('Keep awake', (s, _) async {
                            await s.setKeepAwake(v);
                            return [];
                          }),
                    title: const AppText('Keep cameras awake'),
                    subtitle: const AppText(
                      'Auto power-off is set to Never while connected and restored when you disconnect or put a camera to sleep.',
                    ),
                  ),
                ]),
                section(
                  'SD card',
                  [
                    action(Icons.delete_forever, 'Erase all files', () async {
                      final targets = _targets(service);
                      final names = targets.map(service.nameOf).join(', ');
                      if (!await _confirm(
                        'Erase',
                        'Delete every photo and video on: $names? Import what you need first. This cannot be undone.',
                        typed: 'ERASE',
                      )) {
                        return;
                      }
                      await _run(
                        'Erasing (joins each camera Wi-Fi)',
                        (s, ids) => s.eraseSdCards(ids),
                        done: targets.length == 1
                            ? 'Card is empty'
                            : 'Cards are empty',
                      );
                    }, color: Colors.redAccent),
                    action(Icons.qr_code, 'Format (Labs QR)', _labsFormatQr),
                  ],
                  note:
                      'Erase deletes all media over the camera Wi-Fi and checks the card is empty. Android asks once per camera to join its Wi-Fi.',
                ),
                section(
                  'Power',
                  [
                    action(
                      Icons.bedtime_outlined,
                      'Sleep',
                      () => _run(
                        'Sleep',
                        (s, ids) => _each(s, ids, s.sleepCamera),
                        done: 'Sleeping. Connect all in Cameras wakes them.',
                      ),
                    ),
                    action(Icons.power_settings_new, 'Power off', () async {
                      if (!await _confirm(
                        'Power off',
                        'Powered-off cameras must be switched on by hand. Use Sleep to wake them from the app later.',
                      )) {
                        return;
                      }
                      await _run(
                        'Power off',
                        (s, ids) => _each(s, ids, s.powerDown),
                      );
                    }, color: Colors.redAccent),
                  ],
                  note:
                      'Sleep keeps Bluetooth listening, so the app can wake the camera again.',
                ),
              ],
            ),
    );
  }
}

class _StatusTile extends StatelessWidget {
  const _StatusTile({
    required this.name,
    required this.model,
    required this.status,
    required this.selected,
    required this.onChanged,
  });
  final String name, model;
  final Map<int, int> status;
  final bool selected;
  final ValueChanged<bool>? onChanged;

  static String _duration(int seconds) {
    final h = seconds ~/ 3600, m = (seconds % 3600) ~/ 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }

  static const _sdState = {
    0: 'OK',
    1: 'Full',
    2: 'No card',
    3: 'Format error',
    4: 'Busy',
    8: 'Swapped',
  };

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final warnings = [
      if (status[6] == 1) 'Overheating',
      if (status[85] == 1) 'Too cold',
      if ((status[70] ?? 100) < 20) 'Low battery',
      if (status[33] != null && status[33] != 0)
        'SD: ${_sdState[status[33]] ?? status[33]}',
    ];
    final chips = <String>[
      if (status[70] != null) '${status[70]}%',
      if (status[54] != null)
        '${(status[54]! / 1048576).toStringAsFixed(1)} GB free',
      if (status[34] != null)
        '{n} photos left'.replaceAll('{n}', '${status[34]}'),
      if (status[35] != null) '${_duration(status[35]!)} video',
      if (status[38] != null || status[39] != null)
        '{p} photos, {v} videos on card'
            .replaceAll('{p}', '${status[38] ?? 0}')
            .replaceAll('{v}', '${status[39] ?? 0}'),
      if (status[68] != null) status[68] == 1 ? 'GPS lock' : 'No GPS lock',
      if (status[10] == 1) 'Recording',
      if (status[69] == 1) 'Wi-Fi on',
    ];
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(4, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: selected,
            onChanged: onChanged == null ? null : (v) => onChanged!(v == true),
            title: AppText(
              name,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: AppText(model, style: TextStyle(color: muted)),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final c in chips)
                  Chip(label: AppText(c), visualDensity: VisualDensity.compact),
                for (final w in warnings)
                  Chip(
                    label: AppText(w),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: Colors.orange.withValues(alpha: 0.2),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

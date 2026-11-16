import '../l10n/app_text.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../services/gopro_service.dart';
import '../services/capture_coordinator.dart';
import '../services/capture_options.dart';
import '../models/scan_project.dart';
import '../services/project_service.dart';

import 'capture_session.dart';
import '../widgets/camera_bar.dart';
import '../widgets/gaussian_labs_qr.dart';

/// New project / project settings on one page: name, cameras, preset, capture
/// settings (sent and verified over Bluetooth) and exposure (Labs QR).
class ProjectFlowScreen extends StatefulWidget {
  const ProjectFlowScreen({super.key, this.project});

  /// Set to change an existing project's settings instead of creating one.
  final ScanProject? project;

  @override
  State<ProjectFlowScreen> createState() => _ProjectFlowScreenState();
}

class _ProjectFlowScreenState extends State<ProjectFlowScreen> {
  final _nameController = TextEditingController();
  final Map<String, String> _s = {};
  String? _presetName;
  bool _isStarting = false;
  String? _startError;

  String get _mode => _s['Mode'] ?? 'video';
  bool get _video => _mode == 'video';

  @override
  void initState() {
    super.initState();
    final project = widget.project;
    if (project != null) {
      _nameController.text = project.name;
      _s
        ..addAll(project.cameraSettings)
        ..['Mode'] = project.captureMode;
      return;
    }
    _applyPreset(SettingsProvider.builtInPresets.first, notify: false);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final provider = context.read<SettingsProvider>();
      await provider.ready;
      final defaults = await provider.getDefaultSettings();
      if (!mounted) return;
      setState(() {
        _s
          ..clear()
          ..addAll(defaults);
        _presetName = provider.allPresets
            .where((p) => _same(p.settings, defaults))
            .firstOrNull
            ?.name;
      });
    });
  }

  static bool _same(Map<String, String> a, Map<String, String> b) =>
      a.length == b.length && a.entries.every((e) => b[e.key] == e.value);

  void _applyPreset(CameraPreset preset, {bool notify = true}) {
    void apply() {
      _s
        ..clear()
        ..addAll(preset.settings);
      // Older presets used "Photo Output" / "Standard Photo".
      final format = _s.remove('Photo Output');
      if (format != null) _s['Photo Format'] ??= format;
      if (_s['Photo Format'] == 'Standard Photo') {
        _s['Photo Format'] = 'Standard';
      }
      _presetName = preset.name;
    }

    notify ? setState(apply) : apply();
  }

  void _set(String key, String value) => setState(() {
    _s[key] = value;
    _presetName = null;
  });

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  int _step = 0;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final goPro = context.watch<GoProService>();
    final cams = goPro.devices.where((d) => d.isConnected).length;
    const lastStep = 2;

    void next() {
      if (_step == 0 && _nameController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: AppText('Please enter a project name.')),
        );
        return;
      }
      if (_step < lastStep) {
        setState(() => _step++);
      } else {
        _start(context);
      }
    }

    return PopScope(
      canPop: !_isStarting,
      child: Scaffold(
        appBar: AppBar(
          title: AppText(
            widget.project == null
                ? settings.translate('new_project')
                : 'Project settings',
          ),
        ),
        body: AbsorbPointer(
          absorbing: _isStarting,
          child: Stepper(
            currentStep: _step,
            onStepTapped: (i) {
              if (i == 0 || _nameController.text.trim().isNotEmpty) {
                setState(() => _step = i);
              }
            },
            onStepContinue: next,
            onStepCancel: _step > 0 ? () => setState(() => _step--) : null,
            controlsBuilder: (context, details) {
              final last = details.stepIndex == lastStep;
              if (_isStarting && last) {
                return Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: AppText(goPro.capture.progress)),
                    ],
                  ),
                );
              }
              return Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (last && _startError != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: AppText(
                          'Project not started: $_startError',
                          style: const TextStyle(color: Colors.redAccent),
                        ),
                      ),
                    Row(
                      children: [
                        ElevatedButton(
                          onPressed: last && cams == 0
                              ? null
                              : details.onStepContinue,
                          child: AppText(
                            !last
                                ? settings.translate('next')
                                : cams == 0
                                ? 'Connect a camera first'
                                : widget.project == null
                                ? settings.translate('start_capture')
                                : 'Save and continue',
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (details.stepIndex > 0)
                          TextButton(
                            onPressed: details.onStepCancel,
                            child: AppText(settings.translate('back')),
                          ),
                      ],
                    ),
                  ],
                ),
              );
            },
            steps: [
              Step(
                title: AppText(settings.translate('project_name')),
                subtitle: AppText(
                  cams == 0
                      ? 'No camera connected'
                      : '$cams camera${cams == 1 ? '' : 's'} connected',
                ),
                isActive: _step >= 0,
                content: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        labelText: settings.translate('enter_project_name'),
                        border: const OutlineInputBorder(),
                        hintText: 'e.g. Living Room Scan',
                      ),
                    ),
                    _header('Cameras'),
                    const CameraBar(),
                  ],
                ),
              ),
              Step(
                title: AppText(settings.translate('camera_settings')),
                subtitle: AppText(_presetName ?? 'Custom'),
                isActive: _step >= 1,
                content: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const CameraBar(),
                    _header('Preset'),
                    SizedBox(
                      height: 44,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          for (final preset in settings.allPresets)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                avatar: AppText(preset.icon),
                                label: AppText(preset.name),
                                selected: _presetName == preset.name,
                                onSelected: (_) => _applyPreset(preset),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if ((_s['Guidance'] ?? '').isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: AppText(
                          _s['Guidance']!,
                          style: TextStyle(
                            color: context.ink(0.6),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    _header('Capture'),
                    ..._captureRows(context),
                    _header('Exposure'),
                    ..._exposureRows(context),
                  ],
                ),
              ),
              Step(
                title: AppText(settings.translate('summary')),
                isActive: _step >= 2,
                content: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _summary(Icons.folder, 'Project', _nameController.text),
                    _summary(Icons.tune, 'Preset', _presetName ?? 'Custom'),
                    _summary(
                      _video ? Icons.videocam : Icons.photo_camera,
                      'Capture',
                      _video
                          ? 'Video ${_s['Resolution'] ?? ''} / ${_s['FPS'] ?? ''} fps / ${_s['Lens'] ?? ''}'
                          : 'Photo ${_s['Photo Format'] ?? ''} / ${_s['Interval'] ?? ''} / ${_s['Lens'] ?? ''}',
                    ),
                    _summary(Icons.exposure, 'Exposure', exposureSummary(_s)),
                    _summary(Icons.linked_camera, 'Cameras', '$cams connected'),
                    const SizedBox(height: 4),
                    AppText(
                      'Start sends every setting to all cameras over Bluetooth and reads it back.',
                      style: TextStyle(color: context.ink(0.54), fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _summary(IconData icon, String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Theme.of(context).primaryColor),
        const SizedBox(width: 8),
        SizedBox(
          width: 80,
          child: AppText(label, style: TextStyle(color: context.ink(0.54))),
        ),
        Expanded(
          child: AppText(
            value.isEmpty ? '-' : value,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    ),
  );

  List<Widget> _captureRows(BuildContext context) => [
    SegmentedButton<String>(
      segments: const [
        ButtonSegment(
          value: 'video',
          icon: Icon(Icons.videocam),
          label: AppText('Video'),
        ),
        ButtonSegment(
          value: 'photo',
          icon: Icon(Icons.photo_camera),
          label: AppText('Photo'),
        ),
      ],
      selected: {_mode},
      onSelectionChanged: (v) => _set('Mode', v.first),
    ),
    const SizedBox(height: 12),
    if (_video) ...[
      _row('Resolution', 'Resolution', CaptureOptions.resolutions, '4K'),
      _row('Frame rate', 'FPS', CaptureOptions.fps, '30'),
      _row('Lens', 'Lens', CaptureOptions.videoLenses, 'Linear'),
      _row('Bitrate', 'Bitrate', CaptureOptions.bitrates, 'High'),
      _row(
        'Stabilization',
        'Hypersmooth',
        CaptureOptions.hypersmooth,
        keepCamera,
      ),
      _row('Bit depth', 'Bit Depth', CaptureOptions.bitDepth, keepCamera),
    ] else ...[
      _row(
        'Photo format',
        'Photo Format',
        CaptureOptions.photoFormats,
        'Standard',
      ),
      _row('Interval', 'Interval', CaptureOptions.intervals, '1s'),
      if ((_s['Interval'] ?? '1s') != 'Off') ...[
        _row('Timing', 'Interval Timing', const [
          cameraTimerTiming,
          appTiming,
        ], cameraTimerTiming),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: AppText(
            (_s['Interval Timing'] ?? cameraTimerTiming) == cameraTimerTiming
                ? 'Each camera runs its own timer, started together: exact interval.'
                : 'The app fires every shot and waits for all cameras: confirmed shots, about 3 s apart at best.',
            style: TextStyle(color: context.ink(0.54), fontSize: 11),
          ),
        ),
      ],
      _row('Lens', 'Lens', CaptureOptions.photoLenses, 'Linear'),
    ],
  ];

  List<Widget> _exposureRows(BuildContext context) => [
    _row('ISO min', 'Target ISO Min', CaptureOptions.iso, keepCamera),
    _row('ISO max', 'Target ISO', CaptureOptions.iso, keepCamera),
    _row('Shutter', 'Target Shutter', CaptureOptions.shutter, keepCamera),
    _row(
      'White balance',
      'Target White Balance',
      CaptureOptions.whiteBalance,
      keepCamera,
    ),
    _row('EV', 'Target EV', CaptureOptions.ev, keepCamera),
    _row('Color', 'Target Color', CaptureOptions.color, keepCamera),
    _row('Sharpness', 'Target Sharpness', CaptureOptions.sharpness, keepCamera),
    AppText(
      'Sent over Bluetooth and read back (HERO10 and newer). Shutter steps depend on the frame rate and apply to video. For older cameras use the GoPro Labs QR.',
      style: TextStyle(color: context.ink(0.54), fontSize: 11),
    ),
    TextButton.icon(
      onPressed: () => showSettingsLabsQr(context, Map.of(_s)),
      icon: const Icon(Icons.qr_code, size: 18),
      label: const AppText('GoPro Labs QR (fallback)'),
    ),
  ];

  Widget _header(String text) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 8),
    child: AppText(
      text.toUpperCase(),
      style: TextStyle(
        color: Theme.of(context).primaryColor,
        fontWeight: FontWeight.bold,
        fontSize: 12,
        letterSpacing: 1.2,
      ),
    ),
  );

  Widget _row(String label, String key, List<String> options, String fallback) {
    final current = _s[key];
    final value = options.contains(current)
        ? current!
        : options.contains(fallback)
        ? fallback
        : options.first;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: AppText(label, style: TextStyle(color: context.ink(0.75))),
          ),
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: value,
              key: ValueKey('$key=$value'),
              isExpanded: true,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
              items: [
                for (final o in options)
                  DropdownMenuItem(value: o, child: AppText(o)),
              ],
              onChanged: (v) {
                if (v != null) _set(key, v);
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Settings for the cameras: only keys of the chosen mode, with each
  /// dropdown's shown value written out explicitly.
  Map<String, String> _cameraSettings() {
    String pick(String key, List<String> options, String fallback) =>
        options.contains(_s[key]) ? _s[key]! : fallback;
    final c = <String, String>{'Mode': _mode};
    if (_video) {
      c['Resolution'] = pick('Resolution', CaptureOptions.resolutions, '4K');
      c['FPS'] = pick('FPS', CaptureOptions.fps, '30');
      c['Lens'] = pick('Lens', CaptureOptions.videoLenses, 'Linear');
      c['Bitrate'] = pick('Bitrate', CaptureOptions.bitrates, 'High');
      c['Hypersmooth'] = pick(
        'Hypersmooth',
        CaptureOptions.hypersmooth,
        keepCamera,
      );
      c['Bit Depth'] = pick('Bit Depth', CaptureOptions.bitDepth, keepCamera);
      c['Interval'] = 'Off';
    } else {
      c['Photo Format'] = pick(
        'Photo Format',
        CaptureOptions.photoFormats,
        'Standard',
      );
      c['Interval'] = pick('Interval', CaptureOptions.intervals, '1s');
      c['Interval Timing'] = pick('Interval Timing', const [
        cameraTimerTiming,
        appTiming,
      ], cameraTimerTiming);
      c['Lens'] = pick('Lens', CaptureOptions.photoLenses, 'Linear');
    }
    for (final (key, options) in [
      ('Target ISO Min', CaptureOptions.iso),
      ('Target ISO', CaptureOptions.iso),
      ('Target Shutter', CaptureOptions.shutter),
      ('Target White Balance', CaptureOptions.whiteBalance),
      ('Target EV', CaptureOptions.ev),
      ('Target Color', CaptureOptions.color),
      ('Target Sharpness', CaptureOptions.sharpness),
    ]) {
      c[key] = pick(key, options, keepCamera);
    }
    c['Orientation'] = _s['Orientation'] ?? 'Portrait';
    if (_s['Guidance'] != null) c['Guidance'] = _s['Guidance']!;
    if (_presetName != null) c['Preset'] = _presetName!;
    return c;
  }

  Future<void> _start(BuildContext context) async {
    if (_isStarting) return;
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: AppText('Please enter a project name.')),
      );
      return;
    }
    setState(() {
      _isStarting = true;
      _startError = null;
    });
    final projectService = context.read<ProjectService>();
    final goPro = context.read<GoProService>();
    final cameraSettings = _cameraSettings();
    try {
      await goPro.prepareCapture(_mode, cameraSettings);
      if (!mounted) return;
      final existing = widget.project;
      final ScanProject project;
      if (existing != null) {
        existing
          ..name = name
          ..captureMode = _mode
          ..cameraSettings = cameraSettings;
        await projectService.updateProject(existing);
        project = existing;
      } else {
        project = await projectService.createProject(
          name,
          captureMode: _mode,
          smartCapture: false,
          cameraSettings: cameraSettings,
        );
      }
      if (!context.mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) =>
              CaptureSessionScreen(project: project, camerasPrepared: true),
        ),
      );
    } catch (e) {
      debugPrint('Project start failed: $e');
      if (mounted) {
        setState(() {
          _startError = describeError(e);
          _isStarting = false;
        });
      }
    }
  }
}

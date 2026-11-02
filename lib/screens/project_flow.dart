import '../l10n/app_text.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../services/gopro_service.dart';
import '../services/capture_coordinator.dart';
import '../services/project_service.dart';

import 'capture_session.dart';
import '../widgets/gaussian_labs_qr.dart';

class ProjectFlowScreen extends StatefulWidget {
  const ProjectFlowScreen({super.key});

  @override
  State<ProjectFlowScreen> createState() => _ProjectFlowScreenState();
}

class _ProjectFlowScreenState extends State<ProjectFlowScreen> {
  int _currentStep = 0;
  final _nameController = TextEditingController();
  String _captureMode = 'photo';
  final bool _smartCapture = false;

  // Camera settings for the project
  String _photoFormat = 'Standard Photo';
  String _interval = '1s';
  String _intervalTiming = cameraTimerTiming;
  String _guidance =
      SettingsProvider.builtInPresets.first.settings['Guidance']!;
  String _orientation = 'Portrait';
  String _targetIso = '100';
  String _resolution = '4K';
  String _fps = '30';
  String _lens = 'Linear';
  String _shutter = 'Camera preset';
  String _whiteBalance = 'Camera preset';
  String _bitrate = 'High';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final provider = context.read<SettingsProvider>();
      await provider.ready;
      final defaults = await provider.getDefaultSettings();
      if (!mounted) return;
      setState(() {
        _captureMode = defaults['Mode'] ?? 'photo';
        _photoFormat = defaults['Photo Format'] ?? 'Standard Photo';
        _interval = provider.captureInterval;
        _intervalTiming = defaults['Interval Timing'] ?? cameraTimerTiming;
        _resolution = defaults['Resolution'] ?? '4K';
        _fps = defaults['FPS'] ?? '30';
        _lens = defaults['Lens'] ?? 'Linear';
        _guidance = defaults['Guidance'] ?? _guidance;
        _orientation = defaults['Orientation'] ?? 'Portrait';
        _targetIso = defaults['Target ISO'] ?? '100';
      });
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final goPro = context.watch<GoProService>();
    final connectedCams = goPro.devices.where((d) => d.isConnected).toList();

    return PopScope(
      canPop: !_isStarting,
      child: Scaffold(
        appBar: AppBar(title: AppText(settings.translate('new_project'))),
        body: AbsorbPointer(
          absorbing: _isStarting,
          child: Stepper(
            currentStep: _currentStep,
            onStepContinue: () {
              if (_currentStep == 0 && _nameController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: AppText('Please enter a project name.'),
                  ),
                );
                return;
              }
              if (_currentStep < 2) {
                setState(() => _currentStep++);
              } else {
                // Final step: Create the project and navigate to capture session
                _createProjectAndStart(context);
              }
            },
            onStepCancel: () {
              if (_currentStep > 0) {
                setState(() => _currentStep--);
              }
            },
            controlsBuilder: (BuildContext context, ControlsDetails details) {
              final isLastStep = _currentStep == 2;
              if (_isStarting) {
                return Padding(
                  padding: const EdgeInsets.only(top: 16.0),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: AppText(
                          goPro.capture.progress,
                          style: TextStyle(
                            color: context.ink(0.7),
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }
              return Padding(
                padding: const EdgeInsets.only(top: 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isLastStep &&
                        details.stepIndex == _currentStep &&
                        _startError != null)
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
                          onPressed: details.onStepContinue,
                          child: AppText(
                            isLastStep
                                ? settings.translate('start_capture')
                                : settings.translate('next'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (_currentStep > 0)
                          TextButton(
                            onPressed: details.onStepCancel,
                            child: AppText(
                              settings.translate('back'),
                              style: TextStyle(color: context.ink(0.7)),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              );
            },
            steps: [
              // Step 1: Project Name & Mode
              Step(
                title: AppText(settings.translate('project_name')),
                content: Column(
                  children: [
                    TextFormField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        labelText: settings.translate('enter_project_name'),
                        border: const OutlineInputBorder(),
                        hintText: 'e.g. Living Room Scan',
                        hintStyle: TextStyle(color: context.ink(0.3)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Capture Mode Selection
                    AppText(
                      settings.translate('capture_mode'),
                      style: TextStyle(
                        color: context.ink(0.7),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _buildModeChip(
                          'photo',
                          Icons.photo_camera,
                          settings.translate('single_frames'),
                        ),
                        const SizedBox(width: 8),
                        _buildModeChip(
                          'video',
                          Icons.videocam,
                          settings.translate('record_videos'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      leading: const Icon(Icons.info_outline),
                      title: AppText(settings.translate('smart_capture')),
                      subtitle: AppText(
                        settings.translate('smart_capture_desc'),
                      ),
                    ),
                  ],
                ),
                isActive: _currentStep >= 0,
              ),

              // Step 2: Camera Settings
              Step(
                title: AppText(settings.translate('camera_settings')),
                content: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (connectedCams.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.orange.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.warning_amber,
                              color: Colors.orange,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: AppText(
                                settings.translate('no_cameras_warning'),
                                style: const TextStyle(
                                  color: Colors.orange,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).primaryColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.check_circle,
                              color: Theme.of(context).primaryColor,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            AppText(
                              '${connectedCams.length} camera${connectedCams.length > 1 ? 's' : ''} connected',
                              style: TextStyle(
                                color: Theme.of(context).primaryColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 16),
                    // ─── Preset Selector ───
                    AppText(
                      settings.translate('select_preset'),
                      style: TextStyle(
                        color: context.ink(0.7),
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 42,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: settings.allPresets.map((preset) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ActionChip(
                              avatar: AppText(
                                preset.icon,
                                style: const TextStyle(fontSize: 14),
                              ),
                              label: AppText(
                                preset.name,
                                style: const TextStyle(fontSize: 11),
                              ),
                              backgroundColor: context.ink().withValues(
                                alpha: 0.06,
                              ),
                              side: BorderSide(
                                color: Theme.of(
                                  context,
                                ).primaryColor.withValues(alpha: 0.3),
                              ),
                              onPressed: () {
                                setState(() {
                                  _captureMode =
                                      preset.settings['Mode'] ?? _captureMode;
                                  _photoFormat =
                                      preset.settings['Photo Format'] ??
                                      preset.settings['Photo Output'] ??
                                      _photoFormat;
                                  _interval =
                                      preset.settings['Interval'] ?? _interval;
                                  _resolution =
                                      preset.settings['Resolution'] ??
                                      _resolution;
                                  _guidance = preset.settings['Guidance'] ?? '';
                                  _orientation =
                                      preset.settings['Orientation'] ??
                                      'Portrait';
                                  _targetIso =
                                      preset.settings['Target ISO'] ?? '100';
                                  _fps = preset.settings['FPS'] ?? _fps;
                                  _lens = preset.settings['Lens'] ?? _lens;
                                  _shutter =
                                      preset.settings['Shutter'] ?? _shutter;
                                  _whiteBalance =
                                      preset.settings['White Balance'] ??
                                      _whiteBalance;
                                  _bitrate =
                                      preset.settings['Bitrate'] ?? _bitrate;
                                });
                                if (preset.settings['Labs Recipe'] ==
                                    'daylight') {
                                  showGaussianLabsQr(context);
                                }
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: AppText(
                                      '${preset.icon} ${preset.name} selected; camera confirmation pending',
                                    ),
                                    backgroundColor: Theme.of(
                                      context,
                                    ).primaryColor,
                                    duration: const Duration(seconds: 1),
                                  ),
                                );
                              },
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_captureMode == 'photo') ...[
                      _buildSettingDropdown('Photo Mode', _photoFormat, [
                        'Standard',
                        'SuperPhoto',
                        'RAW',
                        'HDR',
                      ], (v) => setState(() => _photoFormat = v)),
                      _buildSettingDropdown('Interval', _interval, [
                        'Off',
                        '0.5s',
                        '1s',
                        '2s',
                        '5s',
                      ], (v) => setState(() => _interval = v)),
                      if (_interval != 'Off')
                        _buildSettingDropdown(
                          'Interval Timing',
                          _intervalTiming,
                          [cameraTimerTiming, appTiming],
                          (v) => setState(() => _intervalTiming = v),
                        ),
                      if (_interval != 'Off')
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: AppText(
                            _intervalTiming == cameraTimerTiming
                                ? 'Every camera runs its own timer, started together: exact interval, but single shots are not confirmed.'
                                : 'The app fires each shot and waits until every camera has saved it: every shot confirmed, about 3 s apart at best.',
                            style: TextStyle(
                              color: context.ink(0.54),
                              fontSize: 11,
                            ),
                          ),
                        ),
                      _buildSettingDropdown(
                        'Lens',
                        _lens == 'SuperView' ? 'Wide' : _lens,
                        ['Linear', 'Wide'],
                        (v) => setState(() => _lens = v),
                      ),
                    ],
                    if (_captureMode == 'video') ...[
                      _buildSettingDropdown('Resolution', _resolution, [
                        '1080p',
                        '2.7K',
                        '4K',
                        '5.3K',
                      ], (v) => setState(() => _resolution = v)),
                      _buildSettingDropdown('FPS', _fps, [
                        '24',
                        '30',
                        '60',
                        '120',
                      ], (v) => setState(() => _fps = v)),
                      _buildSettingDropdown('Bitrate', _bitrate, [
                        'Standard',
                        'High',
                      ], (v) => setState(() => _bitrate = v)),
                      _buildSettingDropdown('Lens', _lens, [
                        'Linear',
                        'Wide',
                        'SuperView',
                      ], (v) => setState(() => _lens = v)),
                    ],
                    AppText(
                      _guidance,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const AppText(
                      'Set these targets on every camera, or show the ISO / white balance QR from Rig settings. The app cannot read them back.',
                      style: TextStyle(color: Colors.orange, fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    _buildSettingDropdown('Target ISO (manual)', _targetIso, [
                      'Camera preset',
                      '100',
                      '200',
                      '400',
                      '800',
                      '1600',
                    ], (v) => setState(() => _targetIso = v)),
                    _buildSettingDropdown('Target shutter (manual)', _shutter, [
                      'Camera preset',
                      'Auto',
                      ...(_captureMode == 'photo'
                          ? ['1/125', '1/250', '1/500', '1/1000']
                          : ['1/60', '1/120', '1/240', '1/480']),
                    ], (v) => setState(() => _shutter = v)),
                    _buildSettingDropdown(
                      'Target white balance (manual)',
                      _whiteBalance,
                      [
                        'Camera preset',
                        'Auto',
                        '3200K',
                        '4000K',
                        '5500K',
                        '6500K',
                      ],
                      (v) => setState(() => _whiteBalance = v),
                    ),
                  ],
                ),
                isActive: _currentStep >= 1,
              ),

              // Step 3: Summary & Start
              Step(
                title: AppText(settings.translate('summary')),
                content: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSummaryRow(
                      Icons.folder,
                      'Project',
                      _nameController.text.isEmpty ? '—' : _nameController.text,
                    ),
                    _buildSummaryRow(
                      Icons.camera,
                      'Mode',
                      _captureMode == 'photo'
                          ? 'Photo ($_photoFormat)'
                          : 'Video',
                    ),
                    if (_captureMode == 'photo') ...[
                      _buildSummaryRow(Icons.image, 'Format', _photoFormat),
                      _buildSummaryRow(Icons.timer, 'Interval', _interval),
                      if (_interval != 'Off')
                        _buildSummaryRow(
                          Icons.schedule,
                          'Interval Timing',
                          _intervalTiming,
                        ),
                    ],
                    if (_captureMode == 'video') ...[
                      _buildSummaryRow(
                        Icons.aspect_ratio,
                        'Resolution',
                        _resolution,
                      ),
                      _buildSummaryRow(Icons.speed, 'FPS', _fps),
                    ],
                    _buildSummaryRow(Icons.camera_alt, 'Lens', _lens),
                    _buildSummaryRow(
                      Icons.exposure,
                      'Target ISO (manual)',
                      _targetIso,
                    ),
                    _buildSummaryRow(
                      Icons.stay_current_portrait,
                      'Mounting (manual)',
                      _orientation,
                    ),
                    const AppText(
                      'Check exposure and mounting on every camera. The app verifies only supported BLE settings.',
                    ),
                    _buildSummaryRow(
                      Icons.linked_camera,
                      'Cameras',
                      '${connectedCams.length} connected',
                    ),
                    const SizedBox(height: 12),
                    AppText(
                      settings.translate('start_capture_hint'),
                      style: TextStyle(color: context.ink(0.54), fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
                isActive: _currentStep >= 2,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModeChip(String mode, IconData icon, String label) {
    final isSelected = _captureMode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _captureMode = mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? Theme.of(context).primaryColor.withValues(alpha: 0.2)
                : context.ink(0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? Theme.of(context).primaryColor
                  : context.ink(0.24),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: isSelected
                    ? Theme.of(context).primaryColor
                    : context.ink(0.54),
                size: 28,
              ),
              const SizedBox(height: 4),
              AppText(
                label,
                style: TextStyle(
                  color: isSelected ? context.ink() : context.ink(0.54),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettingDropdown(
    String label,
    String currentValue,
    List<String> options,
    ValueChanged<String> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: AppText(
              label,
              style: TextStyle(color: context.ink(0.7), fontSize: 14),
            ),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: context.ink(0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: context.ink(0.24)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: options.contains(currentValue)
                      ? currentValue
                      : options.first,
                  dropdownColor: const Color(0xFF2A2A2A),
                  style: TextStyle(color: context.ink(), fontSize: 14),
                  isExpanded: true,
                  items: options
                      .map((o) => DropdownMenuItem(value: o, child: AppText(o)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) onChanged(v);
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Theme.of(context).primaryColor),
          const SizedBox(width: 8),
          AppText(
            '$label: ',
            style: TextStyle(color: context.ink(0.54), fontSize: 14),
          ),
          AppText(
            value,
            style: TextStyle(
              color: context.ink(),
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  bool _isStarting = false;
  String? _startError;

  Future<void> _createProjectAndStart(BuildContext context) async {
    if (_isStarting) return;
    setState(() {
      _isStarting = true;
      _startError = null;
    });

    final projectService = context.read<ProjectService>();
    final goPro = context.read<GoProService>();

    final cameraSettings = <String, String>{};

    if (_captureMode == 'photo') {
      cameraSettings['Photo Format'] = _photoFormat;
      cameraSettings['Interval'] = _interval;
      cameraSettings['Interval Timing'] = _intervalTiming;
      cameraSettings['Lens'] = _lens == 'SuperView' ? 'Wide' : _lens;
    } else {
      cameraSettings['Resolution'] = _resolution;
      cameraSettings['FPS'] = _fps;
      cameraSettings['Bitrate'] = _bitrate;
      cameraSettings['Lens'] = _lens;
    }

    // Shared settings
    cameraSettings['Orientation'] = _orientation;
    cameraSettings['Target ISO'] = _targetIso;
    cameraSettings['Guidance'] = _guidance;
    cameraSettings['ISO Max'] = 'Camera preset';
    cameraSettings['Shutter'] = 'Camera preset';
    cameraSettings['Target Shutter'] = _shutter;
    cameraSettings['White Balance'] = 'Camera preset';
    cameraSettings['Target White Balance'] = _whiteBalance;

    // Show a loading indicator
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: AppText('Syncing camera modes & settings...'),
          duration: Duration(seconds: 2),
        ),
      );
    }

    try {
      await goPro.prepareCapture(_captureMode, cameraSettings);
      if (!mounted) return;
      final project = await projectService.createProject(
        _nameController.text.trim(),
        captureMode: _captureMode,
        smartCapture: _smartCapture,
        cameraSettings: cameraSettings,
      );
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
      if (mounted) setState(() => _startError = '$e');
      if (context.mounted) ScaffoldMessenger.of(context).clearSnackBars();
      if (mounted) setState(() => _isStarting = false);
    }
  }
}

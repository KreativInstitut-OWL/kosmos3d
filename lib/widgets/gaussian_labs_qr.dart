import 'dart:async';
import '../l10n/app_text.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/capture_options.dart';

/// GoPro Labs video recipe. No shutter/start command is included.
/// Linear lens is subsequently set and verified by BLE (setting 121).
const gaussianVideoLabsRecipe = 'mVr4p30w55i2M1i2S45b1e0hS0';
Future<void> showGaussianLabsQr(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: const AppText('Gaussian Splatting - daylight video'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AppText(
            'Requires GoPro Labs firmware. Show this QR to each camera and confirm the settings on its display. No capture is started.',
          ),
          const SizedBox(height: 12),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(12),
            child: QrImageView(data: gaussianVideoLabsRecipe, size: 230),
          ),
          const SizedBox(height: 12),
          const AppText(
            '4K / 30 fps / 5500K / ISO 100-200 / 45-degree shutter (1/240 s) / high bitrate / stabilization off. Select Linear in the app. Use good lighting.',
          ),
          const SizedBox(height: 8),
          const AppText(
            'QR acceptance and Protune values are not verified over BLE. Keep the configured Video preset active on each camera.',
            style: TextStyle(color: Colors.orange),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const AppText('Close'),
      ),
    ],
  ),
);

/// Labs command for fixed exposure plus a camera clock set to this phone.
/// ISO syntax: `i{max/100}M{min/100}`; white balance: `w{kelvin/100}` or `wA`.
String exposureLabsRecipe({
  required int iso,
  required int? kelvin,
  required DateTime now,
}) {
  String two(int v) => v.toString().padLeft(2, '0');
  final isoCode = '${iso ~/ 100}';
  final wb = kelvin == null ? 'wA' : 'w${kelvin ~/ 100}';
  final time =
      '${two(now.year % 100)}${two(now.month)}${two(now.day)}'
      '${two(now.hour)}${two(now.minute)}${two(now.second)}'
      '.${now.millisecond.toString().padLeft(3, '0')}';
  return 'i${isoCode}M$isoCode${wb}oT$time';
}

Future<void> showExposureLabsQr(BuildContext context, {int iso = 100}) =>
    showDialog<void>(
      context: context,
      builder: (_) => _ExposureLabsDialog(initialIso: iso),
    );

class _ExposureLabsDialog extends StatefulWidget {
  const _ExposureLabsDialog({required this.initialIso});
  final int initialIso;

  @override
  State<_ExposureLabsDialog> createState() => _ExposureLabsDialogState();
}

class _ExposureLabsDialogState extends State<_ExposureLabsDialog> {
  late int _iso = widget.initialIso;
  int? _kelvin = 5500;
  late final Timer _tick;

  @override
  void initState() {
    super.initState();
    // The embedded clock must be current when the camera reads the code.
    _tick = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final recipe = exposureLabsRecipe(
      iso: _iso,
      kelvin: _kelvin,
      now: DateTime.now(),
    );
    return AlertDialog(
      title: const AppText('Same exposure on every camera'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppText(
              'GoPro Labs firmware only. Hold the QR in front of each camera until it beeps. Sets ISO, white balance and the camera clock to this phone.',
            ),
            const SizedBox(height: 12),
            const AppText('ISO'),
            Wrap(
              spacing: 6,
              children: [
                for (final iso in const [100, 200, 400, 800, 1600])
                  ChoiceChip(
                    label: Text('$iso'),
                    selected: _iso == iso,
                    onSelected: (_) => setState(() => _iso = iso),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            const AppText('White balance'),
            Wrap(
              spacing: 6,
              children: [
                for (final k in const [null, 4000, 5000, 5500, 6500])
                  ChoiceChip(
                    label: AppText(k == null ? 'Auto' : '${k}K'),
                    selected: _kelvin == k,
                    onSelected: (_) => setState(() => _kelvin = k),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Center(
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.all(12),
                child: QrImageView(data: recipe, size: 220),
              ),
            ),
            const SizedBox(height: 6),
            Center(
              child: SelectableText(
                recipe,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
              ),
            ),
            const SizedBox(height: 8),
            const AppText(
              'Stock firmware ignores this code. Then set ISO and white balance once in each camera’s Protune menu.',
              style: TextStyle(color: Colors.orange, fontSize: 12),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const AppText('Close'),
        ),
      ],
    );
  }
}

/// Labs QR with every exposure target of a project or preset. The clock in
/// the code is refreshed continuously so cameras also get the phone's time.
Future<void> showSettingsLabsQr(
  BuildContext context,
  Map<String, String> settings,
) => showDialog<void>(
  context: context,
  builder: (_) => _SettingsLabsDialog(settings: settings),
);

class _SettingsLabsDialog extends StatefulWidget {
  const _SettingsLabsDialog({required this.settings});
  final Map<String, String> settings;

  @override
  State<_SettingsLabsDialog> createState() => _SettingsLabsDialogState();
}

class _SettingsLabsDialogState extends State<_SettingsLabsDialog> {
  late final Timer _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final recipe = labsRecipe(widget.settings, now: DateTime.now());
    return AlertDialog(
      title: const AppText('Exposure QR (GoPro Labs)'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppText(exposureSummary(widget.settings)),
            const SizedBox(height: 8),
            if (recipe == null)
              const AppText(
                'All exposure values are "Camera preset" - nothing to send.',
              )
            else ...[
              const AppText(
                'Hold the QR in front of each camera until it beeps. Needs GoPro Labs firmware; without Labs, set these values on each camera.',
              ),
              const SizedBox(height: 12),
              Center(
                child: Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(12),
                  child: QrImageView(data: recipe, size: 230),
                ),
              ),
              const SizedBox(height: 6),
              SelectableText(
                recipe,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
              ),
              if (widget.settings['Mode'] != 'video' &&
                  (widget.settings['Target Shutter'] ?? keepCamera) !=
                      keepCamera)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: AppText(
                    'Labs sets the shutter for video only. For photos set it on the camera.',
                    style: TextStyle(color: Colors.orange),
                  ),
                ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const AppText('Close'),
        ),
      ],
    );
  }
}

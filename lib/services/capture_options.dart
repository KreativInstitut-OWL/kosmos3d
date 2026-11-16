/// Every capture option the app offers, shared by project setup, the preset
/// editor and the built-in presets. Values the camera does not support in its
/// current preset are rejected by the capability check before writing.
///
/// Two kinds of settings:
/// - BLE settings (mode, resolution, fps, lens, bitrate, stabilization, bit
///   depth, photo format, interval): written and read back over Bluetooth.
/// - Exposure targets ("Target ..." keys: ISO, shutter, white balance, EV,
///   color, sharpness): not in the Open GoPro API. They go to the camera via a
///   GoPro Labs QR code built by [labsRecipe].
library;

const keepCamera = 'Camera preset';

/// Set by the build: --dart-define=APP_VERSION=... --dart-define=APP_BUILD=...
const appVersion = String.fromEnvironment('APP_VERSION', defaultValue: '2.3.0');
const appBuild = String.fromEnvironment('APP_BUILD', defaultValue: 'dev');

class CaptureOptions {
  static const photoFormats = ['Standard', 'SuperPhoto', 'HDR', 'RAW'];
  static const intervals = [
    'Off', '0.5s', '1s', '2s', '3s', '5s', '10s', '30s', '60s', //
  ];
  static const resolutions = [
    '1080p', '2.7K', '2.7K 4:3', '4K', '4K 4:3', '4K 8:7', //
    '5.3K', '5.3K 4:3', '5.3K 8:7',
  ];
  static const fps = ['24', '25', '30', '50', '60', '100', '120', '200', '240'];
  static const videoLenses = [
    'Linear', 'Linear + Horizon Leveling', 'Linear + Horizon Lock', //
    'Wide', 'Narrow', 'SuperView', 'HyperView',
  ];
  static const photoLenses = ['Linear', 'Wide'];
  static const bitrates = ['Standard', 'High', 'Max'];
  static const hypersmooth = [
    keepCamera, 'Off', 'Low', 'High', 'Boost', 'Auto boost', //
  ];
  static const bitDepth = [keepCamera, '8 bit', '10 bit'];

  static const iso = [
    keepCamera, '100', '200', '400', '800', '1600', '3200', '6400', //
  ];

  /// GoPro's own shutter steps (video). Which ones a camera offers depends on
  /// the frame rate: at 30 fps 1/30, 1/60, 1/120, 1/240, 1/480, 1/960 ...
  static const shutter = [
    keepCamera, 'Auto', '1/24', '1/25', '1/30', '1/48', '1/50', '1/60', //
    '1/96', '1/100', '1/120', '1/192', '1/200', '1/240', '1/384', '1/400',
    '1/480', '1/800', '1/960', '1/1600', '1/1920', '1/3200', '1/3840',
  ];
  static const whiteBalance = [
    keepCamera, 'Auto', '2300K', '2800K', '3200K', '4000K', '4500K', //
    '5000K', '5500K', '6000K', '6500K', 'Native',
  ];
  static const ev = [
    keepCamera, '-2', '-1.5', '-1', '-0.5', '0', '+0.5', '+1', '+1.5', '+2', //
  ];
  static const color = [keepCamera, 'Natural', 'Flat', 'Vibrant'];
  static const sharpness = [keepCamera, 'Low', 'Medium', 'High'];
}

/// Keys of the exposure targets that only a Labs QR can set.
const exposureKeys = [
  'Target ISO Min',
  'Target ISO',
  'Target Shutter',
  'Target White Balance',
  'Target EV',
  'Target Color',
  'Target Sharpness',
];

/// Shutter angle (degrees) for 1/[denominator] s at [fps], as Labs expects.
int shutterAngle(int denominator, int fps) =>
    (360 * fps / denominator).round().clamp(1, 360);

int? _iso(String? v) => int.tryParse(v ?? '');

/// GoPro Labs QR command for the exposure targets in [settings], plus the
/// camera clock set to [now]. Null when every target is "Camera preset".
String? labsRecipe(Map<String, String> settings, {required DateTime now}) {
  final video = settings['Mode'] == 'video';
  final fps = int.tryParse(settings['FPS'] ?? '') ?? 30;
  final b = StringBuffer();

  var isoMax = _iso(settings['Target ISO']);
  var isoMin = _iso(settings['Target ISO Min']);
  if (isoMax != null && isoMin != null && isoMin > isoMax) isoMin = isoMax;
  if (isoMax == null && isoMin != null) isoMax = 6400;
  if (isoMax != null) b.write('i${isoMax ~/ 100}M${(isoMin ?? 100) ~/ 100}');

  final shutter = settings['Target Shutter'];
  if (video && shutter != null && shutter != keepCamera) {
    final den = int.tryParse(shutter.replaceFirst('1/', ''));
    final angle = shutter == 'Auto' || den == null ? 0 : shutterAngle(den, fps);
    b.write('i${(isoMax ?? 6400) ~/ 100}S$angle');
  }

  final wb = settings['Target White Balance'];
  if (wb != null && wb != keepCamera) {
    b.write(
      wb == 'Auto'
          ? 'wA'
          : wb == 'Native'
          ? 'wN'
          : 'w${int.parse(wb.replaceAll('K', '')) ~/ 100}',
    );
  }

  final ev = settings['Target EV'];
  if (ev != null && ev != keepCamera) {
    final v = double.parse(ev);
    final text = v == v.roundToDouble()
        ? '${v.round()}'
        : '${v < 0 ? '-' : ''}.5';
    b.write('x$text');
  }

  final color = settings['Target Color'];
  if (color != null && color != keepCamera) {
    b.write({'Natural': 'cN', 'Flat': 'cF', 'Vibrant': 'cG'}[color]);
  }
  final sharp = settings['Target Sharpness'];
  if (sharp != null && sharp != keepCamera) {
    b.write({'Low': 'sL', 'Medium': 'sM', 'High': 'sH'}[sharp]);
  }

  if (b.isEmpty) return null;
  String two(int v) => v.toString().padLeft(2, '0');
  final clock =
      '${two(now.year % 100)}${two(now.month)}${two(now.day)}'
      '${two(now.hour)}${two(now.minute)}${two(now.second)}'
      '.${now.millisecond.toString().padLeft(3, '0')}';
  return '${video ? 'mV' : 'mP'}${b}oT$clock';
}

/// Short human summary of the exposure targets, e.g. "ISO 200 · 1/500 · 5500K".
String exposureSummary(Map<String, String> s) {
  final parts = <String>[];
  String? v(String k) {
    final x = s[k];
    return x == null || x == keepCamera ? null : x;
  }

  final min = v('Target ISO Min'), max = v('Target ISO');
  if (max != null || min != null) {
    parts.add(
      min == null || min == max ? 'ISO ${max ?? min}' : 'ISO $min–${max ?? ''}',
    );
  }
  for (final k in exposureKeys.skip(2)) {
    final x = v(k);
    if (x != null) parts.add(k == 'Target EV' ? 'EV $x' : x);
  }
  return parts.isEmpty ? 'Camera preset' : parts.join(' · ');
}

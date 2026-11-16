import 'package:flutter_test/flutter_test.dart';
import 'package:kosmos3d/providers/settings_provider.dart';
import 'package:kosmos3d/services/capture_options.dart';
import 'package:kosmos3d/services/gopro_service.dart';

void main() {
  final now = DateTime(2026, 11, 16, 12, 30, 5, 250);

  test('KIO preset is first and builds the expected Labs recipe', () {
    final kio = SettingsProvider.builtInPresets.first;
    expect(kio.name, 'KIO');
    expect(kio.settings['Resolution'], '5.3K');
    // ISO fixed 200, 1/500 s at 30 fps = 21.6 deg -> 22, 5500K, flat.
    expect(
      labsRecipe(kio.settings, now: now),
      'mVi2M2i2S22w55cFoT261116123005.250',
    );
  });

  test('every preset value exists in the option lists', () {
    for (final p in SettingsProvider.builtInPresets) {
      final s = p.settings;
      if (s['Mode'] == 'video') {
        expect(CaptureOptions.resolutions, contains(s['Resolution']));
        expect(CaptureOptions.fps, contains(s['FPS']));
        expect(CaptureOptions.videoLenses, contains(s['Lens']));
        expect(GoProSettings.resolutionCandidates, contains(s['Resolution']));
      } else {
        expect(CaptureOptions.photoFormats, contains(s['Photo Format']));
        expect(CaptureOptions.intervals, contains(s['Interval']));
      }
      for (final k in exposureKeys) {
        if (s[k] == null) continue;
        final list = {
          'Target ISO Min': CaptureOptions.iso,
          'Target ISO': CaptureOptions.iso,
          'Target Shutter': CaptureOptions.shutter,
          'Target White Balance': CaptureOptions.whiteBalance,
          'Target EV': CaptureOptions.ev,
          'Target Color': CaptureOptions.color,
          'Target Sharpness': CaptureOptions.sharpness,
        }[k]!;
        expect(list, contains(s[k]), reason: '${p.name} $k');
      }
    }
  });

  test('every option list entry maps to a camera value', () {
    for (final r in CaptureOptions.resolutions) {
      expect(GoProSettings.resolutionCandidates, contains(r));
    }
    for (final f in CaptureOptions.fps) {
      expect(GoProSettings.fps, contains(f));
    }
    expect(GoProSettings.fps['120'], 1); // was wrongly 0 (= 240 fps)
    for (final l in CaptureOptions.videoLenses) {
      expect(GoProSettings.videoLens, contains(l));
    }
  });

  test('EV, white balance and auto shutter encode as Labs expects', () {
    final r = labsRecipe({
      'Mode': 'video',
      'Target Shutter': 'Auto',
      'Target White Balance': 'Auto',
      'Target EV': '-0.5',
      'Target Sharpness': 'Low',
    }, now: now)!;
    expect(r, startsWith('mVi64S0wAx-.5sL'));
    expect(labsRecipe({'Mode': 'photo'}, now: now), isNull);
  });
}

import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:kosmos3d/services/exif_time.dart';
import 'package:kosmos3d/services/rig_sets.dart';

final t0 = DateTime.utc(2026, 10, 30, 17, 43, 16);

List<RigEvent> events(int n, {String run = 'r1'}) => [
  for (var k = 0; k < n; k++)
    RigEvent(t0.add(Duration(milliseconds: 1000 * k)), run: run),
];

List<RigPhoto> photos(
  String camera,
  DateTime first,
  int n, {
  Set<int> skip = const {},
}) => [
  for (var k = 0; k < n; k++)
    if (!skip.contains(k))
      RigPhoto(
        camera,
        '${camera}_$k.JPG',
        first.add(Duration(microseconds: 1001000 * k)),
      ),
];

/// Minimal JPEG: SOI, APP1 Exif with little-endian TIFF, ExifIFD tags.
Uint8List jpegWithExif(String dateTime, String subSec) {
  final tiff = BytesBuilder();
  void u16(int v) => tiff.add([v & 0xFF, v >> 8]);
  void u32(int v) =>
      tiff.add([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, v >> 24]);
  tiff.add('II'.codeUnits);
  u16(42);
  u32(8); // IFD0
  u16(1);
  u16(0x8769);
  u16(4);
  u32(1);
  u32(26); // ExifIFD offset
  u32(0);
  // ExifIFD at 26: two entries
  u16(2);
  u16(0x9003);
  u16(2);
  u32(20);
  u32(26 + 2 + 24 + 4); // string right after the IFD
  u16(0x9291);
  u16(2);
  u32(subSec.length + 1);
  tiff.add([...subSec.codeUnits, 0, 0, 0, 0].sublist(0, 4));
  u32(0);
  tiff.add([...dateTime.codeUnits, 0]);
  final body = [...'Exif'.codeUnits, 0, 0, ...tiff.toBytes()];
  final length = body.length + 2;
  return Uint8List.fromList([
    0xFF,
    0xD8,
    0xFF,
    0xE1,
    length >> 8,
    length & 0xFF,
    ...body,
    0xFF,
    0xD9,
  ]);
}

void main() {
  test('reads EXIF capture time with sub-seconds', () {
    final time = readExifCaptureTime(
      jpegWithExif('2026:10:30 17:43:17', '558'),
    );
    expect(time, DateTime.utc(2026, 10, 30, 17, 43, 17, 558));
    expect(readExifCaptureTime(Uint8List.fromList([1, 2, 3])), isNull);
  });

  test(
    'measured HERO13 run: clocks 1.2 s apart, one extra photo stays unmatched',
    () {
      // Values from the 1 s camera-timer test on 30 Oct 2026.
      final result = pairPhotosByTime(events(11), [
        ...photos('9400', DateTime.utc(2026, 10, 30, 17, 43, 16, 335), 12),
        ...photos('5432', DateTime.utc(2026, 10, 30, 17, 43, 17, 558), 11),
      ]);
      expect(result.sets, hasLength(11));
      expect(result.completeSets, 11);
      for (var k = 0; k < 11; k++) {
        expect(result.sets[k].photos, {
          '9400': '9400_$k.JPG',
          '5432': '5432_$k.JPG',
        });
      }
      expect(result.unmatched.map((p) => p.file), ['9400_11.JPG']);
      expect(
        result.clockOffsets[0]!['5432']! - result.clockOffsets[0]!['9400']!,
        closeTo(1.223, 0.01),
      );
    },
  );

  test('a missing photo leaves a gap instead of shifting later sets', () {
    final result = pairPhotosByTime(events(6), [
      ...photos('a', t0.add(const Duration(milliseconds: 80)), 6),
      ...photos('b', t0.add(const Duration(milliseconds: 600)), 6, skip: {2}),
    ]);
    expect(result.completeSets, 5);
    expect(result.sets[2].complete, isFalse);
    expect(result.sets[2].photos.containsKey('b'), isFalse);
    expect(result.sets[3].photos['b'], 'b_3.JPG');
    expect(result.sets[5].photos['b'], 'b_5.JPG');
    expect(result.unmatched, isEmpty);
  });

  test('separate runs pair separately; photos outside runs are counted', () {
    final second = DateTime.utc(2026, 10, 30, 18, 0, 0);
    final result = pairPhotosByTime(
      [
        ...events(3),
        for (var k = 0; k < 2; k++)
          RigEvent(second.add(Duration(seconds: 2 * k)), run: 'r2'),
      ],
      [
        ...photos('a', t0, 3),
        RigPhoto('a', 'r2_0.JPG', second.add(const Duration(milliseconds: 50))),
        RigPhoto(
          'a',
          'r2_1.JPG',
          second.add(const Duration(milliseconds: 2050)),
        ),
        RigPhoto('a', 'old.JPG', DateTime.utc(2026, 10, 29)),
      ],
    );
    expect(result.sets, hasLength(5));
    expect(result.sets.map((s) => s.run), [0, 0, 0, 1, 1]);
    expect(result.sets[4].photos['a'], 'r2_1.JPG');
    expect(result.outsideRuns, 1);
    expect(result.toJson()['complete_set_count'], 5);
  });
}

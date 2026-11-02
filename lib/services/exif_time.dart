import 'dart:io';
import 'dart:typed_data';

/// Reads DateTimeOriginal + SubSecTimeOriginal from a JPEG's EXIF block.
///
/// The result is the camera's wall-clock time returned as a UTC DateTime
/// with the same fields (EXIF carries no time zone). Compare it with other
/// wall-clock times only, see [wallClock].
DateTime? readExifCaptureTime(Uint8List bytes) {
  if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) return null;
  var pos = 2;
  while (pos + 4 <= bytes.length) {
    if (bytes[pos] != 0xFF) return null;
    final marker = bytes[pos + 1];
    if (marker == 0xD9 || marker == 0xDA) return null;
    final length = (bytes[pos + 2] << 8) | bytes[pos + 3];
    final start = pos + 4;
    if (marker == 0xE1 &&
        start + 6 <= bytes.length &&
        String.fromCharCodes(bytes.sublist(start, start + 4)) == 'Exif') {
      final end = (pos + 2 + length).clamp(0, bytes.length);
      return _parseTiff(ByteData.sublistView(bytes, start + 6, end));
    }
    pos += 2 + length;
  }
  return null;
}

/// Reads the capture time from the first 256 KB of a JPEG file.
Future<DateTime?> readExifCaptureTimeFromFile(String path) async {
  final file = File(path);
  final raf = await file.open();
  try {
    final length = await raf.length();
    return readExifCaptureTime(
      await raf.read(length < 262144 ? length : 262144),
    );
  } finally {
    await raf.close();
  }
}

/// A local time expressed with the same fields as a UTC DateTime, so it can be
/// compared with EXIF wall-clock times.
DateTime wallClock(DateTime time) {
  final t = time.toLocal();
  return DateTime.utc(
    t.year,
    t.month,
    t.day,
    t.hour,
    t.minute,
    t.second,
    t.millisecond,
    t.microsecond,
  );
}

DateTime? _parseTiff(ByteData tiff) {
  if (tiff.lengthInBytes < 8) return null;
  final order = tiff.getUint16(0) == 0x4949 ? Endian.little : Endian.big;
  int u16(int o) => tiff.getUint16(o, order);
  int u32(int o) => tiff.getUint32(o, order);

  Map<int, String> asciiTags(int ifd, Set<int> wanted, {int? pointerTag}) {
    final out = <int, String>{};
    if (ifd + 2 > tiff.lengthInBytes) return out;
    final count = u16(ifd);
    for (var i = 0; i < count; i++) {
      final entry = ifd + 2 + i * 12;
      if (entry + 12 > tiff.lengthInBytes) break;
      final tag = u16(entry);
      if (tag == pointerTag) {
        out[tag] = '${u32(entry + 8)}';
      } else if (wanted.contains(tag) && u16(entry + 2) == 2) {
        final n = u32(entry + 4);
        final offset = n <= 4 ? entry + 8 : u32(entry + 8);
        if (offset + n > tiff.lengthInBytes) continue;
        out[tag] = String.fromCharCodes(
          List.generate(n, (k) => tiff.getUint8(offset + k)),
        ).replaceAll('\u0000', '').trim();
      }
    }
    return out;
  }

  try {
    final ifd0 = asciiTags(u32(4), const {}, pointerTag: 0x8769);
    final exifIfd = int.tryParse(ifd0[0x8769] ?? '');
    if (exifIfd == null) return null;
    final tags = asciiTags(exifIfd, const {0x9003, 0x9291});
    final match = RegExp(
      r'^(\d{4}):(\d\d):(\d\d) (\d\d):(\d\d):(\d\d)$',
    ).firstMatch(tags[0x9003] ?? '');
    if (match == null) return null;
    final sub = tags[0x9291] ?? '';
    final fraction = RegExp(r'^\d+$').hasMatch(sub)
        ? int.parse(sub) / _pow10(sub.length)
        : 0.0;
    return DateTime.utc(
      int.parse(match[1]!),
      int.parse(match[2]!),
      int.parse(match[3]!),
      int.parse(match[4]!),
      int.parse(match[5]!),
      int.parse(match[6]!),
    ).add(Duration(microseconds: (fraction * 1e6).round()));
  } on RangeError {
    return null;
  }
}

int _pow10(int n) {
  var v = 1;
  for (var i = 0; i < n; i++) {
    v *= 10;
  }
  return v;
}

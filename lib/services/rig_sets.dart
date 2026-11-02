import 'dart:convert';
import 'dart:io';
import 'exif_time.dart';

/// One imported photo with its camera wall-clock capture time.
class RigPhoto {
  const RigPhoto(this.cameraId, this.file, this.time);
  final String cameraId, file;
  final DateTime time;
}

/// One shutter event from shutter_events.jsonl, on the phone wall clock.
class RigEvent {
  const RigEvent(this.time, {this.run, this.ackOffsets = const {}});
  final DateTime time;

  /// Same value for all events of one Start..Stop run; null in older logs.
  final String? run;

  /// Shutter ACK offset per camera from the event dispatch.
  final Map<String, Duration> ackOffsets;
}

class RigSet {
  RigSet(this.index, this.run, this.event, this.cameras);
  final int index, run;
  final DateTime event;
  final List<String> cameras;
  final Map<String, String> photos = {};
  final Map<String, double> residualSeconds = {};
  bool get complete => cameras.every(photos.containsKey);
}

class RigSetResult {
  RigSetResult(
    this.sets,
    this.unmatched,
    this.clockOffsets, {
    this.outsideRuns = 0,
  });
  final List<RigSet> sets;

  /// Photos taken during a run that fit no shutter event.
  final List<RigPhoto> unmatched;

  /// Imported photos taken outside every logged run (not part of any set).
  final int outsideRuns;

  /// Camera clock minus phone clock per run, in seconds.
  final Map<int, Map<String, double>> clockOffsets;
  int get completeSets => sets.where((s) => s.complete).length;

  Map<String, dynamic> toJson() => {
    'format': 'kosmos3d_rig_sets',
    'version': 1,
    'method': 'exif_capture_time',
    'note':
        'Each camera clock is aligned to the shutter log by its first photo '
        'of a run; photos are then matched to the nearest shutter event '
        'within half an interval.',
    'set_count': sets.length,
    'complete_set_count': completeSets,
    'photos_outside_runs': outsideRuns,
    'sets': [
      for (final s in sets)
        {
          'index': s.index,
          'run': s.run,
          'event_wall_clock': s.event.toIso8601String().replaceAll('Z', ''),
          'complete': s.complete,
          'photos': s.photos,
          'residual_s': s.residualSeconds,
        },
    ],
    'unmatched': [
      for (final p in unmatched)
        {
          'camera_id': p.cameraId,
          'file': p.file,
          'capture_wall_clock': p.time.toIso8601String().replaceAll('Z', ''),
        },
    ],
    'clock_offsets_s': {
      for (final e in clockOffsets.entries) '${e.key}': e.value,
    },
  };
}

/// Groups each run's photos into sets, one per shutter event.
///
/// All times are wall-clock values (see [wallClock]). Camera clocks are only
/// synchronised to the second, so each camera is aligned by its own first
/// photo of a run, then refined by the median residual of its matches.
RigSetResult pairPhotosByTime(
  List<RigEvent> events,
  List<RigPhoto> photos, {
  Duration margin = const Duration(milliseconds: 2500),
}) {
  final sorted = [...events]..sort((a, b) => a.time.compareTo(b.time));
  final runs = <List<RigEvent>>[];
  for (final e in sorted) {
    final last = runs.isEmpty ? null : runs.last.last;
    final sameRun =
        last != null &&
        (e.run != null || last.run != null
            ? e.run == last.run
            : e.time.difference(last.time) < const Duration(seconds: 10));
    if (sameRun) {
      runs.last.add(e);
    } else {
      runs.add([e]);
    }
  }
  final cameras = (photos.map((p) => p.cameraId).toSet().toList()..sort());
  final used = <RigPhoto>{}, inWindow = <RigPhoto>{};
  final sets = <RigSet>[];
  final offsets = <int, Map<String, double>>{};

  for (var r = 0; r < runs.length; r++) {
    final run = runs[r];
    final gaps = [
      for (var i = 1; i < run.length; i++)
        run[i].time.difference(run[i - 1].time).inMicroseconds,
    ]..sort();
    final interval = gaps.isEmpty
        ? const Duration(seconds: 1)
        : Duration(microseconds: gaps[gaps.length ~/ 2]);
    final tolerance = interval ~/ 2 > const Duration(seconds: 1)
        ? const Duration(seconds: 1)
        : interval ~/ 2;
    final runSets = List.generate(
      run.length,
      (k) => RigSet(sets.length + k, r, run[k].time, cameras),
    );
    final windowStart = run.first.time.subtract(margin);
    final windowEnd = run.last.time.add(interval).add(margin);
    inWindow.addAll(
      photos.where(
        (p) => !p.time.isBefore(windowStart) && p.time.isBefore(windowEnd),
      ),
    );
    for (final camera in cameras) {
      final own =
          photos
              .where(
                (p) =>
                    p.cameraId == camera &&
                    !used.contains(p) &&
                    !p.time.isBefore(windowStart) &&
                    p.time.isBefore(windowEnd),
              )
              .toList()
            ..sort((a, b) => a.time.compareTo(b.time));
      if (own.isEmpty) continue;
      Duration expected(int k) =>
          run[k].time.difference(run.first.time) +
          (run[k].ackOffsets[camera] ?? Duration.zero);
      // Camera clock - phone clock, anchored on the first photo of the run.
      var offset = own.first.time.difference(run.first.time) - expected(0);
      var assignment = <int, RigPhoto>{};
      for (var pass = 0; pass < 2; pass++) {
        assignment = {};
        final residual = <int, Duration>{};
        for (final p in own) {
          final t = p.time.difference(run.first.time) - offset;
          var best = -1;
          Duration? bestDiff;
          for (var k = 0; k < run.length; k++) {
            final d = (t - expected(k)).abs();
            if (d <= tolerance && (bestDiff == null || d < bestDiff)) {
              best = k;
              bestDiff = d;
            }
          }
          if (best < 0) continue;
          if (assignment[best] == null || bestDiff! < residual[best]!.abs()) {
            assignment[best] = p;
            residual[best] = t - expected(best);
          }
        }
        if (residual.isEmpty) break;
        final values = residual.values.map((d) => d.inMicroseconds).toList()
          ..sort();
        offset += Duration(microseconds: values[values.length ~/ 2]);
      }
      (offsets[r] ??= {})[camera] = offset.inMicroseconds / 1e6;
      for (final entry in assignment.entries) {
        final p = entry.value;
        used.add(p);
        final set = runSets[entry.key];
        set.photos[camera] = p.file;
        set.residualSeconds[camera] =
            ((p.time.difference(run.first.time) - offset - expected(entry.key))
                .inMicroseconds /
            1e6);
      }
    }
    sets.addAll(runSets);
  }
  final unmatched = inWindow.where((p) => !used.contains(p)).toList()
    ..sort((a, b) => a.time.compareTo(b.time));
  return RigSetResult(
    sets,
    unmatched,
    offsets,
    outsideRuns: photos.length - inWindow.length,
  );
}

/// Wall-clock windows of a project's capture runs (with margins for camera
/// clock offset and processing), used to import only this project's files.
Future<List<({DateTime start, DateTime end})>> projectRunWindows(
  String capturesDirectory,
) async {
  final log = File(
    '${Directory(capturesDirectory).parent.path}/shutter_events.jsonl',
  );
  if (!await log.exists()) return [];
  final events = <RigEvent>[];
  for (final line in await log.readAsLines()) {
    try {
      final json = jsonDecode(line) as Map<String, dynamic>;
      final time = DateTime.tryParse('${json['timestamp']}');
      if (time != null) {
        events.add(
          RigEvent(wallClock(time), run: json['run_started_utc'] as String?),
        );
      }
    } catch (_) {}
  }
  final result = pairPhotosByTime(events, const []);
  final windows = <({DateTime start, DateTime end})>[];
  for (var r = 0; r <= (result.sets.isEmpty ? -1 : result.sets.last.run); r++) {
    final times = result.sets.where((s) => s.run == r).map((s) => s.event);
    if (times.isEmpty) continue;
    windows.add((
      start: times.first.subtract(const Duration(seconds: 10)),
      end: times.last.add(const Duration(minutes: 2)),
    ));
  }
  return windows;
}

/// Camera file time (`mod`, camera wall clock) inside any of [windows].
bool inRunWindows(
  DateTime? cameraTime,
  List<({DateTime start, DateTime end})> windows,
) {
  if (cameraTime == null) return false;
  final wall = cameraTime.toUtc();
  return windows.any((w) => !wall.isBefore(w.start) && !wall.isAfter(w.end));
}

/// Reads a project's shutter log and imported photos, writes rig_sets.json
/// next to the log and returns the result (null without a log or photos).
Future<RigSetResult?> writeRigSets(String capturesDirectory) async {
  final captures = Directory(capturesDirectory);
  final log = File('${captures.parent.path}/shutter_events.jsonl');
  if (!await log.exists() || !await captures.exists()) return null;
  final events = <RigEvent>[];
  for (final line in await log.readAsLines()) {
    if (line.trim().isEmpty) continue;
    try {
      final json = jsonDecode(line) as Map<String, dynamic>;
      final time = DateTime.tryParse('${json['timestamp']}');
      if (time == null) continue;
      final acks = <String, Duration>{};
      for (final d in (json['camera_dispatch_timing'] as List? ?? [])) {
        final m = d as Map;
        final ack = m['ackOffsetUs'], sent = m['dispatchOffsetUs'];
        if (ack is int && sent is int) {
          acks['${m['cameraId']}'] = Duration(microseconds: ack - sent);
        }
      }
      events.add(
        RigEvent(
          wallClock(time),
          run: json['run_started_utc'] as String?,
          ackOffsets: acks,
        ),
      );
    } catch (_) {}
  }
  final photos = <RigPhoto>[];
  await for (final entity in captures.list()) {
    if (entity is! File || !entity.path.endsWith('.receipt.json')) continue;
    final path = entity.path.substring(
      0,
      entity.path.length - '.receipt.json'.length,
    );
    if (!path.toLowerCase().endsWith('.jpg') || !await File(path).exists()) {
      continue;
    }
    try {
      final info = jsonDecode(await entity.readAsString()) as Map;
      final time = await readExifCaptureTimeFromFile(path);
      if (time == null) continue;
      photos.add(
        RigPhoto(
          '${info['cameraId'] ?? info['serial']}',
          path.split(RegExp(r'[\\/]')).last,
          time,
        ),
      );
    } catch (_) {}
  }
  if (events.isEmpty || photos.isEmpty) return null;
  final result = pairPhotosByTime(events, photos);
  await File('${captures.parent.path}/rig_sets.json').writeAsString(
    const JsonEncoder.withIndent('  ').convert(result.toJson()),
    flush: true,
  );
  return result;
}

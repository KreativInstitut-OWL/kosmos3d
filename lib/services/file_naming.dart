/// File naming for imported camera files (the copy in the gallery / DCIM
/// folder that users take to their computer). The app's own copy keeps the
/// camera identity name, which import de-duplication and erase safety use.
library;

class NamingVariable {
  const NamingVariable(this.key, this.label, this.example);
  final String key;
  final String label;
  final String example;
  String get token => '{$key}';
}

const namingVariables = [
  NamingVariable('project', 'Project name', 'Campus'),
  NamingVariable('camera', 'Camera name (as renamed in the app)', 'Front-Left'),
  NamingVariable('serial', 'Camera serial, last 4 digits', '2114'),
  NamingVariable('date', 'Recording date', '2026-11-16'),
  NamingVariable('time', 'Recording time', '154210'),
  NamingVariable('original', 'Original GoPro name', 'GX012800'),
  NamingVariable('clip', 'GoPro clip number', '2800'),
  NamingVariable('chapter', 'Video chapter (01, 02 ...)', '01'),
  NamingVariable('index', 'Running number in this import', '0001'),
  NamingVariable('type', 'video or photo', 'video'),
];

const defaultNamingTemplate = '{project}_{camera}_{date}_{original}';

/// Values for one file.
class NamingValues {
  NamingValues({
    required this.project,
    required this.camera,
    required this.serial,
    required this.original,
    required this.recorded,
    required this.index,
  });
  final String project, camera, serial, original;
  final DateTime recorded;
  final int index;

  /// Example values used for the live preview.
  static NamingValues example() => NamingValues(
    project: 'Campus',
    camera: 'Front-Left',
    serial: 'C3531325642114',
    original: 'GX012800.MP4',
    recorded: DateTime(2026, 11, 16, 15, 42, 10),
    index: 1,
  );
}

String _two(int v) => v.toString().padLeft(2, '0');

/// Keeps letters, digits, dash and underscore; everything else becomes "-".
String _safe(String s) => s
    .trim()
    .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '-')
    .replaceAll(RegExp(r'-{2,}'), '-')
    .replaceAll(RegExp(r'^-|-$'), '');

/// Whether names from [template] can never collide: needs {original},
/// {index}, or {clip} together with {chapter}.
bool namingIsUnique(String template) =>
    template.contains('{original}') ||
    template.contains('{index}') ||
    (template.contains('{clip}') && template.contains('{chapter}'));

/// Final file name (with the original extension). A template that is not
/// [namingIsUnique] gets "_{original}" appended.
String applyNamingTemplate(String template, NamingValues v) {
  final dot = v.original.lastIndexOf('.');
  final base = dot > 0 ? v.original.substring(0, dot) : v.original;
  final ext = dot > 0 ? v.original.substring(dot) : '';
  // GoPro: GX01 2800 -> chapter 01, clip 2800 (photos: GOPR2800 / GP012800).
  final m = RegExp(r'^G[A-Z](\d{2})(\d{4})$').firstMatch(base);
  final video = ext.toLowerCase() == '.mp4';
  final r = v.recorded;
  var t = template.trim().isEmpty ? defaultNamingTemplate : template;
  if (!namingIsUnique(t)) t = '${t}_{original}';
  final values = <String, String>{
    'project': _safe(v.project),
    'camera': _safe(v.camera),
    'serial': v.serial.length > 4
        ? v.serial.substring(v.serial.length - 4)
        : v.serial,
    'date': '${r.year}-${_two(r.month)}-${_two(r.day)}',
    'time': '${_two(r.hour)}${_two(r.minute)}${_two(r.second)}',
    'original': base,
    'clip': m?.group(2) ?? base,
    'chapter': m?.group(1) ?? '01',
    'index': v.index.toString().padLeft(4, '0'),
    'type': video ? 'video' : 'photo',
  };
  var name = t;
  values.forEach((k, value) => name = name.replaceAll('{$k}', value));
  name = name
      .replaceAll(RegExp(r'\{[^}]*\}'), '')
      .replaceAll(RegExp(r'[^A-Za-z0-9_.-]+'), '-')
      .replaceAll(RegExp(r'([_-]){2,}'), r'$1')
      .replaceAll(RegExp(r'^[_.-]+|[_.-]+$'), '');
  return '${name.isEmpty ? base : name}$ext';
}

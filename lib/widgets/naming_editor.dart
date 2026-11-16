import 'package:flutter/material.dart';

import '../l10n/app_text.dart';
import '../services/file_naming.dart';

/// Edit the file naming template: switch variables on/off (appended in the
/// order switched on), or type the template freely. Live preview below.
Future<String?> showNamingEditor(BuildContext context, String template) =>
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _NamingEditor(initial: template),
    );

class _NamingEditor extends StatefulWidget {
  const _NamingEditor({required this.initial});
  final String initial;

  @override
  State<_NamingEditor> createState() => _NamingEditorState();
}

class _NamingEditorState extends State<_NamingEditor> {
  late final _ctrl = TextEditingController(text: widget.initial);
  String _separator = '_';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle(NamingVariable v, bool on) {
    var t = _ctrl.text;
    if (on) {
      t = t.isEmpty ? v.token : '$t$_separator${v.token}';
    } else {
      t = t
          .replaceAll(RegExp('[_.-]?${RegExp.escape(v.token)}'), '')
          .replaceAll(RegExp(r'^[_.-]+'), '');
    }
    setState(() => _ctrl.text = t);
  }

  @override
  Widget build(BuildContext context) {
    final t = _ctrl.text;
    final preview = applyNamingTemplate(t, NamingValues.example());
    final photo = applyNamingTemplate(
      t,
      NamingValues(
        project: 'Campus',
        camera: 'Front-Left',
        serial: 'C3531325642114',
        original: 'GOPR2801.JPG',
        recorded: DateTime(2026, 11, 16, 15, 43, 2),
        index: 2,
      ),
    );
    final primary = Theme.of(context).primaryColor;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppText(
              'File naming',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            AppText(
              'For files copied to Photos / Gallery (DCIM/KOSMOS3D). Switch variables on or off, or type the template. Any other text you type is kept as written.',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).hintColor,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ctrl,
              style: const TextStyle(fontFamily: 'monospace'),
              decoration: InputDecoration(
                labelText: 'Template',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: 'Reset to default',
                  icon: const Icon(Icons.restart_alt),
                  onPressed: () =>
                      setState(() => _ctrl.text = defaultNamingTemplate),
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const AppText('Preview', style: TextStyle(fontSize: 11)),
                  SelectableText(
                    preview,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SelectableText(
                    photo,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const AppText('Separator when adding'),
                const Spacer(),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: '_', label: Text('_')),
                    ButtonSegment(value: '-', label: Text('-')),
                  ],
                  selected: {_separator},
                  onSelectionChanged: (v) =>
                      setState(() => _separator = v.first),
                ),
              ],
            ),
            for (final v in namingVariables)
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: AppText(v.label),
                subtitle: Text(
                  '${v.token}  →  ${v.example}',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                ),
                value: t.contains(v.token),
                onChanged: (on) => _toggle(v, on),
              ),
            if (!namingIsUnique(t))
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: AppText(
                  'Without {original}, {index} or {clip} + {chapter}, the original name is added so files never overwrite each other.',
                  style: TextStyle(color: Colors.orange, fontSize: 12),
                ),
              ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const AppText('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => Navigator.pop(context, _ctrl.text.trim()),
                  child: const AppText('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

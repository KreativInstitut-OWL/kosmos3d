import 'dart:io';
import '../l10n/app_text.dart';
import 'package:flutter/material.dart';
import '../services/rig_sets.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import '../services/gopro_service.dart';
import '../screens/media_library_screen.dart';
import '../services/system_settings_service.dart';

class GoProMediaTransferDialog extends StatefulWidget {
  final String? projectCapturesPath;
  const GoProMediaTransferDialog({super.key, this.projectCapturesPath});
  static Future<void> show(
    BuildContext context, {
    String? projectCapturesPath,
  }) => showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    builder: (_) =>
        GoProMediaTransferDialog(projectCapturesPath: projectCapturesPath),
  );
  @override
  State<GoProMediaTransferDialog> createState() =>
      _GoProMediaTransferDialogState();
}

class _GoProMediaTransferDialogState extends State<GoProMediaTransferDialog> {
  late final GoProService _service = context.read<GoProService>();

  @override
  void initState() {
    super.initState();
    _service; // resolve while the context is active
    _loadWindows();
  }

  @override
  void dispose() {
    // Browsing or importing may have joined a camera Wi-Fi, which routes all
    // app traffic to the camera. Give the phone its normal network back.
    if (!_service.isSyncingMedia) {
      SystemSettingsService.releaseCameraWifi().catchError((_) {});
    }
    super.dispose();
  }

  bool _loading = false, _transferring = false, _gallery = true;
  double _progress = 0;
  String _status =
      'Join a camera’s Wi-Fi, then browse its files. Bluetooth controls the rig; Wi-Fi transfers originals.';
  List<GoProMediaItem> _items = [];
  String? _target;

  /// Where imported files can be found, in words a user can act on.
  List<String> _whereFiles(int galleryFailures) => [
    'In the app: Transfers → View files.',
    if (_gallery)
      Platform.isIOS
          ? 'Copies in Photos, sorted by the date the camera took them.'
          : 'Copies in the gallery album KOSMOS3D, sorted by the date the camera took them.',
    if (galleryFailures > 0)
      'Gallery exports needing attention: $galleryFailures.',
    'Camera SD cards are unchanged.',
  ];
  final Set<int> _selected = {};
  Future<void> _credentials(String id) async {
    final service = context.read<GoProService>();
    try {
      final credentials = await service.readWifiCredentials(id);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const AppText('Camera Wi-Fi'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(
                'SSID: ${credentials.ssid}\nPassword: ${credentials.password}',
              ),
              const SizedBox(height: 12),
              const AppText(
                'The app reads the camera password over Bluetooth. Removing Wi-Fi security is unnecessary.',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: credentials.password)),
              child: const AppText('Copy password'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const AppText('Done'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _status = '$e');
    }
  }

  /// Groups a project's imported photos into rig sets by capture time.
  Future<String?> _matchRigSets() async {
    final captures = widget.projectCapturesPath;
    if (captures == null) return null;
    try {
      final result = await writeRigSets(captures);
      if (result == null) return null;
      return 'Matched by capture time: ${result.completeSets} of '
          '${result.sets.length} photo sets complete'
          '${result.unmatched.isEmpty ? '' : ', ${result.unmatched.length} photos without a set'}.';
    } catch (e) {
      return 'Photo sets not matched: $e';
    }
  }

  /// Capture windows of the project this dialog imports into (empty for
  /// loose imports or projects without a shutter log).
  List<({DateTime start, DateTime end})> _windows = [];

  Future<void> _loadWindows() async {
    final captures = widget.projectCapturesPath;
    if (captures == null) return;
    final windows = await projectRunWindows(captures);
    if (mounted) setState(() => _windows = windows);
  }

  Future<void> _importAll({bool everything = false}) async {
    if (_loading || _transferring) return;
    final service = context.read<GoProService>();
    setState(() {
      _transferring = true;
      _progress = 0;
    });
    try {
      final root = await getApplicationDocumentsDirectory();
      final target =
          widget.projectCapturesPath ?? '${root.path}/kosmos3d_downloads';
      final windows = everything
          ? const <({DateTime start, DateTime end})>[]
          : _windows;
      final report = await service.importAllConnectedCameras(
        target,
        saveToGallery: _gallery,
        include: windows.isEmpty
            ? null
            : (item) => inRunWindows(item.modifiedTime, windows),
        onStatus: (message) {
          if (mounted) {
            setState(() {
              _status = message;
              _progress = service.syncProgress;
            });
          }
        },
      );
      final sets = await _matchRigSets();
      if (mounted) {
        setState(() {
          _progress = report.complete ? 1 : _progress;
          _target = report.destination;
          _status = [
            '${report.complete ? 'Import complete' : 'Import needs attention'}: ${report.imported} local files.',
            for (final c in report.cameras)
              '${c.cameraName}: ${c.imported}/${c.found}${c.error == null ? '' : ' — ${c.error}'}',
            ?sets,
            ..._whereFiles(service.galleryFailures.length),
          ].join('\n');
        });
      }
    } catch (e) {
      if (mounted) setState(() => _status = '$e');
    } finally {
      if (mounted) setState(() => _transferring = false);
    }
  }

  Future<void> _fetch() async {
    if (_loading || _transferring) return;
    final service = context.read<GoProService>();
    setState(() {
      _loading = true;
      _status = 'Finding cameras and reading SD cards…';
    });
    try {
      if (service.capture.active || service.capture.busy) {
        throw StateError('Stop capture before importing.');
      }
      final items = await service.fetchAllMediaItemsFromAllCameras();
      if (!mounted) return;
      setState(() {
        _items = items;
        _selected.clear();
        _selected.addAll([
          for (var i = 0; i < items.length; i++)
            if (_windows.isEmpty ||
                inRunWindows(items[i].modifiedTime, _windows))
              i,
        ]);
        _status = items.isEmpty
            ? 'No readable media found. Connect a camera by Bluetooth and join its Wi-Fi.'
            : '${items.length} files available. Select the originals to import.';
      });
    } catch (e) {
      if (mounted) setState(() => _status = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _transfer() async {
    if (_transferring || _selected.isEmpty) return;
    final service = context.read<GoProService>();
    final items = _selected.map((i) => _items[i]).toList();
    setState(() {
      _transferring = true;
      _progress = 0;
    });
    try {
      final documents = await getApplicationDocumentsDirectory();
      final target =
          widget.projectCapturesPath ?? '${documents.path}/kosmos3d_downloads';
      final count = await service.transferMediaItems(
        items,
        targetCapturesDirectory: target,
        saveToNativeGallery: _gallery,
        onProgress: (current, total, fraction, status) {
          if (mounted) {
            setState(() {
              _progress = (current - 1 + fraction) / total;
              _status = status;
            });
          }
        },
      );
      final sets = await _matchRigSets();
      if (mounted) {
        setState(() {
          _progress = count == items.length ? 1 : _progress;
          _target = target;
          _status = [
            '$count of ${items.length} originals available locally. '
                '${count == items.length ? 'Import complete.' : 'Retry to fetch missing files.'}',
            ?sets,
            ..._whereFiles(service.galleryFailures.length),
          ].join('\n');
        });
      }
    } catch (e) {
      if (mounted) setState(() => _status = 'Import stopped: $e');
    } finally {
      if (mounted) setState(() => _transferring = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _loading || _transferring;
    final cameras = context
        .watch<GoProService>()
        .devices
        .where((c) => c.isConnected)
        .toList();
    return PopScope(
      canPop: !busy,
      child: SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.83,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: AppText(
                        'Import originals',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close import',
                      onPressed: busy ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 110),
                  child: SingleChildScrollView(
                    child: AppText(
                      _status,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                if (_transferring)
                  TextButton(
                    onPressed: context.read<GoProService>().cancelImport,
                    child: const AppText('Cancel import'),
                  ),
                if (!busy && _target != null)
                  TextButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => MediaLibraryScreen(
                          folder: Directory(_target!),
                          title: 'Imported files',
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const AppText('View files'),
                  ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: busy || cameras.isEmpty ? null : _importAll,
                  icon: const Icon(Icons.download_for_offline),
                  label: AppText(
                    _windows.isNotEmpty
                        ? 'Import this project\'s files'
                        : cameras.length == 1
                        ? 'Import all files from 1 camera'
                        : 'Import all files from ${cameras.length} cameras',
                  ),
                ),
                if (_windows.isNotEmpty)
                  TextButton(
                    onPressed: busy || cameras.isEmpty
                        ? null
                        : () => _importAll(everything: true),
                    child: const AppText('Import everything on the cards'),
                  ),
                const AppText(
                  'Cameras transfer one at a time. Approve each Wi-Fi connection when asked.',
                ),
                if (cameras.isNotEmpty)
                  Wrap(
                    children: cameras
                        .map(
                          (camera) => TextButton.icon(
                            onPressed: busy
                                ? null
                                : () => _credentials(camera.id),
                            icon: const Icon(Icons.key),
                            label: AppText('${camera.name} Wi-Fi'),
                          ),
                        )
                        .toList(),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: busy
                            ? null
                            : () async {
                                try {
                                  await SystemSettingsService.openWifiSettings();
                                } catch (e) {
                                  if (mounted) setState(() => _status = '$e');
                                }
                              },
                        icon: const Icon(Icons.wifi),
                        label: const AppText('Wi-Fi settings'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: busy ? null : _fetch,
                        child: const AppText('Browse files'),
                      ),
                    ),
                  ],
                ),
                if (busy)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: LinearProgressIndicator(
                      value: _loading ? null : _progress,
                    ),
                  ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const AppText('Also copy to Photos / Gallery'),
                  subtitle: const AppText(
                    'Originals always remain in the app.',
                  ),
                  value: _gallery,
                  onChanged: busy ? null : (v) => setState(() => _gallery = v!),
                ),
                if (_items.isNotEmpty)
                  Row(
                    children: [
                      AppText('${_selected.length} selected'),
                      const Spacer(),
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => setState(() {
                                if (_selected.length == _items.length) {
                                  _selected.clear();
                                } else {
                                  _selected.addAll(
                                    List.generate(_items.length, (i) => i),
                                  );
                                }
                              }),
                        child: AppText(
                          _selected.length == _items.length
                              ? 'Deselect all'
                              : 'Select all',
                        ),
                      ),
                    ],
                  ),
                Expanded(
                  child: _items.isEmpty
                      ? const Center(
                          child: Icon(Icons.sd_storage_outlined, size: 48),
                        )
                      : ListView.builder(
                          itemCount: _items.length,
                          itemBuilder: (_, i) {
                            final item = _items[i];
                            return CheckboxListTile(
                              value: _selected.contains(i),
                              onChanged: busy
                                  ? null
                                  : (v) => setState(() {
                                      if (v!) {
                                        _selected.add(i);
                                      } else {
                                        _selected.remove(i);
                                      }
                                    }),
                              title: AppText(
                                item.filename,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: AppText(
                                '${item.cameraName} · ${item.formattedSize}',
                              ),
                              secondary: Icon(
                                item.isVideo
                                    ? Icons.videocam_outlined
                                    : Icons.image_outlined,
                              ),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: busy || _selected.isEmpty ? null : _transfer,
                    icon: const Icon(Icons.download),
                    label: AppText('Import ${_selected.length} files'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

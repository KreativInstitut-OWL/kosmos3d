import '../l10n/app_text.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/scan_project.dart';
import '../providers/settings_provider.dart';
import '../services/project_service.dart';
import '../services/upload_service.dart';
import '../services/cloud_storage_service.dart';
import '../widgets/storage_upload_dialog.dart';
import 'settings.dart' show CloudStorageDialog;
import '../services/system_settings_service.dart';
import '../widgets/glass_card.dart';
import '../widgets/gopro_media_transfer_dialog.dart';
import 'gallery_screen.dart';
import 'media_library_screen.dart';

class TransferHubScreen extends StatefulWidget {
  const TransferHubScreen({super.key});
  @override
  State<TransferHubScreen> createState() => _TransferHubScreenState();
}

class _TransferHubScreenState extends State<TransferHubScreen> {
  String? _projectId;
  bool _localBusy = false;
  String _localStatus = '';
  List<File> _files = [];
  int _bytes = 0;
  int _refreshGeneration = 0;
  String? _storageTarget;

  @override
  void initState() {
    super.initState();
    _refresh();
    _loadStorageTarget();
  }

  Future<void> _loadStorageTarget() async {
    final c = await context.read<CloudStorageService>().getDisplayCredentials();
    final endpoint = c['endpoint'] ?? '';
    final host =
        Uri.tryParse(
          endpoint.contains('://') ? endpoint : 'https://$endpoint',
        )?.host ??
        '';
    if (!mounted) return;
    setState(
      () => _storageTarget = (c['bucketName'] ?? '').isEmpty
          ? null
          : '${c['bucketName']}/${c['prefix']} · $host',
    );
  }

  /// A receiver address that can work: 127.0.0.1 is the phone itself.
  static bool _isReceiverSet(String url) {
    final host = Uri.tryParse(url)?.host ?? '';
    return host.isNotEmpty && !['127.0.0.1', 'localhost', '::1'].contains(host);
  }

  void _snack(String text) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: AppText(text)));

  Future<void> _configureStorage() async {
    await showDialog<void>(
      context: context,
      builder: (_) => const CloudStorageDialog(),
    );
    await _loadStorageTarget();
  }

  Future<void> _uploadToStorage(ScanProject? project) async {
    if (project != null) {
      await showStorageUploadDialog(
        context,
        projectId: project.id,
        projectName: project.name,
      );
      return;
    }
    await context.read<CloudStorageService>().uploadFiles(
      _files.where((f) => !f.path.endsWith('.receipt.json')).toList(),
      projectName: 'imports',
    );
  }

  Widget _storageDestination(
    CloudStorageService cloud,
    ScanProject? selected,
    bool busy,
  ) => _destination(
    CupertinoIcons.cloud_upload,
    'Send to storage server',
    cloud.isConfigured
        ? (_storageTarget ?? 'Storage server ready')
        : 'Any S3-compatible storage: Backblaze B2, AWS S3, Wasabi, Cloudflare R2, MinIO. Set it up once.',
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!cloud.isConfigured)
          FilledButton.icon(
            onPressed: busy ? null : _configureStorage,
            icon: const Icon(Icons.tune),
            label: const AppText('Set up storage server'),
          )
        else
          Row(
            children: [
              TextButton(
                onPressed: busy ? null : _configureStorage,
                child: const AppText('Change'),
              ),
              TextButton(
                onPressed: busy
                    ? null
                    : () async {
                        final ok = await cloud.testConnection();
                        if (mounted) {
                          _snack(
                            ok
                                ? 'Storage server reachable'
                                : cloud.lastError ?? 'Connection failed',
                          );
                        }
                      },
                child: const AppText('Test'),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: busy || _files.isEmpty
                    ? null
                    : () => _uploadToStorage(selected),
                icon: const Icon(Icons.cloud_upload_outlined),
                label: const AppText('Upload'),
              ),
            ],
          ),
        if (selected == null && cloud.statusMessage.isNotEmpty) ...[
          const SizedBox(height: 12),
          _statusCard(
            cloud.statusMessage,
            cloud.progress,
            cloud.isUploading ? null : cloud.lastError,
            cloud.isUploading ? cloud.cancelUpload : null,
          ),
        ],
      ],
    ),
  );

  Widget _statusCard(
    String status,
    double progress,
    String? error,
    VoidCallback? onCancel,
  ) => GlassCard(
    padding: const EdgeInsets.all(18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppText(status),
        const SizedBox(height: 12),
        LinearProgressIndicator(
          value: progress,
          minHeight: 6,
          borderRadius: BorderRadius.circular(4),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: AppText(
              error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (onCancel != null)
          TextButton(
            onPressed: onCancel,
            child: const AppText('Cancel transfer'),
          ),
      ],
    ),
  );

  Future<Directory> _folder() async {
    final root = await getApplicationDocumentsDirectory();
    return Directory(
      _projectId == null
          ? '${root.path}/kosmos3d_downloads'
          : '${root.path}/kosmos3d_projects/$_projectId',
    );
  }

  Future<void> _refresh() async {
    final generation = ++_refreshGeneration;
    final directory = await _folder();
    final files = <File>[];
    var bytes = 0;
    if (await directory.exists()) {
      await for (final file in directory.list(
        recursive: true,
        followLinks: false,
      )) {
        if (file is File && !file.path.endsWith('.part')) {
          files.add(file);
          bytes += await file.length();
        }
      }
    }
    if (mounted && generation == _refreshGeneration) {
      setState(() {
        _files = files;
        _bytes = bytes;
      });
    }
  }

  Future<void> _import() async {
    final directory = await _folder();
    final path = _projectId == null
        ? directory.path
        : '${directory.path}/captures';
    if (!mounted) return;
    await GoProMediaTransferDialog.show(context, projectCapturesPath: path);
    await _refresh();
  }

  Future<void> _export() async {
    if (_localBusy) return;
    setState(() {
      _localBusy = true;
      _localStatus = 'Copying originals…';
    });
    var saved = 0;
    try {
      final folder = await _folder();
      for (final file in List<File>.of(_files)) {
        final relative = file.path
            .substring(folder.path.length + 1)
            .replaceAll('\\', '/');
        await SystemSettingsService.saveToDownloads(
          file.path,
          relativePath: '${_projectId ?? 'Imports'}/$relative',
        );
        saved++;
        if (mounted) {
          setState(() => _localStatus = 'Saved $saved/${_files.length} files');
        }
      }
      if (mounted) {
        setState(
          () => _localStatus = Platform.isIOS
              ? '$saved files saved in Files > On My iPhone > KOSMOS 3D > Exports'
              : '$saved originals saved in Downloads/KOSMOS3D',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _localStatus = '$saved saved; export stopped: $e');
      }
    } finally {
      if (mounted) setState(() => _localBusy = false);
    }
  }

  Future<void> _configure() async {
    final settings = context.read<SettingsProvider>();
    final prefs = await SharedPreferences.getInstance();
    final url = TextEditingController(text: settings.serverUrl);
    final token = TextEditingController(text: settings.serverApiKey);
    var transport = prefs.getString('server_transport') ?? 'multipart';
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: const AppText('Server destination'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: transport,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(
                      value: 'kosmos',
                      child: AppText('KOSMOS transfer server'),
                    ),
                    DropdownMenuItem(
                      value: 'multipart',
                      child: AppText('Existing upload API'),
                    ),
                  ],
                  onChanged: (v) => update(() => transport = v!),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: url,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Server address',
                    hintText: 'https://files.example.org',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: token,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(labelText: 'Access token'),
                ),
                const SizedBox(height: 16),
                AppText(
                  transport == 'kosmos'
                      ? 'Uses the included KOSMOS server. Every file is verified with SHA-256. Retry skips files already verified on the server.'
                      : 'Uses your existing POST /upload endpoint with a multipart file field. Username/password can be configured in Settings.',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const AppText('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final parsed = Uri.tryParse(url.text.trim());
                if (parsed == null ||
                    !['http', 'https'].contains(parsed.scheme) ||
                    parsed.host.isEmpty ||
                    parsed.hasQuery ||
                    parsed.hasFragment ||
                    parsed.userInfo.isNotEmpty ||
                    ['127.0.0.1', 'localhost', '::1'].contains(parsed.host)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: AppText(
                        'Enter the HTTP(S) address of your computer, e.g. http://192.168.1.20:8787. 127.0.0.1 is the phone itself.',
                      ),
                    ),
                  );
                  return;
                }
                settings.setServerUrl(url.text.trim());
                settings.setServerApiKey(token.text.trim());
                await prefs.setString('server_url', url.text.trim());
                await prefs.setString('server_api_key', token.text.trim());
                await prefs.setString('server_transport', transport);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const AppText('Save'),
            ),
          ],
        ),
      ),
    );
    // Controllers stay alive through the dialog's closing transition.
    await Future<void>.delayed(const Duration(milliseconds: 350));
    url.dispose();
    token.dispose();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final projects = context.watch<ProjectService>().projects;
    final upload = context.watch<UploadService>();
    final cloud = context.watch<CloudStorageService>();
    final settings = context.watch<SettingsProvider>();
    ScanProject? project;
    for (final candidate in projects) {
      if (candidate.id == _projectId) project = candidate;
    }
    final selected = project;
    final busy = _localBusy || upload.isUploading || cloud.isUploading;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Scaffold(
      appBar: AppBar(
        title: const AppText('Transfers'),
        actions: [
          IconButton(
            tooltip: 'Refresh files',
            onPressed: busy ? null : _refresh,
            icon: const Icon(CupertinoIcons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(22, 12, 22, 130),
        children: [
          AppText(
            'From rig to anywhere.',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 10),
          AppText(
            'Import originals over Wi-Fi. Keep them on your phone or send a complete project to your server.',
            style: TextStyle(color: muted),
          ),
          const SizedBox(height: 24),
          DropdownButtonFormField<String>(
            initialValue: _projectId ?? '',
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Source / import destination',
            ),
            items: [
              const DropdownMenuItem(
                value: '',
                child: AppText('Loose imports'),
              ),
              ...projects.map(
                (p) => DropdownMenuItem(
                  value: p.id,
                  child: AppText(p.name, overflow: TextOverflow.ellipsis),
                ),
              ),
            ],
            onChanged: busy
                ? null
                : (v) {
                    setState(() => _projectId = v == '' ? null : v);
                    _refresh();
                  },
          ),
          const SizedBox(height: 18),
          GlassCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(CupertinoIcons.folder),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AppText(
                        '{n} photos and videos'.replaceAll(
                          '{n}',
                          '${_files.where((f) => isMediaFile(f.path)).length}',
                        ),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    AppText(_size(_bytes), style: TextStyle(color: muted)),
                  ],
                ),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: () async {
                    final folder = await _folder();
                    if (!context.mounted) return;
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => MediaLibraryScreen(
                          folder: folder,
                          title: selected?.name ?? 'Loose imports',
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const AppText('View files'),
                ),
                const SizedBox(height: 8),
                AppText(
                  selected == null
                      ? 'Original camera media, stored on this phone.'
                      : 'Originals, project information and recorded sensor data.',
                  style: TextStyle(color: muted),
                ),
                if (selected != null)
                  TextButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => GalleryScreen(project: selected),
                      ),
                    ),
                    child: const AppText('Open project media'),
                  ),
              ],
            ),
          ),
          _destination(
            CupertinoIcons.arrow_down_to_line,
            'Import from GoPros',
            'Select cameras and files over Wi-Fi.',
            FilledButton.icon(
              onPressed: busy ? null : _import,
              icon: const Icon(Icons.download),
              label: const AppText('Browse camera files'),
            ),
          ),
          _destination(
            CupertinoIcons.device_phone_portrait,
            'Save to phone',
            Platform.isIOS
                ? 'Export originals and metadata to Files > KOSMOS 3D > Exports. Copy to iCloud or another location to keep them after uninstalling.'
                : 'Export all originals and metadata to Downloads/KOSMOS3D.',
            OutlinedButton.icon(
              onPressed: busy || _files.isEmpty ? null : _export,
              icon: const Icon(Icons.save_alt),
              label: const AppText('Save all files'),
            ),
          ),
          _storageDestination(cloud, selected, busy),
          if (_isReceiverSet(settings.serverUrl))
            _destination(
              CupertinoIcons.desktopcomputer,
              'KOSMOS receiver (your computer)',
              settings.serverUrl,
              Row(
                children: [
                  TextButton(
                    onPressed: busy ? null : _configure,
                    child: const AppText('Change'),
                  ),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () async {
                            final ok = await upload.testConnection();
                            if (context.mounted) {
                              _snack(
                                ok
                                    ? 'Server is reachable'
                                    : upload.lastError ?? 'Connection failed',
                              );
                            }
                          },
                    child: const AppText('Test'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: busy || _files.isEmpty
                        ? null
                        : () {
                            if (selected != null) {
                              upload.uploadProject(selected.id, selected.name);
                            } else {
                              upload.uploadFiles(
                                List<File>.of(_files),
                                projectName: 'Imports',
                              );
                            }
                          },
                    child: const AppText('Send all'),
                  ),
                ],
              ),
            )
          else
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: busy ? null : _configure,
                icon: const Icon(CupertinoIcons.desktopcomputer, size: 18),
                label: const AppText(
                  'Send to the KOSMOS receiver on a computer',
                ),
              ),
            ),
          if (upload.statusMessage.isNotEmpty)
            _statusCard(
              upload.statusMessage,
              upload.progress,
              upload.lastError,
              upload.isUploading ? upload.cancel : null,
            ),
          if (_localStatus.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: AppText(_localStatus),
            ),
          AppText(
            'Keep the app open during transfers. An interrupted upload continues on the next try: files already on the server are skipped.',
            style: TextStyle(color: muted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _destination(
    IconData icon,
    String title,
    String detail,
    Widget action,
  ) => GlassCard(
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(icon, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: AppText(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        AppText(
          detail,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 18),
        action,
      ],
    ),
  );
  String _size(int bytes) => bytes >= 1073741824
      ? '${(bytes / 1073741824).toStringAsFixed(1)} GB'
      : '${(bytes / 1048576).toStringAsFixed(1)} MB';
}

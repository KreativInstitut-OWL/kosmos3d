import '../l10n/app_text.dart';
import '../widgets/storage_upload_dialog.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../models/scan_project.dart';
import '../services/upload_service.dart';
import '../services/cloud_storage_service.dart';
import '../services/trajectory_service.dart';
import '../providers/settings_provider.dart';
import '../widgets/gopro_media_transfer_dialog.dart';
import 'settings.dart' show CloudStorageDialog;

/// Gallery screen for viewing captured images and managing project media.
class GalleryScreen extends StatefulWidget {
  final ScanProject project;

  const GalleryScreen({super.key, required this.project});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  List<File> _imageFiles = [];
  bool _isLoading = true;
  bool _selectMode = false;
  final Set<int> _selectedIndices = {};

  @override
  void initState() {
    super.initState();
    _loadImages();
  }

  Future<void> _loadImages() async {
    setState(() => _isLoading = true);
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final capturesDir = Directory(
        '${appDir.path}/kosmos3d_projects/${widget.project.id}/captures',
      );

      if (await capturesDir.exists()) {
        final files = capturesDir.listSync().whereType<File>().where((f) {
          final ext = f.path.split('.').last.toLowerCase();
          return ['jpg', 'jpeg', 'png', 'mp4', 'gpr'].contains(ext);
        }).toList();
        files.sort(
          (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
        );
        _imageFiles = files;
      }
    } catch (e) {
      debugPrint("Error loading images: $e");
    }
    setState(() => _isLoading = false);
  }

  Future<void> _deleteSelected() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: AppText(
          'Delete Selected?',
          style: TextStyle(color: context.ink()),
        ),
        content: AppText(
          'Delete ${_selectedIndices.length} file(s)?',
          style: TextStyle(color: context.ink(0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const AppText('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const AppText(
              'Delete',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      for (final idx in _selectedIndices.toList().reversed) {
        await _imageFiles[idx].delete();
      }
      _selectedIndices.clear();
      _selectMode = false;
      await _loadImages();
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<SettingsProvider>();
    final uploadService = context.watch<UploadService>();
    final cloud = context.watch<CloudStorageService>();
    final primaryColor = Theme.of(context).primaryColor;

    return Scaffold(
      appBar: AppBar(
        title: AppText(widget.project.name),
        actions: [
          if (_selectMode) ...[
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.redAccent),
              onPressed: _selectedIndices.isEmpty ? null : _deleteSelected,
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => setState(() {
                _selectMode = false;
                _selectedIndices.clear();
              }),
            ),
          ] else ...[
            // Import from GoPro over Wi-Fi
            IconButton(
              icon: const Icon(Icons.download_for_offline),
              tooltip: 'Import from GoPros',
              onPressed: () async {
                final appDir = await getApplicationDocumentsDirectory();
                final path =
                    '${appDir.path}/kosmos3d_projects/${widget.project.id}/captures';
                if (context.mounted) {
                  await GoProMediaTransferDialog.show(
                    context,
                    projectCapturesPath: path,
                  );
                  _loadImages();
                }
              },
            ),
            // Upload to storage server (opens setup when not configured)
            IconButton(
              icon: const Icon(Icons.cloud_upload),
              tooltip: 'Upload to storage server',
              onPressed: cloud.isUploading
                  ? null
                  : () async {
                      if (!cloud.isConfigured) {
                        await showDialog<void>(
                          context: context,
                          builder: (_) => const CloudStorageDialog(),
                        );
                        if (!context.mounted || !cloud.isConfigured) return;
                      }
                      await showStorageUploadDialog(
                        context,
                        projectId: widget.project.id,
                        projectName: widget.project.name,
                      );
                    },
            ),
            // KOSMOS receiver on a computer, only when one is set up
            if (context.watch<SettingsProvider>().serverUrl.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.computer),
                tooltip: 'Send to KOSMOS receiver',
                onPressed: uploadService.isUploading
                    ? null
                    : () => _showUploadDialog(context, uploadService),
              ),
            // Export trajectory
            IconButton(
              icon: const Icon(Icons.route),
              tooltip: 'Export trajectory',
              onPressed: () => _showTrajectoryExport(context),
            ),
            IconButton(icon: const Icon(Icons.refresh), onPressed: _loadImages),
          ],
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _imageFiles.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.photo_library, size: 64, color: context.ink(0.15)),
                  const SizedBox(height: 16),
                  AppText(
                    'No captures yet',
                    style: TextStyle(color: context.ink(0.4), fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  AppText(
                    'Images downloaded from GoPros will appear here',
                    style: TextStyle(color: context.ink(0.25), fontSize: 13),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                // Stats bar
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  color: context.ink(0.03),
                  child: Row(
                    children: [
                      Icon(Icons.photo, size: 16, color: primaryColor),
                      const SizedBox(width: 6),
                      AppText(
                        '${_imageFiles.length} files',
                        style: TextStyle(color: context.ink(0.7), fontSize: 13),
                      ),
                      const Spacer(),
                      AppText(
                        _formatTotalSize(),
                        style: TextStyle(
                          color: context.ink(0.54),
                          fontSize: 12,
                        ),
                      ),
                      if (_selectMode) ...[
                        const SizedBox(width: 12),
                        AppText(
                          '${_selectedIndices.length} selected',
                          style: TextStyle(
                            color: primaryColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                // Upload progress bar
                if (uploadService.isUploading || cloud.isUploading) ...[
                  LinearProgressIndicator(
                    value: uploadService.isUploading
                        ? uploadService.progress
                        : cloud.progress,
                    color: primaryColor,
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: AppText(
                      uploadService.isUploading
                          ? uploadService.statusMessage
                          : cloud.statusMessage,
                      style: TextStyle(color: context.ink(0.54), fontSize: 11),
                    ),
                  ),
                ],
                // Grid
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.all(4),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 4,
                          mainAxisSpacing: 4,
                        ),
                    itemCount: _imageFiles.length,
                    itemBuilder: (context, index) {
                      final file = _imageFiles[index];
                      final isSelected = _selectedIndices.contains(index);
                      final ext = file.path.split('.').last.toLowerCase();
                      final isImage = ['jpg', 'jpeg', 'png'].contains(ext);

                      return GestureDetector(
                        onTap: () {
                          if (_selectMode) {
                            setState(() {
                              if (isSelected) {
                                _selectedIndices.remove(index);
                              } else {
                                _selectedIndices.add(index);
                              }
                            });
                          } else if (isImage) {
                            _showImageViewer(context, file, index);
                          }
                        },
                        onLongPress: () {
                          setState(() {
                            _selectMode = true;
                            _selectedIndices.add(index);
                          });
                        },
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                color: context.ink(0.05),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: isImage
                                    ? Image.file(
                                        file,
                                        fit: BoxFit.cover,
                                        cacheWidth: 200,
                                      )
                                    : Center(
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              ext == 'mp4'
                                                  ? Icons.videocam
                                                  : Icons.insert_drive_file,
                                              color: context.ink(0.38),
                                              size: 28,
                                            ),
                                            const SizedBox(height: 4),
                                            AppText(
                                              '.$ext',
                                              style: TextStyle(
                                                color: context.ink(0.38),
                                                fontSize: 10,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                              ),
                            ),
                            // File name label
                            Positioned(
                              bottom: 0,
                              left: 0,
                              right: 0,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.6),
                                  borderRadius: const BorderRadius.only(
                                    bottomLeft: Radius.circular(8),
                                    bottomRight: Radius.circular(8),
                                  ),
                                ),
                                child: AppText(
                                  file.path.split('/').last,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 9,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            // Selection indicator
                            if (_selectMode)
                              Positioned(
                                top: 6,
                                right: 6,
                                child: Container(
                                  width: 22,
                                  height: 22,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isSelected
                                        ? primaryColor
                                        : Colors.white.withValues(alpha: 0.3),
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 1.5,
                                    ),
                                  ),
                                  child: isSelected
                                      ? const Icon(
                                          Icons.check,
                                          size: 14,
                                          color: Colors.black,
                                        )
                                      : null,
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  void _showImageViewer(BuildContext context, File file, int index) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            title: AppText(
              file.path.split('/').last,
              style: const TextStyle(fontSize: 14),
            ),
          ),
          body: InteractiveViewer(
            minScale: 0.5,
            maxScale: 4.0,
            child: Center(child: Image.file(file)),
          ),
        ),
      ),
    );
  }

  void _showUploadDialog(BuildContext context, UploadService uploadService) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: AppText(
          'Upload Project',
          style: TextStyle(color: context.ink()),
        ),
        content: AppText(
          'Upload ${_imageFiles.length} files from "${widget.project.name}" to your configured server?',
          style: TextStyle(color: context.ink(0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const AppText('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final messenger = ScaffoldMessenger.of(context);
              messenger.showSnackBar(
                const SnackBar(content: AppText('Sending to KOSMOS receiver…')),
              );
              final ok = await uploadService.uploadProject(
                widget.project.id,
                widget.project.name,
              );
              messenger.showSnackBar(
                SnackBar(
                  content: AppText(
                    ok
                        ? uploadService.statusMessage
                        : uploadService.lastError ?? 'Upload failed',
                  ),
                ),
              );
            },
            child: const AppText('Upload'),
          ),
        ],
      ),
    );
  }

  void _showTrajectoryExport(BuildContext context) {
    final trajectoryService = context.read<TrajectoryService>();
    final points = trajectoryService.points;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: AppText(
          'Export Trajectory',
          style: TextStyle(color: context.ink()),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppText(
              '${points.length} trajectory points recorded.',
              style: TextStyle(color: context.ink(0.7)),
            ),
            const SizedBox(height: 12),
            if (points.isEmpty)
              const AppText(
                'No trajectory data available. Record some captures first.',
                style: TextStyle(color: Colors.orange),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const AppText('Cancel'),
          ),
          if (points.isNotEmpty) ...[
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await _saveTrajectory(trajectoryService, 'csv');
              },
              child: const AppText('Export CSV'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await _saveTrajectory(trajectoryService, 'json');
              },
              child: const AppText('Export JSON'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _saveTrajectory(TrajectoryService service, String format) async {
    final appDir = await getApplicationDocumentsDirectory();
    final projectDir = '${appDir.path}/kosmos3d_projects/${widget.project.id}';
    final content = format == 'csv'
        ? service.exportAsCsv()
        : service.exportAsJson();
    final file = File('$projectDir/trajectory.$format');
    await file.writeAsString(content);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AppText('Trajectory exported to trajectory.$format'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  String _formatTotalSize() {
    int totalBytes = 0;
    for (final f in _imageFiles) {
      try {
        totalBytes += f.lengthSync();
      } catch (_) {}
    }
    if (totalBytes < 1024 * 1024) {
      return '${(totalBytes / 1024).toStringAsFixed(1)} KB';
    }
    if (totalBytes < 1024 * 1024 * 1024) {
      return '${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(totalBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

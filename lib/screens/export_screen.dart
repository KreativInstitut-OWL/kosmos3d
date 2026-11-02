import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/storage_upload_dialog.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/scan_project.dart';
import '../services/export_service.dart';
import '../services/trajectory_service.dart';
import '../services/rig_geometry_service.dart';
import '../services/gopro_service.dart';
import '../services/cloud_storage_service.dart';
import '../providers/settings_provider.dart';
import '../widgets/camera_connection_status.dart';
import '../widgets/gopro_media_transfer_dialog.dart';
import 'package:path_provider/path_provider.dart';

/// Screen that exports and displays all COLMAP / Gaussian Splatting files.
/// Users can share/download individual files or the entire bundle.
class ExportScreen extends StatefulWidget {
  final ScanProject project;
  const ExportScreen({super.key, required this.project});

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  bool _isExporting = false;
  String? _exportPath;
  List<FileExportItem> _files = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _runExport();
  }

  Future<void> _runExport() async {
    setState(() {
      _isExporting = true;
      _error = null;
    });

    try {
      final exportService = context.read<ExportService>();
      final trajectory = context.read<TrajectoryService>();
      final rigService = context.read<RigGeometryService>();
      final goPro = context.read<GoProService>();

      final connectedIds = goPro.devices
          .where((d) => d.isConnected)
          .map((d) => d.id)
          .toList();

      // If no cameras connected, use rig cameras
      final cameraIds = connectedIds.isNotEmpty
          ? connectedIds
          : rigService.cameras.map((c) => c.cameraId).toList();

      final path = await exportService.exportSession(
        projectName: widget.project.name,
        projectId: widget.project.id,
        trajectory: trajectory.points,
        connectedCameraIds: cameraIds.isNotEmpty ? cameraIds : ['camera_1'],
        rigService: rigService,
        cameraSettings: widget.project.cameraSettings,
        captureMode: widget.project.captureMode,
      );

      final files = await exportService.getExportedFiles(path);

      setState(() {
        _exportPath = path;
        _files = files;
        _isExporting = false;
      });

      // Auto-upload to the storage server if configured and enabled
      if (mounted) {
        final settings = context.read<SettingsProvider>();
        final cloud = context.read<CloudStorageService>();
        if (settings.autoUpload && cloud.isConfigured) {
          await showStorageUploadDialog(
            context,
            projectId: widget.project.id,
            projectName: widget.project.name,
            confirm: false,
          );
        }
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isExporting = false;
      });
    }
  }

  /// Imports this project's originals over the camera Wi-Fi.
  Future<void> _showDownloadDialog() async {
    final root = await getApplicationDocumentsDirectory();
    if (!mounted) return;
    await GoProMediaTransferDialog.show(
      context,
      projectCapturesPath:
          '${root.path}/kosmos3d_projects/${widget.project.id}/captures',
    );
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Export & Download'),
        actions: [
          const CameraConnectionStatus(),
          if (_exportPath != null)
            IconButton(
              icon: const Icon(Icons.share),
              tooltip: 'Share all files',
              onPressed: _shareAll,
            ),
        ],
      ),
      body: _isExporting
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: primaryColor),
                  const SizedBox(height: 16),
                  Text(
                    'Generating export files...',
                    style: TextStyle(color: context.ink(0.7)),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'COLMAP • transforms.json • trajectory.csv',
                    style: TextStyle(color: context.ink(0.38), fontSize: 12),
                  ),
                ],
              ),
            )
          : _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 48,
                    color: Colors.redAccent,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Export failed',
                    style: TextStyle(color: context.ink(0.7)),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _runExport,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ─── Summary Card ───
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        primaryColor.withValues(alpha: 0.15),
                        Colors.transparent,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: primaryColor.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.check_circle,
                            color: primaryColor,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Export Complete',
                            style: TextStyle(
                              color: primaryColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Project: ${widget.project.name}',
                        style: TextStyle(color: context.ink(), fontSize: 14),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_files.length} files generated',
                        style: TextStyle(color: context.ink(0.6), fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          _compatChip('COLMAP'),
                          _compatChip('3DGS'),
                          _compatChip('NeRF'),
                          _compatChip('Nerfstudio'),
                          _compatChip('Metashape'),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ─── Auto-Download (WiFi) ───
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: context.ink(0.04),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.orangeAccent.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.wifi,
                            color: Colors.orangeAccent,
                            size: 20,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Import from cameras',
                            style: TextStyle(
                              color: Colors.orangeAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Copies this project\'s originals from every camera over its Wi-Fi. Passwords are read over Bluetooth.',
                        style: TextStyle(
                          color: context.ink(0.7),
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orangeAccent,
                            foregroundColor: Colors.black,
                          ),
                          onPressed: _showDownloadDialog,
                          icon: const Icon(Icons.download),
                          label: const Text('Import originals'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // ─── File List ───
                Text(
                  'Exported Data',
                  style: TextStyle(
                    color: context.ink(0.6),
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                ..._files.map(
                  (file) =>
                      _FileCard(file: file, onShare: () => _shareFile(file)),
                ),
              ],
            ),
    );
  }

  Widget _compatChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: context.ink(0.06),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(color: context.ink(0.6), fontSize: 10),
      ),
    );
  }

  Future<void> _shareFile(FileExportItem file) async {
    try {
      final box = context.findRenderObject() as RenderBox?;
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Kosmos3D Export: ${file.name}',
        sharePositionOrigin: box!.localToGlobal(Offset.zero) & box.size,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Share failed: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _shareAll() async {
    if (_files.isEmpty) return;
    try {
      final xFiles = _files.map((f) => XFile(f.path)).toList();
      final box = context.findRenderObject() as RenderBox?;
      await Share.shareXFiles(
        xFiles,
        subject: 'Kosmos3D Export: ${widget.project.name}',
        sharePositionOrigin: box!.localToGlobal(Offset.zero) & box.size,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Share failed: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }
}

class _FileCard extends StatelessWidget {
  final FileExportItem file;
  final VoidCallback onShare;

  const _FileCard({required this.file, required this.onShare});

  IconData _getIcon() {
    if (file.name.endsWith('.json')) return Icons.data_object;
    if (file.name.endsWith('.csv')) return Icons.table_chart;
    if (file.name.endsWith('.txt')) return Icons.description;
    return Icons.insert_drive_file;
  }

  Color _getColor() {
    if (file.name.contains('transforms')) return const Color(0xFF00FF41);
    if (file.name.contains('colmap') || file.name.contains('sparse')) {
      return Colors.blueAccent;
    }
    if (file.name.contains('trajectory')) return Colors.orangeAccent;
    if (file.name.contains('rig')) return Colors.purpleAccent;
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    final color = _getColor();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: context.ink(0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Icon(_getIcon(), color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  file.name,
                  style: TextStyle(
                    color: context.ink(),
                    fontSize: 13,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  file.sizeFormatted,
                  style: TextStyle(color: context.ink(0.4), fontSize: 11),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.share,
              color: color.withValues(alpha: 0.7),
              size: 20,
            ),
            onPressed: onShare,
          ),
        ],
      ),
    );
  }
}

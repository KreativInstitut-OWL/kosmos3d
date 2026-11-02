import '../l10n/app_text.dart';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../models/scan_project.dart';
import '../providers/settings_provider.dart';
import '../services/project_service.dart';
import '../services/gopro_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import 'settings.dart';
import 'project_flow.dart';
import 'capture_session.dart';
import 'gallery_screen.dart';
import 'point_cloud_preview.dart';
import 'qr_config_screen.dart';
import 'device_manager.dart';
import 'transfer_hub.dart';

class MainMenuScreen extends StatefulWidget {
  const MainMenuScreen({super.key});
  @override
  State<MainMenuScreen> createState() => _MainMenuScreenState();
}

class _MainMenuScreenState extends State<MainMenuScreen> {
  int _tab = 0;
  void _open(Widget page) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final labels = ['Projects', 'Cameras', 'Transfers', 'Settings'];
    final icons = [
      CupertinoIcons.square_stack_3d_up,
      CupertinoIcons.camera,
      CupertinoIcons.arrow_up_arrow_down,
      CupertinoIcons.slider_horizontal_3,
    ];
    return Scaffold(
      extendBody: true,
      // Tab screens run under the floating bar; lift their snackbars above it
      // (they were hidden behind the bar).
      body: Theme(
        data: Theme.of(context).copyWith(
          snackBarTheme: Theme.of(context).snackBarTheme.copyWith(
            insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 112),
          ),
        ),
        child: switch (_tab) {
          1 => const DeviceManagerScreen(),
          2 => const TransferHubScreen(),
          3 => const SettingsScreen(),
          _ => _projects(),
        },
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(34),
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: MediaQuery.highContrastOf(context) ? 0 : 18,
              sigmaY: MediaQuery.highContrastOf(context) ? 0 : 18,
            ),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: scheme.surface.withValues(alpha: 0.96),
                borderRadius: BorderRadius.circular(34),
                border: Border.all(
                  color: scheme.onSurface.withValues(alpha: 0.12),
                ),
              ),
              child: Row(
                children: List.generate(
                  4,
                  (i) => Expanded(
                    child: Semantics(
                      selected: _tab == i,
                      button: true,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(28),
                        onTap: () => setState(() => _tab = i),
                        child: AnimatedContainer(
                          duration: MediaQuery.disableAnimationsOf(context)
                              ? Duration.zero
                              : const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: _tab == i
                                ? scheme.primary.withValues(alpha: 0.13)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(28),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                icons[i],
                                size: 23,
                                color: _tab == i
                                    ? scheme.primary
                                    : scheme.onSurfaceVariant,
                              ),
                              const SizedBox(height: 5),
                              AppText(
                                labels[i],
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: _tab == i
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: _tab == i
                                      ? scheme.primary
                                      : scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _projects() {
    final settings = context.watch<SettingsProvider>();
    final projects = context.watch<ProjectService>();
    final goPro = context.watch<GoProService>();
    final connected = goPro.devices.where((d) => d.isConnected).length;
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: projects.loadProjects,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 120),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.asset(
                    'assets/icon/app_icon.png',
                    width: 44,
                    height: 44,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppText(
                        'KOSMOS 3D',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                        ),
                      ),
                      AppText(
                        'KreativInstitut.OWL',
                        style: TextStyle(fontSize: 11, color: muted),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'QR configuration',
                  onPressed: () => _open(const QrConfigScreen()),
                  icon: const Icon(CupertinoIcons.qrcode),
                ),
              ],
            ),
            const SizedBox(height: 32),
            AppText(
              'Your capture\nstudio.',
              style: theme.textTheme.headlineLarge?.copyWith(height: 1.08),
            ),
            const SizedBox(height: 12),
            AppText(
              'One rig. Every perspective.',
              style: TextStyle(fontSize: 16, color: muted),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: AppTheme.neonGreen,
                borderRadius: BorderRadius.circular(28),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        CupertinoIcons.viewfinder,
                        color: AppTheme.textDark,
                        size: 24,
                      ),
                      const Spacer(),
                      AppText(
                        connected == 0
                            ? 'RIG OFFLINE'
                            : '$connected CAMERAS CONNECTED',
                        style: const TextStyle(
                          color: AppTheme.textDark,
                          fontSize: 10,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const AppText(
                    'Make space\nfor a new dimension.',
                    style: TextStyle(
                      color: AppTheme.textDark,
                      fontSize: 25,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.8,
                      height: 1.13,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.textDark,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () => _open(const ProjectFlowScreen()),
                          icon: const Icon(Icons.add, size: 20),
                          label: AppText(settings.translate('new_project')),
                        ),
                      ),
                      const SizedBox(width: 10),
                      IconButton.filled(
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black.withValues(alpha: 0.09),
                          foregroundColor: AppTheme.textDark,
                        ),
                        tooltip: 'Manage cameras',
                        onPressed: () => setState(() => _tab = 1),
                        icon: const Icon(CupertinoIcons.camera),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: AppText(
                    settings.translate('project_overview'),
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                AppText(
                  '${projects.projects.length}',
                  style: TextStyle(color: muted),
                ),
                IconButton(
                  tooltip: 'Trajectory preview',
                  onPressed: () => _open(const PointCloudPreviewScreen()),
                  icon: const Icon(CupertinoIcons.cube),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (projects.isLoading)
              const Center(child: CircularProgressIndicator())
            else if (projects.projects.isEmpty)
              GlassCard(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppText(
                      settings.translate('no_projects'),
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    AppText(
                      settings.translate('create_first_project'),
                      style: TextStyle(color: muted),
                    ),
                  ],
                ),
              )
            else
              ...projects.projects.map(
                (p) => _buildProjectCard(context, p, settings, projects),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildProjectCard(
    BuildContext context,
    ScanProject project,
    SettingsProvider settings,
    ProjectService projectService,
  ) {
    final timeAgo = _formatTimeAgo(project.lastModifiedAt, settings);
    final modeIcon = project.captureMode == 'video'
        ? Icons.videocam
        : Icons.photo_camera;

    return GlassCard(
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Theme.of(context).primaryColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            modeIcon,
            color: Theme.of(context).primaryColor,
            size: 28,
          ),
        ),
        title: AppText(
          project.name,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Theme.of(context).textTheme.bodyLarge?.color,
            fontSize: 16,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: AppText(
            '${project.captureCount} shutter events · $timeAgo',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
        ),
        trailing: PopupMenuButton<String>(
          icon: Icon(
            Icons.more_vert,
            color: Theme.of(
              context,
            ).textTheme.bodyMedium?.color?.withValues(alpha: 0.5),
          ),
          onSelected: (value) async {
            if (value == 'open') {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CaptureSessionScreen(project: project),
                ),
              );
            } else if (value == 'gallery') {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => GalleryScreen(project: project),
                ),
              );
            } else if (value == '3d') {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const PointCloudPreviewScreen(),
                ),
              );
            } else if (value == 'delete') {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: AppText(
                    'Delete Project?',
                    style: TextStyle(color: context.ink()),
                  ),
                  content: AppText(
                    'This will permanently delete "${project.name}" and all its capture data.',
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
                await projectService.deleteProject(project.id);
              }
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'open', child: AppText('Open Session')),
            const PopupMenuItem(value: 'gallery', child: AppText('Gallery')),
            const PopupMenuItem(value: '3d', child: AppText('3D Preview')),
            const PopupMenuItem(
              value: 'delete',
              child: AppText(
                'Delete',
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
          ],
        ),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CaptureSessionScreen(project: project),
          ),
        ),
      ),
    );
  }

  String _formatTimeAgo(DateTime date, SettingsProvider settings) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${date.day}.${date.month}.${date.year}';
  }
}

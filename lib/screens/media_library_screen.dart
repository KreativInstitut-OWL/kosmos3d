import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../l10n/app_text.dart';

/// Photo/video extensions shown as media; receipts, logs and partial
/// downloads stay out of the grid.
const mediaExtensions = {
  'jpg',
  'jpeg',
  'gpr',
  'dng',
  'png',
  'mp4',
  'mov',
  'lrv',
  '360',
};

bool isMediaFile(String path) {
  final name = path.split(RegExp(r'[\\/]')).last.toLowerCase();
  if (name.endsWith('.part') || name.endsWith('.receipt.json')) return false;
  return mediaExtensions.contains(name.split('.').last);
}

bool isVideoFile(String path) {
  final ext = path.split('.').last.toLowerCase();
  return ext == 'mp4' || ext == 'mov' || ext == 'lrv' || ext == '360';
}

/// Every imported photo and video in a folder, newest import first.
class MediaLibraryScreen extends StatefulWidget {
  const MediaLibraryScreen({
    super.key,
    required this.folder,
    required this.title,
  });
  final Directory folder;
  final String title;

  @override
  State<MediaLibraryScreen> createState() => _MediaLibraryScreenState();
}

class _MediaLibraryScreenState extends State<MediaLibraryScreen> {
  List<File> _media = [];
  int _partial = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final media = <File>[];
    var partial = 0;
    if (await widget.folder.exists()) {
      await for (final e in widget.folder.list(
        recursive: true,
        followLinks: false,
      )) {
        if (e is! File) continue;
        if (e.path.endsWith('.part')) partial++;
        if (isMediaFile(e.path)) media.add(e);
      }
    }
    final modified = {for (final f in media) f.path: await f.lastModified()};
    media.sort((a, b) => modified[b.path]!.compareTo(modified[a.path]!));
    if (mounted) {
      setState(() {
        _media = media;
        _partial = partial;
        _loading = false;
      });
    }
  }

  String _name(File f) => f.path.split(RegExp(r'[\\/]')).last;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.65);
    return Scaffold(
      appBar: AppBar(
        title: AppText(widget.title),
        actions: [
          IconButton(
            tooltip: 'Share all files',
            icon: const Icon(Icons.ios_share),
            onPressed: _media.isEmpty
                ? null
                : () => Share.shareXFiles([
                    for (final f in _media) XFile(f.path),
                  ]),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AppText(
                            '{n} photos and videos'.replaceAll(
                              '{n}',
                              '${_media.length}',
                            ),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          AppText(
                            Platform.isIOS
                                ? 'Copies in Photos are sorted by the date the camera took them.'
                                : 'Copies in the phone gallery are in the album KOSMOS3D, sorted by the date the camera took them.',
                            style: TextStyle(color: muted, fontSize: 12),
                          ),
                          if (_partial > 0) ...[
                            const SizedBox(height: 6),
                            AppText(
                              'Interrupted downloads: {n}. They continue on the next import.'
                                  .replaceAll('{n}', '$_partial'),
                              style: const TextStyle(
                                color: Colors.orangeAccent,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (_media.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: AppText(
                          'No imported files yet',
                          style: TextStyle(color: muted),
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      sliver: SliverGrid.builder(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              mainAxisSpacing: 6,
                              crossAxisSpacing: 6,
                            ),
                        itemCount: _media.length,
                        itemBuilder: (context, i) => _tile(_media[i]),
                      ),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
              ),
            ),
    );
  }

  Widget _tile(File file) {
    final video = isVideoFile(file.path);
    final raw =
        file.path.toLowerCase().endsWith('.gpr') ||
        file.path.toLowerCase().endsWith('.dng');
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => _MediaViewer(file: file, name: _name(file)),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (video || raw)
              Container(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Icon(video ? Icons.movie : Icons.raw_on, size: 36),
              )
            else
              Image.file(
                file,
                fit: BoxFit.cover,
                cacheWidth: 300,
                errorBuilder: (_, _, _) => const Icon(Icons.broken_image),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                color: Colors.black54,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text(
                  _name(file).split('_').last,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MediaViewer extends StatelessWidget {
  const _MediaViewer({required this.file, required this.name});
  final File file;
  final String name;

  @override
  Widget build(BuildContext context) {
    final video = isVideoFile(file.path);
    final bytes = file.lengthSync();
    final size = bytes > 1 << 30
        ? '${(bytes / (1 << 30)).toStringAsFixed(2)} GB'
        : '${(bytes / (1 << 20)).toStringAsFixed(1)} MB';
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(name, style: const TextStyle(fontSize: 13)),
        actions: [
          IconButton(
            tooltip: 'Share',
            icon: const Icon(Icons.ios_share),
            onPressed: () => Share.shareXFiles([XFile(file.path)]),
          ),
        ],
      ),
      body: Center(
        child: video
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.movie, color: Colors.white54, size: 72),
                  const SizedBox(height: 12),
                  Text(size, style: const TextStyle(color: Colors.white70)),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => Share.shareXFiles([XFile(file.path)]),
                    icon: const Icon(Icons.open_in_new),
                    label: const AppText('Open with…'),
                  ),
                ],
              )
            : InteractiveViewer(maxScale: 8, child: Image.file(file)),
      ),
    );
  }
}

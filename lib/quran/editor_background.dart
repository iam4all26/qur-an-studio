import 'dart:io';

import 'package:flutter/material.dart';
import 'package:kainuwa_encoder/kainuwa_encoder.dart';

import '../models.dart';
import '../theme.dart';
import 'background_manager.dart';
import 'backgrounds_screen.dart';
import 'templates.dart';

/// The Background tool of the editor. The user first chooses where the background comes from
/// (template pictures, downloaded video clips, own video, own photo), then whether it is for
/// this slide or every slide. Returns 'changed', 'dark' (open the darken sheet) or null.
Future<String?> editBackground(BuildContext context, Lesson lesson, Scene? scene) async {
  final source = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: KColors.surface,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Background', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            ),
          ),
          _tile(c, Icons.image_outlined, 'Template pictures', 'Pictures of the templates', 'template'),
          _tile(c, Icons.movie_filter_outlined, 'Video backgrounds', 'Moving sky, clouds, water and more', 'clips'),
          _tile(c, Icons.video_library_outlined, 'My video', 'Use a video from your phone', 'video'),
          _tile(c, Icons.photo_outlined, 'My photo', 'Use a photo from your phone', 'photo'),
          _tile(c, Icons.contrast, 'Darken background', 'Makes the text readable on any background', 'dark',
              dot: lesson.scenes.any((sc) => sc.layers.any((l) => l.id.startsWith('overlay_') && l.opacity > 0.001))),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (source == null || !context.mounted) return null;
  if (source == 'dark') return 'dark';

  // What was chosen: a picture (type and value) or a video (path and length).
  String? picType;
  String? picValue;
  String? videoPath;
  var videoMs = 0;

  try {
    if (source == 'template') {
      final list = await QTemplates.load();
      if (!context.mounted) return null;
      final asset = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        backgroundColor: KColors.surface,
        builder: (c) => _TemplateGrid(templates: list, w: lesson.aspectW, h: lesson.aspectH),
      );
      if (asset == null) return null;
      picType = 'asset';
      picValue = asset;
    } else if (source == 'clips') {
      final bm = BackgroundManager.instance;
      await bm.load();
      final ready = bm.clips.where((c) => bm.isReady(c.id)).toList();
      final previews = <String, String>{};
      for (final c in ready) {
        previews[c.id] = await bm.previewPath(c.id);
      }
      if (!context.mounted) return null;
      final clip = await showModalBottomSheet<BgClip>(
        context: context,
        isScrollControlled: true,
        backgroundColor: KColors.surface,
        builder: (c) => _ClipList(clips: ready, previews: previews),
      );
      if (clip == null) return null;
      videoPath = await bm.clipPath(clip.id);
      videoMs = clip.durationMs;
      if (!await File(videoPath).exists() || videoMs < 1000) {
        _say(context, 'This clip is not available. Download it again.');
        return null;
      }
    } else if (source == 'video') {
      final p = await KainuwaEncoder.pickVideo();
      if (p == null || p.isEmpty) return null;
      final ms = await KainuwaEncoder.audioDuration(p);
      if (ms < 1000) {
        if (context.mounted) _say(context, 'This video could not be read (it must be at least 1 second long).');
        return null;
      }
      videoPath = p;
      videoMs = ms;
    } else if (source == 'photo') {
      final p = await KainuwaEncoder.pickImage();
      if (p == null || p.isEmpty) return null;
      picType = 'file';
      picValue = p;
    }
  } catch (e) {
    if (context.mounted) _say(context, 'Could not open it: $e');
    return null;
  }
  if (!context.mounted) return null;

  var all = scene == null;
  if (scene != null) {
    final scope = await showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('Use this background for'),
        children: [
          SimpleDialogOption(onPressed: () => Navigator.pop(c, 'one'), child: const Text('This slide')),
          SimpleDialogOption(onPressed: () => Navigator.pop(c, 'all'), child: const Text('All slides')),
        ],
      ),
    );
    if (scope == null) return null;
    all = scope == 'all';
  }
  final targets = all ? lesson.scenes : [scene!];

  if (videoPath != null) {
    var pos = 0;
    for (final s in targets) {
      var off = pos % videoMs;
      // A slide that would run past the end of the clip starts the clip again.
      if (off + s.durationMs > videoMs) off = 0;
      s.bgType = 'color';
      s.bgValue = '4278190080';
      s.videoPath = videoPath;
      s.videoStartMs = off;
      s.videoMs = videoMs;
      s.videoMuted = true;
      s.videoFill = true;
      pos += s.durationMs;
    }
  } else if (picType != null && picValue != null) {
    for (final s in targets) {
      s.bgType = picType;
      s.bgValue = picValue;
      s.videoPath = '';
      s.videoMs = 0;
      s.videoStartMs = 0;
      s.videoFill = false;
    }
  }
  return 'changed';
}

void _say(BuildContext context, String m) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
}

Widget _tile(BuildContext c, IconData icon, String title, String sub, String value, {bool dot = false}) {
  return ListTile(
    leading: Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(color: KColors.selected, borderRadius: BorderRadius.circular(12)),
      child: Icon(icon, color: Colors.white),
    ),
    title: Row(
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        if (dot) ...[
          const SizedBox(width: 8),
          Container(
            width: 9,
            height: 9,
            decoration: const BoxDecoration(color: Color(0xFF2ECC71), shape: BoxShape.circle),
          ),
        ],
      ],
    ),
    subtitle: Text(sub, style: const TextStyle(fontSize: 12.5)),
    onTap: () => Navigator.of(c).pop(value),
  );
}

class _TemplateGrid extends StatelessWidget {
  const _TemplateGrid({required this.templates, required this.w, required this.h});
  final List<QTemplate> templates;
  final int w;
  final int h;

  @override
  Widget build(BuildContext context) {
    final wide = w > h;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Template pictures', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              ),
            ),
            Flexible(
              child: GridView.count(
                shrinkWrap: true,
                crossAxisCount: wide ? 2 : 3,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: wide ? 16 / 9 : 9 / 16,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  for (final t in templates)
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => Navigator.pop(context, t.assetFor(w, h)),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.asset(t.assetFor(w, h), fit: BoxFit.cover),
                            Positioned(
                              left: 6,
                              right: 6,
                              bottom: 6,
                              child: Text(t.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 12, fontWeight: FontWeight.w700, shadows: [Shadow(blurRadius: 4)])),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClipList extends StatelessWidget {
  const _ClipList({required this.clips, required this.previews});
  final List<BgClip> clips;
  final Map<String, String> previews;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Video backgrounds', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              ),
            ),
            if (clips.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Text('No video backgrounds are downloaded yet.'),
              ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                children: [
                  for (final c in clips)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox(
                          width: 64,
                          height: 44,
                          child: File(previews[c.id] ?? '').existsSync()
                              ? Image.file(File(previews[c.id]!), fit: BoxFit.cover)
                              : const ColoredBox(color: Color(0xFF2A2250), child: Icon(Icons.movie_outlined)),
                        ),
                      ),
                      title: Text(c.name),
                      subtitle: Text('${c.category}  •  ${(c.durationMs / 1000).toStringAsFixed(0)} s'),
                      onTap: () => Navigator.pop(context, c),
                    ),
                ],
              ),
            ),
            TextButton.icon(
              onPressed: () {
                Navigator.pop(context);
                Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const BackgroundsScreen()));
              },
              icon: const Icon(Icons.download),
              label: const Text('Get video backgrounds'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

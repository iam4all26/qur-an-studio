import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:kainuwa_encoder/kainuwa_encoder.dart';

import '../models.dart';
import '../theme.dart';
import 'background_manager.dart';
import 'backgrounds_screen.dart';

/// What the video uses as its background.
/// mode 0 = template picture, 1 = downloaded video clip, 2 = own video, 3 = own photo.
class BgChoice {
  BgChoice({this.mode = 0, this.clipId = '', this.path = '', this.ms = 0});
  final int mode;
  final String clipId;
  final String path;
  final int ms;
}

/// Creates the scenes of a project so the background keeps moving from one verse to the
/// next: every scene continues the clip where the previous scene stopped, and a scene that
/// would run past the end of the clip is split at the loop point.
class BackgroundPlan {
  BackgroundPlan(this.choice, this.videoPath);

  final BgChoice choice;

  /// Local file of the chosen video (empty when the mode has no video).
  final String videoPath;
  int _pos = 0;

  bool get _video => (choice.mode == 1 || choice.mode == 2) && videoPath.isNotEmpty && choice.ms >= 1000;

  static Future<BackgroundPlan> create(BgChoice choice) async {
    var path = '';
    if (choice.mode == 1) path = await BackgroundManager.instance.clipPath(choice.clipId);
    if (choice.mode == 2) path = choice.path;
    if (path.isNotEmpty && !await File(path).exists()) path = '';
    return BackgroundPlan(choice, path);
  }

  /// A readable problem with the choice, or null when it can be used.
  String? get problem {
    if (choice.mode == 1 && !_video) return 'The chosen video clip is not downloaded. Choose another background.';
    if (choice.mode == 2 && !_video) return 'The chosen video could not be read (it must be at least 1 second long).';
    if (choice.mode == 3 && !File(choice.path).existsSync()) return 'The chosen photo is no longer available.';
    return null;
  }

  List<Scene> scenesFor({required int durationMs, required List<Layer> layers, required String imageAsset}) {
    if (!_video) {
      final photo = choice.mode == 3 && choice.path.isNotEmpty;
      return [
        Scene(
          id: newId(),
          durationMs: durationMs,
          bgType: photo ? 'file' : 'asset',
          bgValue: photo ? choice.path : imageAsset,
          layers: layers,
        ),
      ];
    }
    final clip = choice.ms;
    final out = <Scene>[];
    var a = 0;
    while (a < durationMs) {
      var offset = _pos % clip;
      var part = math.min(durationMs - a, clip - offset);
      if (part < 500 && durationMs - a > part) {
        offset = 0;
        part = math.min(durationMs - a, clip);
      }
      if (part <= 0) break;
      final b = a + part;
      out.add(Scene(
        id: newId(),
        durationMs: part,
        bgType: 'color',
        bgValue: '4278190080',
        videoPath: videoPath,
        videoStartMs: offset,
        videoMs: clip,
        videoMuted: true,
        videoFill: true,
        layers: _slice(layers, durationMs, a, b),
      ));
      _pos += part;
      a = b;
    }
    return out;
  }

  /// The layers that are on screen between a and b, with times moved to the part.
  List<Layer> _slice(List<Layer> layers, int total, int a, int b) {
    final out = <Layer>[];
    for (final l in layers) {
      final start = l.startMs;
      final end = l.endMs < 0 ? total : l.endMs;
      if (end <= a || start >= b) continue;
      final c = l.copy();
      c.startMs = math.max(0, start - a);
      c.endMs = end >= b ? -1 : end - a;
      if (start < a) c.animIn = 'none';
      out.add(c);
    }
    return out;
  }
}

/// Background picker used by the wizard and the sync studio.
class BackgroundChooser extends StatefulWidget {
  const BackgroundChooser({super.key, required this.choice, required this.onChanged});

  final BgChoice choice;
  final ValueChanged<BgChoice> onChanged;

  @override
  State<BackgroundChooser> createState() => _BackgroundChooserState();
}

class _BackgroundChooserState extends State<BackgroundChooser> {
  final bm = BackgroundManager.instance;
  String _note = '';

  @override
  void initState() {
    super.initState();
    bm.load();
  }

  Future<void> _pickVideo() async {
    try {
      final path = await KainuwaEncoder.pickVideo();
      if (path == null || path.isEmpty) return;
      final ms = await KainuwaEncoder.audioDuration(path);
      if (!mounted) return;
      setState(() => _note = ms < 1000 ? 'This video length could not be read.' : '');
      widget.onChanged(BgChoice(mode: 2, path: path, ms: ms));
    } catch (e) {
      if (mounted) setState(() => _note = 'Could not open the video: $e');
    }
  }

  Future<void> _pickPhoto() async {
    try {
      final path = await KainuwaEncoder.pickImage();
      if (path == null || path.isEmpty) return;
      widget.onChanged(BgChoice(mode: 3, path: path));
    } catch (e) {
      if (mounted) setState(() => _note = 'Could not open the photo: $e');
    }
  }

  Widget _clips() {
    return AnimatedBuilder(
      animation: bm,
      builder: (context, _) {
        final ready = bm.clips.where((c) => bm.isReady(c.id)).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (ready.isEmpty) const Text('No video clips are downloaded yet.', style: TextStyle(fontSize: 13)),
            if (ready.isNotEmpty)
              Wrap(
                spacing: 8,
                children: [
                  for (final c in ready)
                    ChoiceChip(
                      label: Text(c.name),
                      selected: widget.choice.mode == 1 && widget.choice.clipId == c.id,
                      onSelected: (_) => widget.onChanged(BgChoice(mode: 1, clipId: c.id, ms: c.durationMs)),
                    ),
                ],
              ),
            TextButton.icon(
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute<void>(builder: (_) => const BackgroundsScreen()))
                  .then((_) => setState(() {})),
              icon: const Icon(Icons.download),
              label: const Text('Get video backgrounds'),
            ),
          ],
        );
      },
    );
  }

  String _name(String path) => path.split('/').last;

  @override
  Widget build(BuildContext context) {
    final c = widget.choice;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: const Text('Template picture'),
              selected: c.mode == 0,
              onSelected: (_) => widget.onChanged(BgChoice()),
            ),
            ChoiceChip(
              label: const Text('Video clip'),
              selected: c.mode == 1,
              onSelected: (_) => widget.onChanged(BgChoice(mode: 1)),
            ),
            ChoiceChip(
              label: const Text('My video'),
              selected: c.mode == 2,
              onSelected: (_) => _pickVideo(),
            ),
            ChoiceChip(
              label: const Text('My photo'),
              selected: c.mode == 3,
              onSelected: (_) => _pickPhoto(),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (c.mode == 1) _clips(),
        if (c.mode == 2 && c.path.isNotEmpty)
          Text('${_name(c.path)}, ${(c.ms / 1000).toStringAsFixed(1)} s', style: const TextStyle(fontSize: 12.5)),
        if (c.mode == 3 && c.path.isNotEmpty) Text(_name(c.path), style: const TextStyle(fontSize: 12.5)),
        if (c.mode == 1 || c.mode == 2)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              'A short clip repeats. Video backgrounds make the export slower; 720p is advised.',
              style: TextStyle(fontSize: 11.5, color: KColors.accent),
            ),
          ),
        if (_note.isNotEmpty) Text(_note, style: const TextStyle(fontSize: 12.5)),
      ],
    );
  }
}

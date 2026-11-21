import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:kainuwa_encoder/kainuwa_encoder.dart';

import '../models.dart';
import '../theme.dart';
import 'background_manager.dart';
import 'backgrounds_screen.dart';

/// How long a photo stays on screen inside a background sequence.
const int kPhotoMs = 6000;

/// One background in the sequence: kind 1 = downloaded clip, 2 = own video, 3 = own photo.
class BgItem {
  BgItem({required this.kind, required this.path, this.ms = 0, this.clipId = ''})
      : uid = '${DateTime.now().microsecondsSinceEpoch}_${_counter++}';

  static int _counter = 0;
  final String uid;
  final int kind;
  final String path;

  /// Length of the video in ms (0 for a photo).
  final int ms;
  final String clipId;

  bool get isPhoto => kind == 3;

  /// How long one pass of this item lasts in the sequence.
  int get lengthMs => isPhoto ? kPhotoMs : ms;
}

/// What the video uses as its background: the template picture, or a sequence of video
/// clips, own videos and own photos that plays in order and then starts again from the
/// first one, so the sequence loops without a jump in the middle of an item.
class BgChoice {
  BgChoice({this.template = true, List<BgItem>? items}) : items = items ?? <BgItem>[];

  /// True when the template picture is the background (the media list is then ignored).
  final bool template;
  final List<BgItem> items;

  bool get usesMedia => !template && items.isNotEmpty;

  BgChoice copyWith({bool? template, List<BgItem>? items}) =>
      BgChoice(template: template ?? this.template, items: items ?? this.items);

  /// Reads the backgrounds of an existing video back from its scenes (in the order they first
  /// appear), so a rebuilt timeline keeps the same backgrounds.
  static BgChoice fromScenes(List<Scene> scenes) {
    final items = <BgItem>[];
    final seen = <String>{};
    for (final s in scenes) {
      if (s.videoPath.isNotEmpty && s.videoMs >= 1000) {
        if (seen.add('v|${s.videoPath}')) items.add(BgItem(kind: 2, path: s.videoPath, ms: s.videoMs));
      } else if (s.bgType == 'file' && s.bgValue.isNotEmpty) {
        if (seen.add('p|${s.bgValue}')) items.add(BgItem(kind: 3, path: s.bgValue));
      }
    }
    return BgChoice(template: items.isEmpty, items: items);
  }
}

class _Seg {
  _Seg(this.path, this.ms, this.photo);
  final String path;
  final int ms;
  final bool photo;
}

/// Creates the scenes of a project so the background keeps going from one verse to the next:
/// every scene continues the sequence where the previous scene stopped, a scene that would run
/// past the end of an item is split at that point, and after the last item the sequence starts
/// again with the first.
class BackgroundPlan {
  BackgroundPlan(this.choice, this._segs, this._missing);

  final BgChoice choice;
  final List<_Seg> _segs;
  final int _missing;
  int _seg = 0;
  int _off = 0;

  bool get _media => choice.usesMedia && _segs.isNotEmpty;

  static Future<BackgroundPlan> create(BgChoice choice) async {
    final segs = <_Seg>[];
    var missing = 0;
    if (choice.usesMedia) {
      for (final it in choice.items) {
        final ok = it.path.isNotEmpty && await File(it.path).exists();
        if (!ok || (!it.isPhoto && it.ms < 1000)) {
          missing++;
          continue;
        }
        segs.add(_Seg(it.path, it.lengthMs, it.isPhoto));
      }
    }
    return BackgroundPlan(choice, segs, missing);
  }

  /// A readable problem with the choice, or null when it can be used.
  String? get problem {
    if (!choice.template && choice.items.isEmpty) {
      return 'Choose at least one video or photo, or pick Template.';
    }
    if (choice.usesMedia && _missing > 0) {
      return _missing == 1
          ? 'One chosen background is no longer available. Remove it and choose again.'
          : '$_missing chosen backgrounds are no longer available. Remove them and choose again.';
    }
    return null;
  }

  List<Scene> scenesFor({required int durationMs, required List<Layer> layers, required String imageAsset}) {
    if (!_media) {
      return [
        Scene(
          id: newId(),
          durationMs: durationMs,
          bgType: 'asset',
          bgValue: imageAsset,
          layers: layers,
        ),
      ];
    }
    final out = <Scene>[];
    var a = 0;
    while (a < durationMs) {
      var seg = _segs[_seg];
      var part = math.min(durationMs - a, seg.ms - _off);
      // A tiny leftover at the end of an item is skipped: the next item starts instead.
      if (part < 500 && durationMs - a > part) {
        _seg = (_seg + 1) % _segs.length;
        _off = 0;
        seg = _segs[_seg];
        part = math.min(durationMs - a, seg.ms);
      }
      if (part <= 0) break;
      final b = a + part;
      final sliced = _slice(layers, durationMs, a, b);
      if (seg.photo) {
        out.add(Scene(
          id: newId(),
          durationMs: part,
          bgType: 'file',
          bgValue: seg.path,
          layers: sliced,
        ));
      } else {
        out.add(Scene(
          id: newId(),
          durationMs: part,
          bgType: 'color',
          bgValue: '4278190080',
          videoPath: seg.path,
          videoStartMs: _off,
          videoMs: seg.ms,
          videoMuted: true,
          videoFill: true,
          layers: sliced,
        ));
      }
      _off += part;
      if (_off >= seg.ms) {
        _seg = (_seg + 1) % _segs.length;
        _off = 0;
      }
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

/// Background picker used by the wizard and the sync studio. Tabs: Template, Video clips,
/// My videos, My photos. Videos and photos can be chosen several times; the chosen ones are
/// shown as previews, in the order they play.
class BackgroundChooser extends StatefulWidget {
  const BackgroundChooser({super.key, required this.choice, required this.onChanged});

  final BgChoice choice;
  final ValueChanged<BgChoice> onChanged;

  @override
  State<BackgroundChooser> createState() => _BackgroundChooserState();
}

class _BackgroundChooserState extends State<BackgroundChooser> {
  final bm = BackgroundManager.instance;
  final Map<String, Future<String?>> _frames = {};
  late int _tab;
  String _note = '';

  static const _tabs = ['Template', 'Video clips', 'My videos', 'My photos'];

  @override
  void initState() {
    super.initState();
    _tab = widget.choice.template ? 0 : 1;
    bm.load();
  }

  List<BgItem> get _items => widget.choice.items;

  void _setTab(int i) {
    setState(() {
      _tab = i;
      _note = '';
    });
    widget.onChanged(widget.choice.copyWith(template: i == 0));
  }

  void _add(BgItem item) {
    widget.onChanged(widget.choice.copyWith(template: false, items: [..._items, item]));
  }

  void _removeAt(int i) {
    final list = [..._items]..removeAt(i);
    widget.onChanged(widget.choice.copyWith(items: list));
  }

  void _reorder(int from, int to) {
    if (to > from) to -= 1;
    final list = [..._items];
    final it = list.removeAt(from);
    list.insert(to, it);
    widget.onChanged(widget.choice.copyWith(items: list));
  }

  Future<void> _addVideo() async {
    try {
      final paths = await KainuwaEncoder.pickVideos();
      if (paths.isEmpty) return;
      final added = <BgItem>[];
      var bad = 0;
      for (final path in paths) {
        final ms = await KainuwaEncoder.audioDuration(path);
        if (ms < 1000) {
          bad++;
          continue;
        }
        added.add(BgItem(kind: 2, path: path, ms: ms));
      }
      if (!mounted) return;
      setState(() => _note = bad == 0
          ? ''
          : '$bad video(s) could not be read and were skipped (each must be at least 1 second long).');
      if (added.isNotEmpty) {
        widget.onChanged(widget.choice.copyWith(template: false, items: [..._items, ...added]));
      }
    } catch (e) {
      if (mounted) setState(() => _note = 'Could not open the videos: $e');
    }
  }

  Future<void> _addPhoto() async {
    try {
      final paths = await KainuwaEncoder.pickImages();
      if (paths.isEmpty) return;
      if (!mounted) return;
      setState(() => _note = '');
      widget.onChanged(widget.choice.copyWith(
        template: false,
        items: [..._items, for (final p in paths) BgItem(kind: 3, path: p)],
      ));
    } catch (e) {
      if (mounted) setState(() => _note = 'Could not open the photos: $e');
    }
  }

  Future<void> _toggleClip(BgClip c) async {
    final i = _items.indexWhere((x) => x.kind == 1 && x.clipId == c.id);
    if (i >= 0) {
      _removeAt(i);
      return;
    }
    final path = await bm.clipPath(c.id);
    if (!mounted) return;
    _add(BgItem(kind: 1, path: path, ms: c.durationMs, clipId: c.id));
  }

  Future<String?> _previewOf(BgItem it) {
    return _frames.putIfAbsent(it.kind == 1 ? 'clip_${it.clipId}' : it.uid, () async {
      try {
        if (it.kind == 1) {
          final p = await bm.previewPath(it.clipId);
          if (await File(p).exists()) return p;
        }
        return await KainuwaEncoder.videoFrame(it.path, 0);
      } catch (_) {
        return null;
      }
    });
  }

  Widget _picture(BgItem it, {double w = 72, double h = 100}) {
    Widget fallback() => Container(
          width: w,
          height: h,
          color: KColors.surface,
          child: Icon(it.isPhoto ? Icons.image_outlined : Icons.movie_outlined, color: Colors.white54),
        );
    if (it.isPhoto) {
      return Image.file(File(it.path), width: w, height: h, fit: BoxFit.cover, cacheWidth: 240,
          errorBuilder: (_, __, ___) => fallback());
    }
    return FutureBuilder<String?>(
      future: _previewOf(it),
      builder: (context, snap) {
        final p = snap.data;
        if (p == null || p.isEmpty) return fallback();
        return Image.file(File(p), width: w, height: h, fit: BoxFit.cover, cacheWidth: 240,
            errorBuilder: (_, __, ___) => fallback());
      },
    );
  }

  String _name(String path) => path.split('/').last;

  String _secs(int ms) => '${(ms / 1000).toStringAsFixed(ms % 1000 == 0 ? 0 : 1)} s';

  Widget _selectedStrip() {
    final items = _items;
    if (items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 8),
        child: Text('Nothing chosen yet. Choose one or more; they play in order and then repeat.',
            style: TextStyle(fontSize: 12.5, color: KColors.accent)),
      );
    }
    var total = 0;
    for (final it in items) {
      total += it.lengthMs;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        Text('Selected (${items.length}) - ${_secs(total)} in total, then it repeats',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        const SizedBox(height: 2),
        const Text('Hold and drag to change the order.', style: TextStyle(fontSize: 11.5, color: Colors.white60)),
        const SizedBox(height: 8),
        SizedBox(
          height: 112,
          child: ReorderableListView.builder(
            scrollDirection: Axis.horizontal,
            buildDefaultDragHandles: false,
            itemCount: items.length,
            onReorder: _reorder,
            itemBuilder: (context, i) {
              final it = items[i];
              return ReorderableDelayedDragStartListener(
                key: ValueKey(it.uid),
                index: i,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: SizedBox(
                    width: 72,
                    child: Stack(
                      children: [
                        ClipRRect(borderRadius: BorderRadius.circular(10), child: _picture(it)),
                        Positioned(
                          left: 4,
                          top: 4,
                          child: CircleAvatar(
                            radius: 10,
                            backgroundColor: Colors.black87,
                            child: Text('${i + 1}', style: const TextStyle(fontSize: 11, color: Colors.white)),
                          ),
                        ),
                        Positioned(
                          right: 2,
                          top: 2,
                          child: InkWell(
                            onTap: () => _removeAt(i),
                            child: const CircleAvatar(
                              radius: 10,
                              backgroundColor: Colors.black87,
                              child: Icon(Icons.close, size: 13, color: Colors.white),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Container(
                            color: Colors.black54,
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text(
                              it.isPhoto ? 'Photo' : _secs(it.ms),
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 10.5, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
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
                runSpacing: 8,
                children: [
                  for (final c in ready) _clipTile(c),
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

  Widget _clipTile(BgClip c) {
    final on = _items.any((x) => x.kind == 1 && x.clipId == c.id);
    final probe = BgItem(kind: 1, path: '', ms: c.durationMs, clipId: c.id);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _toggleClip(c),
      child: Container(
        width: 96,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: on ? KColors.gold : Colors.white24, width: on ? 3 : 1),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            children: [
              _picture(probe, w: 96, h: 120),
              if (on)
                const Positioned(
                  right: 4,
                  top: 4,
                  child: CircleAvatar(radius: 11, backgroundColor: KColors.gold, child: Icon(Icons.check, size: 15, color: Colors.black)),
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  color: Colors.black54,
                  padding: const EdgeInsets.all(3),
                  child: Text('${c.name}\n${_secs(c.durationMs)}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 10.5, color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.choice;
    final anyVideo = c.items.any((i) => !i.isPhoto);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (var i = 0; i < _tabs.length; i++)
              ChoiceChip(
                label: Text(_tabs[i]),
                selected: _tab == i,
                onSelected: (_) => _setTab(i),
              ),
          ],
        ),
        const SizedBox(height: 6),
        if (_tab == 0)
          const Text('The template picture is used as the background.', style: TextStyle(fontSize: 12.5)),
        if (_tab == 1) _clips(),
        if (_tab == 2)
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _addVideo,
              icon: const Icon(Icons.video_library_outlined),
              label: const Text('Add videos from this phone'),
            ),
          ),
        if (_tab == 3)
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _addPhoto,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('Add photos from this phone'),
            ),
          ),
        if (_tab != 0) _selectedStrip(),
        if (_tab != 0 && c.items.any((i) => i.isPhoto))
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Each photo stays ${kPhotoMs ~/ 1000} seconds.',
                style: const TextStyle(fontSize: 11.5, color: Colors.white60)),
          ),
        if (_tab != 0 && anyVideo)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              'A short clip repeats. Video backgrounds make the export slower; 720p is advised.',
              style: TextStyle(fontSize: 11.5, color: KColors.accent),
            ),
          ),
        if (_note.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(_note, style: const TextStyle(fontSize: 12.5))),
      ],
    );
  }
}

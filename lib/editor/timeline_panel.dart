import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../animation_math.dart';
import '../models.dart';
import '../scene_canvas.dart';
import '../theme.dart';
import 'editor_tools.dart';
import 'lesson_player.dart';
import 'peaks_cache.dart';

/// The four tracks of the multitrack timeline, in their default order.
const List<String> kDefaultTrackOrder = ['image', 'text', 'audio', 'video'];

String trackName(String id) {
  switch (id) {
    case 'image':
      return 'Background';
    case 'text':
      return 'Verses';
    case 'audio':
      return 'Audio';
    default:
      return 'Video';
  }
}

IconData trackIcon(String id) {
  switch (id) {
    case 'image':
      return Icons.image_outlined;
    case 'text':
      return Icons.title;
    case 'audio':
      return Icons.headphones_outlined;
    default:
      return Icons.videocam_outlined;
  }
}

class _Clip {
  _Clip({
    required this.kind,
    required this.startMs,
    required this.endMs,
    required this.lane,
    required this.sceneIndex,
    this.layer,
    this.scene,
    this.audio,
    this.label = '',
    this.seed = 1,
  });

  /// scene, layer, narration or music
  final String kind;
  final int startMs;
  final int endMs;
  final int lane;
  final int sceneIndex;
  final Layer? layer;
  final Scene? scene;
  final AudioClip? audio;
  final String label;
  final int seed;
}

class TimelinePanel extends StatefulWidget {
  const TimelinePanel({
    super.key,
    required this.lesson,
    required this.player,
    required this.order,
    required this.hidden,
    required this.selectedLayerId,
    required this.selectedAudioId,
    required this.sceneSelected,
    required this.selectedSound,
    required this.onSelectSound,
    required this.onSelectScene,
    required this.onSelectLayer,
    required this.onSelectAudio,
    required this.onSceneMenu,
    required this.onSceneDuration,
    required this.onEditEnd,
    required this.onLayerTiming,
    required this.onAudioChanged,
    required this.onTrackMenu,
    required this.onToggleHidden,
    required this.onAddTrack,
    required this.onAddScene,
    required this.onTransition,
    this.maxUnit = double.infinity,
  });

  /// Upper limit for the size unit, so a wide landscape screen does not make the tracks huge.
  final double maxUnit;
  final Lesson lesson;
  final LessonPlayer player;
  final List<String> order;
  final Set<String> hidden;
  final String? selectedLayerId;
  final String? selectedAudioId;
  final bool sceneSelected;

  /// 'music' or 'narration:<scene index>' when a sound strip is selected.
  final String? selectedSound;
  final void Function(String kind, int sceneIndex) onSelectSound;
  final ValueChanged<int> onSelectScene;
  final void Function(int sceneIndex, String layerId) onSelectLayer;
  final ValueChanged<String> onSelectAudio;
  final ValueChanged<int> onSceneMenu;

  /// Live change of a scene length while a handle is dragged.
  final void Function(int sceneIndex, int ms) onSceneDuration;

  /// Called when a handle drag ends, so the change can be saved.
  final VoidCallback onEditEnd;

  /// An item's start or end was changed on the timeline (live, not yet saved).
  final VoidCallback onLayerTiming;

  /// An extra audio clip was moved or trimmed (live, not yet saved).
  final VoidCallback onAudioChanged;
  final ValueChanged<String> onTrackMenu;
  final ValueChanged<String> onToggleHidden;
  final VoidCallback onAddTrack;
  final VoidCallback onAddScene;

  /// Opens the transition settings for the join after the slide with this index.
  final ValueChanged<int> onTransition;

  @override
  State<TimelinePanel> createState() => _TimelinePanelState();
}

class _TimelinePanelState extends State<TimelinePanel> {
  final ScrollController _scroll = ScrollController();
  double _zoom = 1.0;
  double _zoomStart = 1.0;

  // While the user touches or scrolls the timeline, the view does not follow the playhead.
  DateTime _followHoldUntil = DateTime.fromMillisecondsSinceEpoch(0);
  Offset? _tapDown;
  DateTime _tapTime = DateTime.fromMillisecondsSinceEpoch(0);

  void _holdFollow(int ms) {
    _followHoldUntil = DateTime.now().add(Duration(milliseconds: ms));
  }
  double _pps = 22;

  // handle drag
  double _dragAccum = 0;
  int _dragStartThis = 0;
  int _dragStartPrev = 0;

  @override
  void initState() {
    super.initState();
    widget.player.addListener(_follow);
    PeaksCache.instance.addListener(_peaksReady);
  }

  void _peaksReady() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant TimelinePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.player != widget.player) {
      oldWidget.player.removeListener(_follow);
      widget.player.addListener(_follow);
    }
  }

  @override
  void dispose() {
    widget.player.removeListener(_follow);
    PeaksCache.instance.removeListener(_peaksReady);
    _scroll.dispose();
    super.dispose();
  }

  /// Keeps the playhead on screen while the lesson plays.
  void _follow() {
    if (!widget.player.playing || !_scroll.hasClients) return;
    if (DateTime.now().isBefore(_followHoldUntil)) return;
    final x = widget.player.positionMs / 1000 * _pps;
    final position = _scroll.position;
    final left = position.pixels;
    final right = left + position.viewportDimension;
    if (x > right - 12 || x < left) {
      final target = (x - 24).clamp(0.0, position.maxScrollExtent).toDouble();
      _scroll.jumpTo(target);
    }
  }

  void _seekFromX(double dx) {
    widget.player.seek((dx / _pps * 1000).round());
  }

  String _pillText(int ms) {
    final totalTenths = ms ~/ 100;
    final tenths = totalTenths % 10;
    final seconds = (totalTenths ~/ 10) % 60;
    final minutes = totalTenths ~/ 600;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}.$tenths';
  }

  // ---- building the clips of every track ----

  Map<String, List<_Clip>> _buildClips() {
    final lesson = widget.lesson;
    final image = <_Clip>[];
    final text = <_Clip>[];
    final audio = <_Clip>[];
    final video = <_Clip>[];
    var start = 0;
    var anyNarration = false;
    for (var i = 0; i < lesson.scenes.length; i++) {
      final scene = lesson.scenes[i];
      final end = start + scene.durationMs;
      if (scene.hasVideo) {
        video.add(_Clip(
          kind: 'scene',
          startMs: start,
          endMs: end,
          lane: 0,
          sceneIndex: i,
          scene: scene,
          label: 'Video',
        ));
      }
      image.add(_Clip(
        kind: 'scene',
        startMs: start,
        endMs: end,
        lane: 0,
        sceneIndex: i,
        scene: scene,
        label: '${i + 1}',
      ));
      var imageLane = 1;
      var textLane = 0;
      for (final layer in scene.layers) {
        final dur = scene.durationMs;
        final from = layer.startMs.clamp(0, math.max(0, dur - 200)).toInt();
        final to = math.max(from + 200, layerEndMs(layer, dur));
        if (layer.type == 'text') {
          text.add(_Clip(
            kind: 'layer',
            startMs: start + from,
            endMs: start + math.min(to, dur),
            lane: textLane++,
            sceneIndex: i,
            layer: layer,
            label: layerLabel(layer),
          ));
        } else {
          image.add(_Clip(
            kind: 'layer',
            startMs: start + from,
            endMs: start + math.min(to, dur),
            lane: imageLane++,
            sceneIndex: i,
            layer: layer,
            label: layerLabel(layer),
          ));
        }
      }
      if (scene.narrationPath.isNotEmpty) {
        anyNarration = true;
        final length = scene.narrationMs > 0 ? math.min(scene.narrationLenMs, scene.durationMs) : scene.durationMs;
        audio.add(_Clip(
          kind: 'narration',
          startMs: start,
          endMs: start + length,
          lane: 0,
          sceneIndex: i,
          scene: scene,
          label: 'Narration',
          seed: scene.narrationPath.hashCode,
        ));
      }
      start = end;
    }
    if (lesson.musicPath.isNotEmpty) {
      audio.add(_Clip(
        kind: 'music',
        startMs: 0,
        endMs: start,
        lane: anyNarration ? 1 : 0,
        sceneIndex: 0,
        label: 'Music',
        seed: lesson.musicPath.hashCode,
      ));
    }
    // extra clips of the Audio track, packed into lanes below the rest
    final firstLane = (anyNarration ? 1 : 0) + (lesson.musicPath.isNotEmpty ? 1 : 0);
    final laneEnds = <int>[];
    final sorted = List<AudioClip>.of(lesson.audioClips)..sort((a, b) => a.startMs.compareTo(b.startMs));
    for (final ac in sorted) {
      var lane = laneEnds.indexWhere((end) => end <= ac.startMs);
      if (lane < 0) {
        laneEnds.add(ac.endMs);
        lane = laneEnds.length - 1;
      } else {
        laneEnds[lane] = ac.endMs;
      }
      audio.add(_Clip(
        kind: 'audioclip',
        startMs: ac.startMs,
        endMs: math.max(ac.startMs + 200, ac.endMs),
        lane: firstLane + lane,
        sceneIndex: 0,
        audio: ac,
        label: ac.label,
        seed: ac.path.hashCode,
      ));
    }
    return {'image': image, 'text': text, 'audio': audio, 'video': video};
  }

  int _lanes(List<_Clip> clips) {
    var lanes = 1;
    for (final c in clips) {
      lanes = math.max(lanes, c.lane + 1);
    }
    return lanes;
  }

  // ---- handles on the selected slide clip ----

  Widget _grip(double u) {
    final d = math.max(2.5, 4 * u);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < 5; i++)
          Container(
            width: d,
            height: d,
            margin: EdgeInsets.symmetric(vertical: d * 0.45),
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
          ),
      ],
    );
  }

  Widget _handle({required bool left, required int index, required double u}) {
    final lesson = widget.lesson;
    final scene = lesson.scenes[index];
    final width = math.max(24.0, 40 * u);
    return Positioned(
      left: left ? 0.0 : null,
      right: left ? null : 0.0,
      top: 0,
      bottom: 0,
      width: width,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) {
          _dragAccum = 0;
          _dragStartThis = scene.durationMs;
          _dragStartPrev = index > 0 ? lesson.scenes[index - 1].durationMs : 0;
        },
        onHorizontalDragUpdate: (d) {
          _dragAccum += d.delta.dx;
          var deltaMs = (_dragAccum / _pps * 1000);
          deltaMs = (deltaMs / 100).round() * 100.0;
          if (!left) {
            final minMs = math.max(500, scene.narrationLenMs);
            final ms = math.max(minMs, _dragStartThis + deltaMs.round());
            widget.onSceneDuration(index, ms);
          } else if (index > 0) {
            final prev = lesson.scenes[index - 1];
            final minPrev = math.max(500, prev.narrationLenMs);
            final minThis = math.max(500, scene.narrationLenMs);
            final low = (minPrev - _dragStartPrev).toDouble();
            final high = (_dragStartThis - minThis).toDouble();
            if (high >= low) {
              final delta = deltaMs.clamp(low, high).round();
              widget.onSceneDuration(index - 1, _dragStartPrev + delta);
              widget.onSceneDuration(index, _dragStartThis - delta);
            }
          }
        },
        onHorizontalDragEnd: (_) => widget.onEditEnd(),
        onHorizontalDragCancel: () => widget.onEditEnd(),
        child: Container(
          alignment: Alignment.center,
          color: const Color(0x33000000),
          child: (left && index == 0) ? const SizedBox.shrink() : _grip(u),
        ),
      ),
    );
  }

  // ---- handles and moving of a selected item ----

  int _layerStartA = 0;
  int _layerStartB = 0;

  void _layerDragStart(Layer layer, int sceneMs) {
    _dragAccum = 0;
    _layerStartA = layer.startMs;
    _layerStartB = layerEndMs(layer, sceneMs);
  }

  /// Zooms the timeline and keeps the playhead in the middle of the view.
  void _zoomTo(double value) {
    setState(() => _zoom = value.clamp(0.25, 30.0).toDouble());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final pos = _scroll.position;
      final x = widget.player.positionMs / 1000 * _pps - pos.viewportDimension / 2;
      _scroll.jumpTo(x.clamp(0.0, pos.maxScrollExtent).toDouble());
    });
  }

  Widget _zoomButton(IconData icon, String tip, VoidCallback onTap) {
    return Tooltip(
      message: tip,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: KColors.editorLabel,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 17, color: Colors.white),
        ),
      ),
    );
  }

  double _roundedDelta() => ((_dragAccum / _pps * 1000) / 100).round() * 100.0;

  void _layerTrim(Layer layer, int sceneMs, {required bool left}) {
    final delta = _roundedDelta().round();
    if (left) {
      layer.startMs = (_layerStartA + delta).clamp(0, math.max(0, _layerStartB - 200)).toInt();
    } else {
      final end = (_layerStartB + delta).clamp(_layerStartA + 200, sceneMs).toInt();
      layer.endMs = end >= sceneMs ? -1 : end;
    }
    widget.onLayerTiming();
  }

  void _layerMove(Layer layer, int sceneMs) {
    var delta = _roundedDelta().round();
    delta = delta.clamp(-_layerStartA, sceneMs - _layerStartB).toInt();
    layer.startMs = _layerStartA + delta;
    final end = _layerStartB + delta;
    layer.endMs = end >= sceneMs ? -1 : end;
    widget.onLayerTiming();
  }

  Widget _layerHandle({required bool left, required Layer layer, required int sceneMs, required double u}) {
    final width = math.max(24.0, 40 * u);
    return Positioned(
      left: left ? 0.0 : null,
      right: left ? null : 0.0,
      top: 0,
      bottom: 0,
      width: width,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) => _layerDragStart(layer, sceneMs),
        onHorizontalDragUpdate: (d) {
          _dragAccum += d.delta.dx;
          _layerTrim(layer, sceneMs, left: left);
        },
        onHorizontalDragEnd: (_) => widget.onEditEnd(),
        onHorizontalDragCancel: () => widget.onEditEnd(),
        child: Container(
          alignment: Alignment.center,
          color: const Color(0x33000000),
          child: _grip(u),
        ),
      ),
    );
  }

  // ---- extra audio clips: move and trim ----

  int _aStart = 0;
  int _aTrim = 0;
  int _aDur = 0;

  void _audioDragStart(AudioClip ac) {
    _dragAccum = 0;
    _aStart = ac.startMs;
    _aTrim = ac.trimMs;
    _aDur = ac.durationMs;
  }

  void _audioMove(AudioClip ac) {
    final total = widget.lesson.durationMs;
    ac.startMs = (_aStart + _roundedDelta().round()).clamp(0, math.max(0, total - 300)).toInt();
    widget.onAudioChanged();
  }

  void _audioTrim(AudioClip ac, {required bool left}) {
    final delta = _roundedDelta().round();
    if (left) {
      final low = math.max(-_aTrim, -_aStart);
      final high = _aDur - 300;
      if (high >= low) {
        final applied = delta.clamp(low, high).toInt();
        ac.trimMs = _aTrim + applied;
        ac.startMs = _aStart + applied;
        ac.durationMs = _aDur - applied;
      }
    } else {
      final high = math.max(300, ac.sourceMs - ac.trimMs);
      ac.durationMs = (_aDur + delta).clamp(300, high).toInt();
    }
    final half = ac.durationMs ~/ 2;
    if (ac.fadeInMs > half) ac.fadeInMs = half;
    if (ac.fadeOutMs > half) ac.fadeOutMs = half;
    widget.onAudioChanged();
  }

  Widget _audioHandle({required bool left, required AudioClip ac, required double u}) {
    final width = math.max(24.0, 40 * u);
    return Positioned(
      left: left ? 0.0 : null,
      right: left ? null : 0.0,
      top: 0,
      bottom: 0,
      width: width,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) => _audioDragStart(ac),
        onHorizontalDragUpdate: (d) {
          _dragAccum += d.delta.dx;
          _audioTrim(ac, left: left);
        },
        onHorizontalDragEnd: (_) => widget.onEditEnd(),
        onHorizontalDragCancel: () => widget.onEditEnd(),
        child: Container(
          alignment: Alignment.center,
          color: const Color(0x33000000),
          child: _grip(u),
        ),
      ),
    );
  }

  // ---- one clip ----

  Widget _clipView(_Clip clip, double w, double h, double u) {
    final radius = BorderRadius.circular(math.max(6.0, 14 * u));
    final fontSize = math.max(10.5, 26 * u);
    Widget body;
    bool selected = false;
    VoidCallback? onTap;
    VoidCallback? onLong;
    GestureDragStartCallback? dragStart;
    GestureDragUpdateCallback? dragUpdate;
    VoidCallback? dragEnd;

    switch (clip.kind) {
      case 'scene':
        selected = widget.sceneSelected && clip.sceneIndex == sceneIndexNow;
        onTap = () => widget.onSelectScene(clip.sceneIndex);
        onLong = () => widget.onSceneMenu(clip.sceneIndex);
        body = Stack(
          fit: StackFit.expand,
          children: [
            IgnorePointer(child: SceneBackground(scene: clip.scene!)),
            Positioned(
              left: 6,
              top: 3,
              child: Text(
                clip.label,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: math.max(10.0, 22 * u),
                  fontWeight: FontWeight.w800,
                  shadows: const [Shadow(color: Color(0xCC000000), blurRadius: 4)],
                ),
              ),
            ),
          ],
        );
        break;
      case 'layer':
        final layer = clip.layer!;
        selected = !widget.sceneSelected && widget.selectedLayerId == layer.id;
        onTap = () => widget.onSelectLayer(clip.sceneIndex, layer.id);
        if (selected) {
          final sceneMs = widget.lesson.scenes[clip.sceneIndex].durationMs;
          dragStart = (_) => _layerDragStart(layer, sceneMs);
          dragUpdate = (d) {
            _dragAccum += d.delta.dx;
            _layerMove(layer, sceneMs);
          };
          dragEnd = widget.onEditEnd;
        }
        final isText = layer.type == 'text';
        final fg = isText ? KColors.onGold : Colors.white;
        body = Container(
          color: isText ? KColors.clipText : KColors.clipPicture,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.centerLeft,
          child: Row(
            children: [
              Icon(layerIcon(layer), size: math.max(14.0, 34 * u), color: fg),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  clip.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: fg, fontSize: fontSize, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        );
        break;
      case 'audioclip':
        {
          final ac = clip.audio!;
          selected = widget.selectedAudioId == ac.id;
          onTap = () => widget.onSelectAudio(ac.id);
          final color = ac.kind == 'sfx'
              ? const Color(0xFFD9822B)
              : (ac.kind == 'voice' ? KColors.clipAudio : KColors.clipMusic);
          final from = ac.sourceMs <= 0 ? 0.0 : ac.trimMs / ac.sourceMs;
          final to = ac.sourceMs <= 0 ? 1.0 : (ac.trimMs + ac.durationMs) / ac.sourceMs;
          body = Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: color),
              CustomPaint(
                painter: _WavePainter(
                  seed: clip.seed,
                  peaks: PeaksCache.instance.peaksFor(ac.path),
                  from: from,
                  to: to,
                ),
              ),
              Positioned(
                left: 6,
                top: 2,
                right: 6,
                child: Text(
                  clip.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: math.max(9.5, 20 * u),
                    fontWeight: FontWeight.w700,
                    shadows: const [Shadow(color: Color(0xAA000000), blurRadius: 3)],
                  ),
                ),
              ),
            ],
          );
          if (selected) {
            dragStart = (_) => _audioDragStart(ac);
            dragUpdate = (d) {
              _dragAccum += d.delta.dx;
              _audioMove(ac);
            };
            dragEnd = widget.onEditEnd;
          }
        }
        break;
      default:
        final music = clip.kind == 'music';
        final soundKey = music ? 'music' : 'narration:${clip.sceneIndex}';
        selected = widget.selectedSound == soundKey;
        onTap = () {
          widget.onSelectSound(music ? 'music' : 'narration', clip.sceneIndex);
        };
        final path = music ? widget.lesson.musicPath : (clip.scene?.narrationPath ?? '');
        body = Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: music ? KColors.clipMusic : KColors.clipAudio),
            CustomPaint(painter: _WavePainter(seed: clip.seed, peaks: PeaksCache.instance.peaksFor(path))),
          ],
        );
    }

    Widget view = ClipRRect(borderRadius: radius, child: body);
    if (selected) {
      view = Container(
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: const [BoxShadow(color: Color(0x663B0F8C), blurRadius: 6)],
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(borderRadius: radius, child: body),
            if (clip.kind == 'scene') ...[
              _handle(left: true, index: clip.sceneIndex, u: u),
              _handle(left: false, index: clip.sceneIndex, u: u),
            ],
            if (clip.kind == 'audioclip') ...[
              _audioHandle(left: true, ac: clip.audio!, u: u),
              _audioHandle(left: false, ac: clip.audio!, u: u),
            ],
            if (clip.kind == 'layer') ...[
              _layerHandle(left: true, layer: clip.layer!, sceneMs: widget.lesson.scenes[clip.sceneIndex].durationMs, u: u),
              _layerHandle(left: false, layer: clip.layer!, sceneMs: widget.lesson.scenes[clip.sceneIndex].durationMs, u: u),
            ],
          ],
        ),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onLong,
      onHorizontalDragStart: dragStart,
      onHorizontalDragUpdate: dragUpdate,
      onHorizontalDragEnd: dragEnd == null ? null : (_) => dragEnd!(),
      child: view,
    );
  }

  int get sceneIndexNow => sceneAt(widget.lesson, widget.player.positionMs).index;

  // ---- label column ----

  Widget _labelChip(String id, double height, double u, double labelW) {
    final hidden = widget.hidden.contains(id);
    final iconSize = math.max(16.0, 36 * u);
    return Container(
      width: labelW,
      height: height,
      decoration: BoxDecoration(
        color: KColors.editorLabel,
        borderRadius: BorderRadius.circular(math.max(8.0, 18 * u)),
        boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 4, offset: Offset(0, 1))],
      ),
      padding: EdgeInsets.symmetric(horizontal: math.max(4.0, 10 * u)),
      child: Row(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => widget.onToggleHidden(id),
            child: Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(
                hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                size: iconSize,
                color: KColors.ink,
              ),
            ),
          ),
          Icon(trackIcon(id), size: iconSize, color: KColors.ink),
          const SizedBox(width: 4),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                trackName(id),
                maxLines: 1,
                style: TextStyle(
                  fontSize: math.max(11.0, 27 * u),
                  fontWeight: FontWeight.w500,
                  color: KColors.ink,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final u = math.min(width / 941.0, widget.maxUnit);
        final labelLeft = 14 * u;
        final labelW = math.max(84.0, 214 * u);
        final stripLeft = labelLeft + labelW + 5 * u;
        final viewportW = width - stripLeft - 13 * u;
        _pps = (viewportW / 31.2) * _zoom;
        final pps = _pps;

        final rulerH = 128 * u;
        final baseRow = math.max(34.0, 70 * u);
        final pad = math.max(2.0, 2 * u);
        final clipH = baseRow - 2 * pad;
        final stride = clipH + pad;
        final rowGap = math.max(4.0, 10 * u);
        final addH = math.max(30.0, 52 * u);
        // Transition button: small, and the room kept free on each side of it.
        final tBtn = math.max(14.0, math.min(clipH * 0.55, 22.0));
        final tGap = tBtn / 2 + 4;

        final clips = _buildClips();
        final totalMs = widget.lesson.durationMs;
        final contentW = math.max(viewportW, totalMs / 1000 * pps + 60 * u + clipH);

        final rowHeights = <String, double>{};
        for (final id in widget.order) {
          rowHeights[id] = baseRow + (_lanes(clips[id]!) - 1) * stride;
        }
        var rowsTotal = 0.0;
        for (final id in widget.order) {
          rowsTotal += rowHeights[id]! + rowGap;
        }
        final panelH = rulerH + rowsTotal + 12 * u + addH + 10 * u;

        // ---- scroll content (ruler, rows, playhead) ----
        final rows = <Widget>[];
        var top = rulerH;
        for (final id in widget.order) {
          final rowH = rowHeights[id]!;
          final hidden = widget.hidden.contains(id);
          final children = <Widget>[
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (d) => _seekFromX(d.localPosition.dx),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: KColors.editorStrip,
                    borderRadius: BorderRadius.circular(math.max(8.0, 16 * u)),
                  ),
                ),
              ),
            ),
          ];
          for (final clip in clips[id]!) {
            var x = clip.startMs / 1000 * pps;
            var w = math.max(8.0, (clip.endMs - clip.startMs) / 1000 * pps - 2);
            if (clip.kind == 'scene') {
              // Leave a clear gap beside every join so the transition button never touches a slide.
              final lastIndex = widget.lesson.scenes.length - 1;
              if (clip.sceneIndex > 0) {
                x += tGap;
                w -= tGap;
              }
              if (clip.sceneIndex < lastIndex) w -= tGap;
              w = math.max(8.0, w);
            }
            children.add(Positioned(
              left: x,
              top: pad + clip.lane * stride,
              width: w,
              height: clipH,
              child: _clipView(clip, w, clipH, u),
            ));
          }
          if (id == 'video' && clips[id]!.isEmpty) {
            children.add(Positioned(
              left: 12 * u,
              top: 0,
              bottom: 0,
              child: Center(
                child: Text(
                  'Screen recordings will appear here',
                  style: TextStyle(fontSize: math.max(10.0, 22 * u), color: const Color(0xFFA89DD0)),
                ),
              ),
            ));
          }
          if (id == 'image') {
            final btn = tBtn;
            for (var i = 0; i < widget.lesson.scenes.length - 1; i++) {
              final boundaryMs = sceneStartMs(widget.lesson, i + 1);
              final on = widget.lesson.scenes[i].transKind != 'none';
              children.add(Positioned(
                left: boundaryMs / 1000 * pps - btn / 2,
                top: pad + (clipH - btn) / 2,
                width: btn,
                height: btn,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => widget.onTransition(i),
                  child: Container(
                    decoration: BoxDecoration(
                      color: on ? const Color(0xFF7351FF) : KColors.editorLabel,
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF7351FF), width: 1.5),
                    ),
                    child: Icon(Icons.compare_arrows, size: btn * 0.62, color: Colors.white),
                  ),
                ),
              ));
            }
          }
          if (id == 'image') {
            children.add(Positioned(
              left: totalMs / 1000 * pps + 6,
              top: pad,
              width: clipH,
              height: clipH,
              child: GestureDetector(
                onTap: widget.onAddScene,
                child: Container(
                  decoration: BoxDecoration(
                    color: KColors.lavender,
                    borderRadius: BorderRadius.circular(math.max(6.0, 14 * u)),
                    border: Border.all(color: KColors.purple, width: 1.2),
                  ),
                  child: const Icon(Icons.add, color: KColors.purple),
                ),
              ),
            ));
          }
          Widget row = SizedBox(width: contentW, height: rowH, child: Stack(children: children));
          if (hidden) row = Opacity(opacity: 0.4, child: row);
          rows.add(Positioned(left: 0, top: top, child: row));
          top += rowH + rowGap;
        }

        final playheadX = widget.player.positionMs / 1000 * pps;
        final pillW = math.max(64.0, 107 * u);
        final pillH = math.max(22.0, 42 * u);
        final lineW = math.max(2.0, 3 * u);

        final content = Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (e) {
            _holdFollow(3000);
            _tapDown = e.localPosition;
            _tapTime = DateTime.now();
          },
          onPointerMove: (_) => _holdFollow(3000),
          onPointerUp: (e) {
            _holdFollow(2500);
            final down = _tapDown;
            _tapDown = null;
            // A quick tap anywhere on the timeline moves the playhead there.
            if (down != null &&
                (e.localPosition - down).distance < 10 &&
                DateTime.now().difference(_tapTime).inMilliseconds < 400) {
              _seekFromX(e.localPosition.dx);
            }
          },
          child: SizedBox(
          width: contentW,
          height: panelH,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                top: 0,
                width: contentW,
                height: rulerH,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) => _seekFromX(d.localPosition.dx),
                  onScaleStart: (_) => _zoomStart = _zoom,
                  onScaleUpdate: (d) {
                    if (d.pointerCount >= 2) {
                      setState(() => _zoom = (_zoomStart * d.scale).clamp(0.25, 30.0).toDouble());
                    }
                  },
                  child: CustomPaint(painter: _RulerPainter(pps: pps, u: u)),
                ),
              ),
              ...rows,
              Positioned(
                left: playheadX - lineW / 2,
                top: 66 * u,
                width: lineW,
                height: panelH - 66 * u - 6 * u,
                child: IgnorePointer(child: ColoredBox(color: KColors.editorPlayhead)),
              ),
              Positioned(
                left: playheadX - pillW / 2 - 12,
                top: 26 * u,
                width: pillW + 24,
                height: pillH + 10,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragUpdate: (d) {
                    final ms = widget.player.positionMs + (d.delta.dx / pps * 1000).round();
                    widget.player.seek(ms);
                  },
                  child: Center(
                    child: Container(
                      width: pillW,
                      height: pillH,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: KColors.editorPlay,
                        borderRadius: BorderRadius.circular(pillH),
                        boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 4, offset: Offset(0, 1))],
                      ),
                      child: Text(
                        _pillText(widget.player.positionMs),
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: math.max(10.0, 24 * u),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ));

        // ---- fixed left column ----
        final labels = <Widget>[SizedBox(height: rulerH)];
        for (final id in widget.order) {
          labels.add(_labelChip(id, rowHeights[id]!, u, labelW));
          labels.add(SizedBox(height: rowGap));
        }
        labels.add(SizedBox(height: 12 * u));
        labels.add(SizedBox(height: addH));

        // ---- fixed menu icons at the right edge of every row ----
        final menus = <Widget>[];
        var menuTop = rulerH;
        for (final id in widget.order) {
          final rowH = rowHeights[id]!;
          menus.add(Positioned(
            right: 6 * u,
            top: menuTop,
            height: baseRow,
            width: math.max(32.0, 60 * u),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => widget.onTrackMenu(id),
              child: Center(
                child: Icon(Icons.menu, size: math.max(16.0, 34 * u), color: const Color(0xFF9C8FD0)),
              ),
            ),
          ));
          menuTop += rowH + rowGap;
        }

        return SizedBox(
          height: panelH,
          child: Stack(
            children: [
              Positioned(left: labelLeft, top: 0, width: labelW, height: panelH, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: labels)),
              Positioned(
                left: labelLeft,
                top: 8 * u,
                width: labelW,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _zoomButton(Icons.zoom_out, 'Zoom out', () => _zoomTo(_zoom / 1.6)),
                    const SizedBox(width: 2),
                    _zoomButton(Icons.zoom_in, 'Zoom in', () => _zoomTo(_zoom * 1.6)),
                    const SizedBox(width: 2),
                    _zoomButton(
                      _zoom > 8 ? Icons.fit_screen : Icons.unfold_more,
                      _zoom > 8 ? 'Back to normal width' : 'Wide: see tenths of a second',
                      () => _zoomTo(_zoom > 8 ? 1 : 24),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: stripLeft,
                right: 13 * u,
                top: 0,
                height: panelH,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: SingleChildScrollView(
                        controller: _scroll,
                        scrollDirection: Axis.horizontal,
                        physics: const ClampingScrollPhysics(),
                        child: content,
                      ),
                    ),
                    ...menus,
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// painters
// ---------------------------------------------------------------------------

class _RulerPainter extends CustomPainter {
  _RulerPainter({required this.pps, required this.u});

  final double pps;
  final double u;

  static const List<double> _steps = [0.1, 0.2, 0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600];

  @override
  void paint(Canvas canvas, Size size) {
    var step = _steps.last;
    for (final s in _steps) {
      if (s * pps >= 100 * u) {
        step = s;
        break;
      }
    }
    final minor = step / 5.0;
    final tickPaint = Paint()
      ..color = const Color(0xFF8E84B8)
      ..strokeWidth = math.max(1.0, 2 * u);
    final seconds = size.width / pps;
    final count = (seconds / minor).ceil() + 1;
    for (var i = 0; i < count; i++) {
      final sec = i * minor;
      final x = sec * pps;
      if (x > size.width) break;
      final major = i % 5 == 0;
      final y1 = 73 * u;
      final y2 = major ? 98 * u : 86 * u;
      canvas.drawLine(Offset(x, y1), Offset(x, y2), tickPaint);
      if (major) {
        String label;
        if (step < 1) {
          final tenths = (sec * 10).round();
          final whole = tenths ~/ 10;
          label = '${whole ~/ 60}:${(whole % 60).toString().padLeft(2, '0')}.${tenths % 10}';
        } else {
          final total = sec.round();
          label = '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
        }
        final painter = TextPainter(
          text: TextSpan(
            text: label,
            style: TextStyle(
              color: const Color(0xFFB5ABD6),
              fontSize: math.max(10.0, 24 * u),
              fontWeight: FontWeight.w500,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        painter.paint(canvas, Offset(x - painter.width / 2, 53 * u - painter.height / 2));
        painter.dispose();
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RulerPainter oldDelegate) =>
      oldDelegate.pps != pps || oldDelegate.u != u;
}

/// A waveform. It uses the real loudness of the file when it is known, and a
/// look-alike drawn from the file name while it is still being read.
class _WavePainter extends CustomPainter {
  _WavePainter({required this.seed, this.peaks, this.from = 0, this.to = 1});

  final int seed;
  final List<double>? peaks;
  final double from;
  final double to;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.2;
    final mid = size.height / 2;
    final count = (size.width / 5).floor();
    final data = peaks;
    for (var i = 0; i < count; i++) {
      double amp;
      if (data != null && data.isNotEmpty) {
        final f = count <= 1 ? from : from + (to - from) * (i / (count - 1));
        final index = (f * (data.length - 1)).round().clamp(0, data.length - 1).toInt();
        amp = math.max(2.0, math.sqrt(data[index]) * size.height * 0.46);
      } else {
        final r = (((i * 2654435761) ^ (seed * 40503)) >> 3) & 0xFF;
        final env = 0.35 + 0.65 * (math.sin(i * 0.23 + (seed & 7)) * 0.5 + 0.5);
        amp = math.max(2.0, (r / 255.0) * env * (size.height * 0.42));
      }
      final x = 4.0 + i * 5.0;
      canvas.drawLine(Offset(x, mid - amp), Offset(x, mid + amp), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WavePainter oldDelegate) =>
      oldDelegate.seed != seed ||
      oldDelegate.peaks != peaks ||
      oldDelegate.from != from ||
      oldDelegate.to != to;
}

class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, math.min(d + 5, metric.length)), paint);
        d += 9;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}

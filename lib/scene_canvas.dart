import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:kainuwa_encoder/kainuwa_encoder.dart';

import 'animation_math.dart';
import 'demo_plan.dart';
import 'hands.dart';
import 'models.dart';
import 'stage_shape.dart';
import 'text_reveal.dart';

/// Draws one scene. Everything is sized from fractions of the slide, so the
/// same widget works for the editor, small thumbnails and video export.
class SceneCanvas extends StatefulWidget {
  const SceneCanvas({
    super.key,
    required this.scene,
    this.selectedId,
    this.onSelect,
    this.onCommit,
    this.onDuplicate,
    this.onDelete,
    this.interactive = false,
    this.tapSelect = false,
    this.previewMs,
    this.ghostAtMs,
    this.demoId,
    this.demoMs,
  });

  final Scene scene;
  final String? selectedId;
  final ValueChanged<String?>? onSelect;
  final VoidCallback? onCommit;

  /// Called with the layer id when the copy button on the selection is tapped.
  final ValueChanged<String>? onDuplicate;

  /// Called with the layer id when the delete button on the selection is tapped.
  final ValueChanged<String>? onDelete;
  final bool interactive;

  /// While the slide plays (not interactive), a tap on an item still selects it.
  final bool tapSelect;

  /// When set, the scene is drawn as it looks at this time (in milliseconds),
  /// with entrance animations applied.
  final int? previewMs;

  /// Editor only: while paused at this time (milliseconds into the slide), items
  /// that are not on screen at that moment are drawn faded so they can still be edited.
  final int? ghostAtMs;

  /// Editor only: while the Animate panel is open, the item with this id plays its
  /// animations on the canvas, [demoMs] milliseconds into the demo round.
  final String? demoId;
  final int? demoMs;

  @override
  State<SceneCanvas> createState() => _SceneCanvasState();
}

class _SceneCanvasState extends State<SceneCanvas> {
  Offset? _startFocal;
  double _startCx = 0;
  double _startCy = 0;
  double _startW = 0;
  double _startH = 0;
  double _startRotation = 0;
  double _startDistance = 1;

  /// True while the user is moving, resizing or turning the selected item: guide lines show.
  bool _guiding = false;
  bool _snapX = false;
  bool _snapY = false;

  void _guideOn() {
    if (!_guiding) setState(() => _guiding = true);
  }

  void _guideOff() {
    if (_guiding || _snapX || _snapY) {
      setState(() {
        _guiding = false;
        _snapX = false;
        _snapY = false;
      });
    }
  }

  /// Pulls [value] onto the slide centre or onto another item's centre when it is very close.
  (double, bool) _snap(double value, Iterable<double> targets) {
    const reach = 0.012;
    var best = value;
    var bestGap = reach;
    var hit = false;
    for (final t in targets) {
      final gap = (value - t).abs();
      if (gap < bestGap) {
        best = t;
        bestGap = gap;
        hit = true;
      }
    }
    return (best, hit);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final children = <Widget>[
          Positioned.fill(child: SceneBackground(scene: widget.scene, liveMs: widget.previewMs)),
        ];
        if (widget.interactive) {
          children.add(
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => widget.onSelect?.call(null),
              ),
            ),
          );
        }
        Layer? selected;
        for (final layer in widget.scene.layers) {
          children.add(_buildLayer(layer, width, height));
          if (widget.interactive && layer.id == widget.selectedId) selected = layer;
        }
        for (final layer in widget.scene.layers) {
          if (layer.hand.isEmpty) continue;
          final t = _timing(layer);
          if (t != null) children.add(_buildHand(t.$1, t.$2, width, height));
        }
        if (selected != null && _guiding) {
          children.add(_buildGuides(selected, width, height));
        }
        if (selected != null) {
          children.add(_buildSelection(selected, width, height));
        }
        return ClipRect(child: Stack(children: children));
      },
    );
  }

  // ---- guide lines and exact coordinates while adjusting ----

  Widget _buildGuides(Layer layer, double width, double height) {
    final x = layer.cx * width;
    final y = layer.cy * height;
    final label = 'X ${(layer.cx * 100).toStringAsFixed(1)}%   Y ${(layer.cy * 100).toStringAsFixed(1)}%';
    final fs = math.max(10.0, width / 36);
    final labelW = fs * 11.5;
    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(painter: _GuidePainter(layer.cx, layer.cy, _snapX, _snapY)),
            ),
            Positioned(
              left: (x + 10).clamp(4.0, math.max(4.0, width - labelW - 4)).toDouble(),
              top: (y + 10).clamp(4.0, math.max(4.0, height - fs * 2.2)).toDouble(),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: fs * 0.6, vertical: fs * 0.3),
                decoration: BoxDecoration(
                  color: const Color(0xFF7351FF),
                  borderRadius: BorderRadius.circular(fs),
                ),
                child: Text(
                  label,
                  style: TextStyle(color: Colors.white, fontSize: fs, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- selection frame with handles (as in the mockup) ----

  Offset _toLocal(Offset global) {
    final box = context.findRenderObject();
    if (box is RenderBox) return box.globalToLocal(global);
    return global;
  }

  Offset _centerOf(Layer layer, double width, double height) =>
      Offset(layer.cx * width, layer.cy * height);

  Widget _roundButton(double size, IconData icon, VoidCallback? onTap) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Color(0x44000000), blurRadius: 4, offset: Offset(0, 1))],
        ),
        child: Icon(icon, size: size * 0.58, color: const Color(0xFF5B21B6)),
      ),
    );
  }

  Widget _buildSelection(Layer layer, double width, double height) {
    final k = width / 885.0;
    final btn = math.max(28.0, 52 * k);
    final dot = math.max(10.0, 18 * k);
    final hit = dot * 2.4;
    final gap = math.max(8.0, 14 * k);
    final pad = btn + gap + 4;
    final boxW = layer.w * width;
    final boxH = layer.h * height;
    final center = _centerOf(layer, width, height);

    Widget corner(double dx, double dy) {
      return Positioned(
        left: pad + dx - hit / 2,
        top: pad + dy - hit / 2,
        width: hit,
        height: hit,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (d) {
            _guideOn();
            _startW = layer.w;
            _startH = layer.h;
            _startDistance = math.max(4.0, (_toLocal(d.globalPosition) - center).distance);
          },
          onPanUpdate: (d) {
            final dist = (_toLocal(d.globalPosition) - center).distance;
            final f = dist / _startDistance;
            setState(() {
              layer.w = (_startW * f).clamp(0.03, 1.6).toDouble();
              layer.h = (_startH * f).clamp(0.03, 1.6).toDouble();
            });
          },
          onPanEnd: (_) {
            _guideOff();
            widget.onCommit?.call();
          },
          onPanCancel: () {
            _guideOff();
            widget.onCommit?.call();
          },
          child: Center(
            child: Container(
              width: dot,
              height: dot,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Color(0x66000000), blurRadius: 3)],
              ),
            ),
          ),
        ),
      );
    }

    Widget line(double left, double top, double w, double h) {
      return Positioned(
        left: left,
        top: top,
        width: w,
        height: h,
        child: const IgnorePointer(child: ColoredBox(color: Colors.white)),
      );
    }

    final midX = pad + boxW / 2;
    final midY = pad + boxH / 2;

    final overlay = Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: pad - 1,
          top: pad - 1,
          width: boxW + 2,
          height: boxH + 2,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(border: Border.all(color: const Color(0x66000000), width: 1)),
            ),
          ),
        ),
        Positioned(
          left: pad,
          top: pad,
          width: boxW,
          height: boxH,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(border: Border.all(color: Colors.white, width: 1.6)),
            ),
          ),
        ),
        // connectors to the three round buttons
        line(midX - 0.8, pad - gap, 1.6, gap),
        line(pad - gap, midY - 0.8, gap, 1.6),
        line(pad + boxW, midY - 0.8, gap, 1.6),
        corner(0, 0),
        corner(boxW, 0),
        corner(0, boxH),
        corner(boxW, boxH),
        // turn
        Positioned(
          left: midX - btn / 2,
          top: pad - gap - btn,
          width: btn,
          height: btn,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) => _guideOn(),
            onPanUpdate: (d) {
              final p = _toLocal(d.globalPosition) - center;
              var angle = math.atan2(p.dy, p.dx) + math.pi / 2;
              final step = math.pi / 4;
              final nearest = (angle / step).round() * step;
              if ((angle - nearest).abs() < 0.05) angle = nearest;
              setState(() => layer.rotation = angle);
            },
            onPanEnd: (_) {
              _guideOff();
              widget.onCommit?.call();
            },
            onPanCancel: () {
              _guideOff();
              widget.onCommit?.call();
            },
            child: _roundButton(btn, Icons.rotate_right, null),
          ),
        ),
        // copy
        Positioned(
          left: pad - gap - btn,
          top: midY - btn / 2,
          width: btn,
          height: btn,
          child: _roundButton(btn, Icons.copy_all_outlined, () => widget.onDuplicate?.call(layer.id)),
        ),
        // delete
        Positioned(
          left: pad + boxW + gap,
          top: midY - btn / 2,
          width: btn,
          height: btn,
          child: _roundButton(btn, Icons.delete_outline, () => widget.onDelete?.call(layer.id)),
        ),
      ],
    );

    return Positioned(
      left: center.dx - boxW / 2 - pad,
      top: center.dy - boxH / 2 - pad,
      width: boxW + 2 * pad,
      height: boxH + 2 * pad,
      child: Transform.rotate(angle: layer.rotation, child: overlay),
    );
  }

  /// The item to take timing from, the time, and the slide length, when the item is
  /// animating (playing, or shown in the Animate panel's live demo). Null otherwise.
  (Layer, int, int)? _timing(Layer layer) {
    final demo = widget.demoMs;
    if (widget.demoId == layer.id && demo != null) {
      final plan = demoPlan(layer);
      return (plan.layer, demo, math.max(widget.scene.durationMs, plan.total));
    }
    final p = widget.previewMs;
    if (p != null) return (layer, p, widget.scene.durationMs);
    return null;
  }

  Widget _buildHand(Layer layer, int ms, double width, double height) {
    final spec = handById(layer.hand);
    if (spec == null) return const SizedBox.shrink();
    final st = handStateAt(layer, ms - (layer.startMs + layer.animStartMs));
    if (!st.visible) return const SizedBox.shrink();
    final hw = width * kHandWidthFrac;
    final hh = hw / spec.aspect;
    return Positioned(
      left: st.tipX * width - spec.tipX * hw,
      top: st.tipY * height - spec.tipY * hh,
      width: hw,
      height: hh,
      child: IgnorePointer(
        child: Image.asset(spec.asset, fit: BoxFit.fill, gaplessPlayback: true),
      ),
    );
  }

  Widget _buildLayer(Layer layer, double width, double height) {
    final timing = _timing(layer);
    final handSpec = layer.hand.isEmpty ? null : handById(layer.hand);
    final revealMs = (timing != null &&
            handSpec == null &&
            layer.type == 'text' &&
            layer.textAnim != 'none')
        ? timing.$2 - (timing.$1.startMs + timing.$1.animStartMs)
        : null;
    Widget content = LayerContent(layer: layer, revealMs: revealMs);
    if (handSpec != null && timing != null) {
      final hs = handStateAt(timing.$1, timing.$2 - (timing.$1.startMs + timing.$1.animStartMs));
      if (hs.reveal < 1) {
        content = ClipRect(clipper: FractionClipper(hs.reveal), child: content);
      }
    }

    if (widget.interactive && !layer.id.startsWith('overlay_')) {
      content = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onSelect?.call(layer.id),
        onScaleStart: (details) {
          widget.onSelect?.call(layer.id);
          _guideOn();
          _startFocal = details.focalPoint;
          _startCx = layer.cx;
          _startCy = layer.cy;
          _startW = layer.w;
          _startH = layer.h;
          _startRotation = layer.rotation;
        },
        onScaleUpdate: (details) {
          final start = _startFocal;
          if (start == null) return;
          setState(() {
            final rawX = (_startCx + (details.focalPoint.dx - start.dx) / width).clamp(0.0, 1.0).toDouble();
            final rawY = (_startCy + (details.focalPoint.dy - start.dy) / height).clamp(0.0, 1.0).toDouble();
            final others = widget.scene.layers.where((l) => l.id != layer.id);
            final sx = _snap(rawX, [0.5, ...others.map((l) => l.cx)]);
            final sy = _snap(rawY, [0.5, ...others.map((l) => l.cy)]);
            layer.cx = sx.$1;
            layer.cy = sy.$1;
            _snapX = sx.$2;
            _snapY = sy.$2;
            _guiding = true;
            layer.w = (_startW * details.scale).clamp(0.03, 1.6).toDouble();
            layer.h = (_startH * details.scale).clamp(0.03, 1.6).toDouble();
            layer.rotation = _startRotation + details.rotation;
          });
        },
        onScaleEnd: (_) {
          _startFocal = null;
          _guideOff();
          widget.onCommit?.call();
        },
        child: content,
      );
    } else if (widget.tapSelect) {
      content = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => widget.onSelect?.call(layer.id),
        child: content,
      );
    } else {
      content = IgnorePointer(child: content);
    }

    Widget placed = Transform.rotate(angle: layer.rotation, child: content);
    if (timing != null) {
      final frame = layerFrame(timing.$1, timing.$2, timing.$3);
      if (frame.alpha <= 0) return const SizedBox.shrink();
      placed = Opacity(
        opacity: frame.alpha.clamp(0.0, 1.0).toDouble(),
        child: Transform.translate(
          offset: Offset(frame.dx * width, frame.dy * height),
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..rotateZ(frame.rot * math.pi / 180)
              ..scale(frame.scale * frame.scaleX, frame.scale, 1.0),
            child: placed,
          ),
        ),
      );
    } else if (widget.ghostAtMs != null) {
      final t = widget.ghostAtMs!;
      final end = layerEndMs(layer, widget.scene.durationMs);
      if (t < layer.startMs || t >= end) {
        // Items that are not on screen at this moment are not shown at all.
        return const SizedBox.shrink();
      }
    }

    return Positioned(
      left: (layer.cx - layer.w / 2) * width,
      top: (layer.cy - layer.h / 2) * height,
      width: layer.w * width,
      height: layer.h * height,
      child: placed,
    );
  }
}

/// Frames of video clips, cached so a thumbnail is only read once.
class VideoFrames {
  VideoFrames._();
  static final Map<String, Future<String?>> _cache = {};

  static Future<String?> frame(String path, int ms) {
    return _cache.putIfAbsent('$path@$ms', () async {
      try {
        return await KainuwaEncoder.videoFrame(path, ms);
      } catch (_) {
        return null;
      }
    });
  }
}

/// Shows a video as a quick series of frames while the lesson plays.
class LiveVideoFrame extends StatefulWidget {
  const LiveVideoFrame({super.key, required this.path, required this.ms, this.fill = false});

  final String path;
  final int ms;
  final bool fill;

  @override
  State<LiveVideoFrame> createState() => _LiveVideoFrameState();
}

class _LiveVideoFrameState extends State<LiveVideoFrame> {
  Uint8List? _bytes;
  bool _busy = false;
  int _wanted = 0;

  @override
  void initState() {
    super.initState();
    _request();
  }

  @override
  void didUpdateWidget(LiveVideoFrame old) {
    super.didUpdateWidget(old);
    _request();
  }

  void _request() {
    _wanted = (widget.ms ~/ 100) * 100;
    if (!_busy) _fetch();
  }

  Future<void> _fetch() async {
    _busy = true;
    var last = -1;
    while (mounted) {
      final target = _wanted;
      if (target != last) {
        last = target;
        Uint8List? data;
        try {
          data = await KainuwaEncoder.videoFrameBytes(widget.path, target);
        } catch (_) {
          data = null;
        }
        if (!mounted) break;
        if (data != null) setState(() => _bytes = data);
      }
      if (_wanted == last) break;
    }
    _busy = false;
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    return ColoredBox(
      color: Colors.black,
      child: bytes == null
          ? const SizedBox.expand()
          : Image.memory(
              bytes,
              fit: widget.fill ? BoxFit.cover : BoxFit.contain,
              width: double.infinity,
              height: double.infinity,
              gaplessPlayback: true,
            ),
    );
  }
}

/// Plays a video smoothly through a native texture, with a still frame underneath.
class LiveVideo extends StatefulWidget {
  const LiveVideo({super.key, required this.path, required this.ms, this.fill = false});

  final String path;
  final int ms;
  final bool fill;

  @override
  State<LiveVideo> createState() => _LiveVideoState();
}

class _LiveVideoState extends State<LiveVideo> {
  /// There is one native player. Only the newest video widget may close it, otherwise the old
  /// slide's video, disposed after the next slide's video opened, would shut the new one.
  static _LiveVideoState? _active;

  int? _texture;
  double _aspect = 16 / 9;
  bool _failed = false;
  bool _opening = false;
  bool _owner = false;
  Timer? _timer;
  late final int _startMs;
  late final DateTime _startedAt;

  @override
  void initState() {
    super.initState();
    _startMs = widget.ms;
    _startedAt = DateTime.now();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current = ModalRoute.of(context)?.isCurrent ?? true;
    if (current && _texture == null && !_opening && !_failed) {
      _open();
    } else if (!current && _owner) {
      _close();
    }
  }

  Future<void> _open() async {
    _opening = true;
    _active = this;
    try {
      final r = await KainuwaEncoder.videoOpen(widget.path, widget.ms);
      if (_active != this) {
        // A newer video took over the player while this one was opening.
        _opening = false;
        return;
      }
      if (!mounted) {
        _active = null;
        await KainuwaEncoder.videoClose();
        _opening = false;
        return;
      }
      if (r == null) {
        setState(() => _failed = true);
      } else {
        _owner = true;
        setState(() {
          _texture = r['textureId'];
          _aspect = r['width']! / r['height']!;
        });
        await KainuwaEncoder.videoPlay(widget.ms + 30);
        if (!mounted) return;
        _timer = Timer.periodic(const Duration(milliseconds: 400), (_) => _checkDrift());
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
    _opening = false;
  }

  Future<void> _checkDrift() async {
    if (!_owner || !mounted || _active != this) return;
    try {
      final pos = await KainuwaEncoder.videoPosition();
      if (pos < 0 || !_owner) return;
      final drift = pos - (widget.ms + 30);
      if (drift.abs() > 600) {
        // Far out of step: jump.
        await KainuwaEncoder.videoSeek(widget.ms + 30);
        await KainuwaEncoder.videoSpeed(1.0);
      } else if (drift.abs() > 50) {
        // A little out of step: play slightly slower or faster until it catches up,
        // which looks smoother than jumping.
        await KainuwaEncoder.videoSpeed(drift > 0 ? 0.92 : 1.08);
      } else {
        await KainuwaEncoder.videoSpeed(1.0);
      }
    } catch (_) {}
  }

  void _close() {
    _timer?.cancel();
    _timer = null;
    if (_owner) {
      _owner = false;
      if (_active == this) {
        _active = null;
        KainuwaEncoder.videoClose();
      }
    }
    if (mounted) setState(() => _texture = null);
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (_owner) {
      _owner = false;
      if (_active == this) {
        _active = null;
        KainuwaEncoder.videoClose();
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return LiveVideoFrame(path: widget.path, ms: widget.ms, fill: widget.fill);
    }
    final id = _texture;
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (id == null)
            FutureBuilder<String?>(
              future: VideoFrames.frame(widget.path, _startMs),
              builder: (context, snap) {
                final file = snap.data;
                if (file == null) return const SizedBox.expand();
                return Image.file(File(file),
                    fit: widget.fill ? BoxFit.cover : BoxFit.contain,
                    width: double.infinity,
                    height: double.infinity);
              },
            )
          else if (widget.fill)
            ClipRect(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _aspect * 1000,
                  height: 1000,
                  child: Texture(textureId: id),
                ),
              ),
            )
          else
            Center(
              child: AspectRatio(
                aspectRatio: _aspect,
                child: Texture(textureId: id),
              ),
            ),
        ],
      ),
    );
  }
}

/// Where the phone body and its screen sit, for a stage of the given size.
class PhoneGeometry {
  PhoneGeometry(double w, double h, double scale) {
    final s = scale.clamp(0.4, 1.0).toDouble();
    bodyH = h * s;
    bezel = bodyH * 0.025;
    screenH = bodyH - 2 * bezel;
    screenW = screenH * 9 / 16;
    bodyW = screenW + 2 * bezel;
    radius = bodyH * 0.06;
    body = Rect.fromCenter(center: Offset(w / 2, h / 2), width: bodyW, height: bodyH);
    screen = Rect.fromCenter(center: Offset(w / 2, h / 2), width: screenW, height: screenH);
  }

  late final double bodyH, bezel, screenH, screenW, bodyW, radius;
  late final Rect body, screen;

  RRect get bodyRRect => RRect.fromRectAndRadius(body, Radius.circular(radius));
  RRect get screenRRect => RRect.fromRectAndRadius(screen, Radius.circular(radius * 0.8));
}

class PhoneHoleClipper extends CustomClipper<Path> {
  PhoneHoleClipper(this.geo);
  final PhoneGeometry geo;

  @override
  Path getClip(Size size) {
    return Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(geo.screenRRect);
  }

  @override
  bool shouldReclip(covariant PhoneHoleClipper old) => false;
}

/// The phone body (and a small speaker notch), drawn over the slide background.
class PhoneBody extends StatelessWidget {
  const PhoneBody({super.key, required this.geo, required this.light});

  final PhoneGeometry geo;
  final bool light;

  @override
  Widget build(BuildContext context) {
    final color = light ? const Color(0xFFF2F2F5) : const Color(0xFF111114);
    return Stack(children: [
      Positioned.fromRect(
        rect: geo.body,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(geo.radius),
            boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 14, offset: Offset(0, 4))],
          ),
        ),
      ),
    ]);
  }
}

class PhoneNotch extends StatelessWidget {
  const PhoneNotch({super.key, required this.geo});

  final PhoneGeometry geo;

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      Positioned(
        left: geo.body.center.dx - geo.screenW * 0.12,
        top: geo.screen.top + geo.bezel * 0.5,
        width: geo.screenW * 0.24,
        height: geo.bezel * 1.1,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF111114),
            borderRadius: BorderRadius.circular(geo.bezel),
          ),
        ),
      ),
    ]);
  }
}

class SceneBackground extends StatelessWidget {
  const SceneBackground({super.key, required this.scene, this.liveMs, this.noVideo = false, this.videoOnly = false});

  final Scene scene;
  final bool noVideo;
  final bool videoOnly;

  /// While playing: the time inside this slide, so a video shows moving frames.
  final int? liveMs;

  @override
  Widget build(BuildContext context) {
    if (scene.hasVideo && scene.phoneFrame && !noVideo && !videoOnly) {
      return LayoutBuilder(builder: (context, c) {
        final geo = PhoneGeometry(c.maxWidth, c.maxHeight, scene.phoneScale);
        return Stack(children: [
          Positioned.fill(child: SceneBackground(scene: scene, noVideo: true)),
          PhoneBody(geo: geo, light: scene.phoneLight),
          Positioned.fromRect(
            rect: geo.screen,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(geo.radius * 0.8),
              child: SceneBackground(scene: scene, liveMs: liveMs, videoOnly: true),
            ),
          ),
          PhoneNotch(geo: geo),
        ]);
      });
    }
    final showVideo = scene.hasVideo && !noVideo;
    if (showVideo && liveMs != null) {
      return LiveVideo(
        key: ValueKey('live-${scene.id}'),
        path: scene.videoPath,
        ms: scene.videoStartMs + liveMs!,
        fill: scene.videoFill && !scene.phoneFrame,
      );
    }
    if (showVideo) {
      return ColoredBox(
        color: Colors.black,
        child: FutureBuilder<String?>(
          future: VideoFrames.frame(scene.videoPath, scene.videoStartMs),
          builder: (context, snap) {
            final file = snap.data;
            if (file == null) {
              return const Center(child: Icon(Icons.videocam, color: Colors.white54, size: 32));
            }
            return Image.file(
              File(file),
              fit: scene.videoFill && !scene.phoneFrame ? BoxFit.cover : BoxFit.contain,
              width: double.infinity,
              height: double.infinity,
              gaplessPlayback: true,
            );
          },
        ),
      );
    }
    switch (scene.bgType) {
      case 'asset':
        return Image.asset(
          scene.bgValue,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          gaplessPlayback: true,
        );
      case 'file':
        return Image.file(
          File(scene.bgValue),
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFFDDDDDD)),
        );
      default:
        return ColoredBox(color: Color(int.tryParse(scene.bgValue) ?? 0xFFFFFFFF));
    }
  }
}

/// The text style of a text item, drawn at [size] (the slide scales it to fit the box).
/// The text with the chosen parts in their own colours (the rest keeps the item colour).
TextSpan layerTextSpan(Layer layer, TextStyle base, {String? text}) {
  final t = text ?? layer.text;
  if (layer.colorSpans.isEmpty || t.isEmpty) return TextSpan(text: t, style: base);
  final colors = List<int?>.filled(t.length, null);
  for (final s in layer.colorSpans) {
    if (s.length < 3) continue;
    for (var i = math.max(0, s[0]); i < math.min(t.length, s[1]); i++) {
      colors[i] = s[2];
    }
  }
  final parts = <TextSpan>[];
  var start = 0;
  while (start < t.length) {
    var end = start + 1;
    while (end < t.length && colors[end] == colors[start]) {
      end++;
    }
    final c = colors[start];
    parts.add(TextSpan(
      text: t.substring(start, end),
      style: c == null ? null : TextStyle(color: Color(c), decorationColor: Color(c)),
    ));
    start = end;
  }
  return TextSpan(style: base, children: parts);
}

/// Moves the coloured parts along when the text is edited.
List<List<int>> shiftColorSpans(String oldText, String newText, List<List<int>> spans) {
  if (spans.isEmpty) return spans;
  final maxCommon = math.min(oldText.length, newText.length);
  var prefix = 0;
  while (prefix < maxCommon && oldText.codeUnitAt(prefix) == newText.codeUnitAt(prefix)) {
    prefix++;
  }
  var suffix = 0;
  while (suffix < maxCommon - prefix &&
      oldText.codeUnitAt(oldText.length - 1 - suffix) == newText.codeUnitAt(newText.length - 1 - suffix)) {
    suffix++;
  }
  final delta = newText.length - oldText.length;
  final added = newText.length - prefix - suffix;
  int map(int p, bool isEnd) {
    if (p <= prefix) return p;
    if (p >= oldText.length - suffix) return p + delta;
    return isEnd ? prefix + added : prefix;
  }

  final out = <List<int>>[];
  for (final s in spans) {
    if (s.length < 3) continue;
    final a = map(s[0], false);
    final b = map(s[1], true);
    if (b > a) out.add([a, b, s[2]]);
  }
  return out;
}

TextStyle layerTextStyle(Layer layer, {double size = 100}) {
  final color = Color(layer.color);
  final light = color.computeLuminance() > 0.7 && !layer.bgBox;
  final decorations = <TextDecoration>[
    if (layer.underline) TextDecoration.underline,
    if (layer.strike) TextDecoration.lineThrough,
  ];
  return TextStyle(
    fontSize: size,
    height: layer.lineHeight,
    fontWeight: layer.bold ? FontWeight.w800 : FontWeight.w500,
    fontStyle: layer.italic ? FontStyle.italic : FontStyle.normal,
    // The Default font stays the phone's own font, whatever font the app itself uses.
    fontFamily: layer.fontFamily.isEmpty ? 'sans-serif' : layer.fontFamily,
    letterSpacing: layer.letterSpacing * size / 72,
    decoration: decorations.isEmpty ? TextDecoration.none : TextDecoration.combine(decorations),
    decorationColor: color,
    color: color,
    shadows: light ? const [Shadow(color: Color(0x66000000), blurRadius: 8)] : null,
  );
}

/// Arabic text must be laid out right to left, otherwise the stop signs between words
/// make the bidi algorithm reorder whole chunks of a verse.
TextDirection layerTextDirection(Layer layer) {
  return RegExp(r'[\u0600-\u06FF\u0750-\u077F\uFB50-\uFDFF\uFE70-\uFEFF]').hasMatch(layer.text)
      ? TextDirection.rtl
      : TextDirection.ltr;
}

TextAlign layerTextAlign(Layer layer) {
  switch (layer.align) {
    case 'left':
      return TextAlign.left;
    case 'right':
      return TextAlign.right;
    case 'justify':
      return TextAlign.justify;
    default:
      return TextAlign.center;
  }
}

const double _kBoxPadX = 24;
const double _kBoxPadY = 8;

/// Natural width and height of a text item at a 100 px font, box padding included.
Size measureLayerText(Layer layer) {
  final painter = TextPainter(
    text: TextSpan(text: layer.text.isEmpty ? ' ' : layer.text, style: layerTextStyle(layer)),
    textDirection: layerTextDirection(layer),
    textAlign: layerTextAlign(layer),
  )..layout();
  var w = painter.width;
  var h = painter.height;
  painter.dispose();
  if (layer.bgBox) {
    w += _kBoxPadX * 2;
    h += _kBoxPadY * 2;
  }
  return Size(math.max(1, w), math.max(1, h));
}

double layerTextAspect(Layer layer) {
  final size = measureLayerText(layer);
  return size.width / size.height;
}

/// Text size in pixels of the 1280 x 720 video.
double layerTextSizePx(Layer layer) {
  final size = measureLayerText(layer);
  return layer.h * Stage.h * 100 / size.height;
}

/// Changes the box so the text has the given size in pixels of the 1280 x 720 video.
void setLayerTextSizePx(Layer layer, double px) {
  final size = measureLayerText(layer);
  final scale = px / 100;
  layer.h = (size.height * scale / Stage.h).clamp(0.02, 1.6).toDouble();
  layer.w = (size.width * scale / Stage.w).clamp(0.02, 1.6).toDouble();
}

/// Re-fits the box to the text after the text or its style changed, keeping the
/// text size.
void refitLayerText(Layer layer, double keepSizePx) {
  setLayerTextSizePx(layer, keepSizePx);
}

/// What a single layer looks like, without any gestures.
class LayerContent extends StatelessWidget {
  const LayerContent({super.key, required this.layer, this.revealMs, this.clipFraction});

  final Layer layer;

  /// For text with a text animation: milliseconds since the animation started.
  final int? revealMs;

  /// Hand reveal in the video export: show only the left part (0 to 1), null for all.
  final double? clipFraction;

  bool get _needsShaping =>
      (layer.type == 'asset' || layer.type == 'image') &&
      (layer.cropL > 0 || layer.cropT > 0 || layer.cropR > 0 || layer.cropB > 0 || layer.mask != 'none');

  /// The picture of an icon or image item, drawn with the given fit.
  Widget _pictureWidget(BoxFit fit) {
    if (layer.type == 'asset') {
      return Image.asset(layer.path, fit: fit, gaplessPlayback: true);
    }
    final picture = Image.file(
      File(layer.path),
      fit: fit,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => const ColoredBox(
        color: Color(0xFFDDDDDD),
        child: Icon(Icons.broken_image_outlined),
      ),
    );
    if (layer.shape == 'tint') {
      return ColorFiltered(
        colorFilter: ColorFilter.mode(Color(layer.color), BlendMode.srcIn),
        child: picture,
      );
    }
    return picture;
  }

  Widget _body() {
    final color = Color(layer.color);
    switch (layer.type) {
      case 'text':
        Widget text = (revealMs != null && layer.textAnim != 'none')
            ? TextRevealView(layer: layer, timeMs: revealMs!)
            : Text.rich(
                layerTextSpan(layer, layerTextStyle(layer)),
                textAlign: layerTextAlign(layer),
                textDirection: layerTextDirection(layer),
              );
        if (layer.gradOn) {
          final a = layer.gradAngle * math.pi / 180;
          text = ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (rect) => LinearGradient(
              begin: Alignment(-math.cos(a), -math.sin(a)),
              end: Alignment(math.cos(a), math.sin(a)),
              colors: [Color(layer.gradC1), Color(layer.gradC2)],
            ).createShader(rect),
            child: text,
          );
        }
        if (layer.bgBox) {
          text = Container(
            padding: const EdgeInsets.symmetric(horizontal: _kBoxPadX, vertical: _kBoxPadY),
            decoration: BoxDecoration(
              color: Color(layer.bgColor),
              borderRadius: BorderRadius.circular(18),
            ),
            child: text,
          );
        }
        return FittedBox(fit: BoxFit.contain, child: text);
      case 'asset':
      case 'image':
        if (_needsShaping) {
          return _ShapedPicture(layer: layer, builder: _pictureWidget);
        }
        return _pictureWidget(BoxFit.contain);
      case 'shape':
        switch (layer.shape) {
          case 'circle':
            return ClipOval(child: ColoredBox(color: color));
          case 'round':
            return LayoutBuilder(
              builder: (context, c) => ClipRRect(
                borderRadius: BorderRadius.circular(math.min(c.maxWidth, c.maxHeight) * 0.18),
                child: ColoredBox(color: color),
              ),
            );
          default:
            return ColoredBox(color: color);
        }
      default:
        return const SizedBox.shrink();
    }
  }

  /// A soft copy of the item behind it, in the shadow colour, moved and blurred as set.
  Widget _withShadow(Widget body) {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth.isFinite ? c.maxWidth : 100.0;
      final h = c.maxHeight.isFinite ? c.maxHeight : 100.0;
      final unit = math.min(w, h);
      final sigma = layer.shadowBlur * unit;
      Widget copy = ColorFiltered(
        colorFilter: ColorFilter.mode(Color(layer.shadowColor), BlendMode.srcIn),
        child: body,
      );
      if (sigma >= 0.3) {
        copy = ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.decal),
          child: copy,
        );
      }
      return Stack(
        clipBehavior: Clip.none,
        fit: StackFit.passthrough,
        children: [
          Positioned.fill(
            child: Transform.translate(offset: Offset(layer.shadowX * unit, layer.shadowY * unit), child: copy),
          ),
          body,
        ],
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    var body = _body();
    final clip = clipFraction;
    if (clip != null && clip < 1) {
      body = ClipRect(clipper: FractionClipper(clip), child: body);
    }
    if (layer.shadowOn) body = _withShadow(body);
    if (layer.opacity >= 0.999) return body;
    return Opacity(opacity: layer.opacity.clamp(0.0, 1.0).toDouble(), child: body);
  }
}

/// Where the whole picture and its visible part sit inside the item box.
class _PicGeom {
  _PicGeom(Size box, Layer l) {
    final boxAspect = box.width / math.max(1.0, box.height);
    final a = l.srcAspect > 0 ? l.srcAspect : boxAspect;
    double fw;
    double fh;
    if (boxAspect > a) {
      fh = box.height;
      fw = fh * a;
    } else {
      fw = box.width;
      fh = fw / a;
    }
    final vw = (1 - l.cropL - l.cropR).clamp(0.05, 1.0).toDouble();
    final vh = (1 - l.cropT - l.cropB).clamp(0.05, 1.0).toDouble();
    final visW = fw * vw;
    final visH = fh * vh;
    final s = math.min(box.width / visW, box.height / visH);
    final dispW = visW * s;
    final dispH = visH * s;
    final fullW = fw * s;
    final fullH = fh * s;
    final dx = (box.width - dispW) / 2;
    final dy = (box.height - dispH) / 2;
    visible = Rect.fromLTWH(dx, dy, dispW, dispH);
    full = Rect.fromLTWH(dx - l.cropL * fullW, dy - l.cropT * fullH, fullW, fullH);
  }

  late final Rect visible;
  late final Rect full;
}

/// The outline of a mask inside [r].
Path _maskPath(String mask, Rect r) {
  final path = Path();
  final side = math.min(r.width, r.height);
  final center = r.center;
  switch (mask) {
    case 'circle':
      path.addOval(Rect.fromCenter(center: center, width: side, height: side));
      break;
    case 'round':
      path.addRRect(RRect.fromRectAndRadius(r, Radius.circular(side * 0.18)));
      break;
    case 'diamond':
      path.moveTo(center.dx, r.top);
      path.lineTo(r.right, center.dy);
      path.lineTo(center.dx, r.bottom);
      path.lineTo(r.left, center.dy);
      path.close();
      break;
    case 'star':
      {
        final outer = side / 2;
        final inner = outer * 0.45;
        for (var i = 0; i < 10; i++) {
          final radius = i.isEven ? outer : inner;
          final angle = -math.pi / 2 + i * math.pi / 5;
          final x = center.dx + radius * math.cos(angle);
          final y = center.dy + radius * math.sin(angle);
          if (i == 0) {
            path.moveTo(x, y);
          } else {
            path.lineTo(x, y);
          }
        }
        path.close();
      }
      break;
    case 'heart':
      {
        final w = r.width;
        final h = r.height;
        path.moveTo(r.left + w * 0.5, r.top + h * 0.95);
        path.cubicTo(r.left - w * 0.15, r.top + h * 0.55, r.left + w * 0.02, r.top - h * 0.02,
            r.left + w * 0.5, r.top + h * 0.28);
        path.cubicTo(r.right - w * 0.02, r.top - h * 0.02, r.right + w * 0.15, r.top + h * 0.55,
            r.left + w * 0.5, r.top + h * 0.95);
        path.close();
      }
      break;
    default:
      path.addRect(r);
  }
  return path;
}

class _MaskClipper extends CustomClipper<Path> {
  _MaskClipper(this.mask, this.rect);

  final String mask;
  final Rect rect;

  @override
  Path getClip(Size size) => _maskPath(mask, rect);

  @override
  bool shouldReclip(covariant _MaskClipper oldClipper) =>
      oldClipper.mask != mask || oldClipper.rect != rect;
}

/// A picture that is cropped and/or cut to a mask shape.
class _ShapedPicture extends StatelessWidget {
  const _ShapedPicture({required this.layer, required this.builder});

  final Layer layer;
  final Widget Function(BoxFit fit) builder;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final g = _PicGeom(Size(c.maxWidth, c.maxHeight), layer);
        final picture = Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: g.full.left,
              top: g.full.top,
              width: g.full.width,
              height: g.full.height,
              child: builder(BoxFit.fill),
            ),
          ],
        );
        return ClipPath(clipper: _MaskClipper(layer.mask, g.visible), child: picture);
      },
    );
  }
}


/// Vertical and horizontal guide lines through the item's centre, plus the slide's centre lines.
class _GuidePainter extends CustomPainter {
  _GuidePainter(this.cx, this.cy, this.snapX, this.snapY);

  final double cx;
  final double cy;
  final bool snapX;
  final bool snapY;

  void _dashed(Canvas canvas, Offset a, Offset b, Paint paint, double dash, double gap) {
    final total = (b - a).distance;
    if (total <= 0) return;
    final dir = (b - a) / total;
    var d = 0.0;
    while (d < total) {
      final e = math.min(total, d + dash);
      canvas.drawLine(a + dir * d, a + dir * e, paint);
      d = e + gap;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final faint = Paint()
      ..color = const Color(0x55FFFFFF)
      ..strokeWidth = 1;
    _dashed(canvas, Offset(size.width / 2, 0), Offset(size.width / 2, size.height), faint, 4, 5);
    _dashed(canvas, Offset(0, size.height / 2), Offset(size.width, size.height / 2), faint, 4, 5);
    final x = cx * size.width;
    final y = cy * size.height;
    final vp = Paint()
      ..color = snapX ? const Color(0xFFF6C101) : const Color(0xFFB69CFF)
      ..strokeWidth = snapX ? 2 : 1.4;
    final hp = Paint()
      ..color = snapY ? const Color(0xFFF6C101) : const Color(0xFFB69CFF)
      ..strokeWidth = snapY ? 2 : 1.4;
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), vp);
    canvas.drawLine(Offset(0, y), Offset(size.width, y), hp);
  }

  @override
  bool shouldRepaint(_GuidePainter old) =>
      old.cx != cx || old.cy != cy || old.snapX != snapX || old.snapY != snapY;
}

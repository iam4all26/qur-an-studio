import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:kainuwa_encoder/kainuwa_encoder.dart';

import '../models.dart';
import '../theme.dart';
import '../widgets.dart';

class DrawingResult {
  const DrawingResult(this.path, this.aspect);
  final String path;
  final double aspect;
}

/// Free hand drawing. Returns a transparent PNG cut to the drawn part, or null if cancelled.
Future<DrawingResult?> showDrawingScreen(BuildContext context) {
  return Navigator.of(context).push<DrawingResult>(
    MaterialPageRoute(fullscreenDialog: true, builder: (_) => const _DrawingScreen()),
  );
}

class _Stroke {
  _Stroke(this.color, this.width, this.erase);
  final Color color;
  final double width;
  final bool erase;
  final List<Offset> points = [];
}

class _DrawingPainter extends CustomPainter {
  _DrawingPainter(this.strokes, {this.repaint});

  final List<_Stroke> strokes;
  final Listenable? repaint;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(const Rect.fromLTWH(-4000, -4000, 12000, 12000), Paint());
    for (final s in strokes) {
      final paint = Paint()
        ..color = s.color
        ..strokeWidth = s.width
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true;
      if (s.erase) paint.blendMode = BlendMode.clear;
      if (s.points.length == 1) {
        canvas.drawCircle(
          s.points.first,
          s.width / 2,
          Paint()
            ..color = s.color
            ..blendMode = s.erase ? BlendMode.clear : BlendMode.srcOver,
        );
        continue;
      }
      final path = Path()..moveTo(s.points.first.dx, s.points.first.dy);
      for (var i = 1; i < s.points.length - 1; i++) {
        final mid = Offset(
          (s.points[i].dx + s.points[i + 1].dx) / 2,
          (s.points[i].dy + s.points[i + 1].dy) / 2,
        );
        path.quadraticBezierTo(s.points[i].dx, s.points[i].dy, mid.dx, mid.dy);
      }
      path.lineTo(s.points.last.dx, s.points.last.dy);
      canvas.drawPath(path, paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _DrawingPainter old) => true;
}

class _DrawingScreen extends StatefulWidget {
  const _DrawingScreen();

  @override
  State<_DrawingScreen> createState() => _DrawingScreenState();
}

class _DrawingScreenState extends State<_DrawingScreen> {
  final List<_Stroke> _strokes = [];
  final List<_Stroke> _undone = [];
  Color _color = const Color(0xFFFFFFFF);
  double _width = 8;
  bool _erase = false;
  bool _busy = false;
  Size _size = const Size(100, 100);

  static const _palette = <int>[
    0xFFFFFFFF,
    0xFF000000,
    0xFFE53935,
    0xFFFFB300,
    0xFFFDD835,
    0xFF43A047,
    0xFF1E88E5,
    0xFF8E24AA,
    0xFFEC407A,
  ];

  void _down(Offset p) {
    final s = _Stroke(_color, _erase ? _width * 2 : _width, _erase)..points.add(p);
    setState(() {
      _strokes.add(s);
      _undone.clear();
    });
  }

  void _move(Offset p) {
    if (_strokes.isEmpty) return;
    setState(() => _strokes.last.points.add(p));
  }

  Future<void> _done() async {
    final drawn = _strokes.where((s) => !s.erase).toList();
    if (drawn.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _busy = true);
    try {
      var rect = Rect.fromPoints(drawn.first.points.first, drawn.first.points.first);
      for (final s in drawn) {
        for (final p in s.points) {
          rect = rect.expandToInclude(Rect.fromCircle(center: p, radius: s.width / 2 + 1));
        }
      }
      rect = rect.intersect(Offset.zero & _size);
      if (rect.width < 4 || rect.height < 4) {
        Navigator.of(context).pop();
        return;
      }
      final scale = math.min(2.5, 1600 / math.max(rect.width, rect.height));
      final w = (rect.width * scale).ceil();
      final h = (rect.height * scale).ceil();
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.scale(scale);
      canvas.translate(-rect.left, -rect.top);
      _DrawingPainter(_strokes).paint(canvas, _size);
      final image = await recorder.endRecording().toImage(w, h);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) throw Exception('no image');
      final base = await KainuwaEncoder.filesDir();
      final dir = Directory('$base/kainuwa_data/drawings');
      if (!await dir.exists()) await dir.create(recursive: true);
      final file = File('${dir.path}/${newId()}.png');
      await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
      if (mounted) Navigator.of(context).pop(DrawingResult(file.path, w / h));
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not save the drawing.')));
      }
    }
  }

  Widget _toolButton(IconData icon, String tip, VoidCallback? onTap, {bool active = false}) {
    return IconButton(
      tooltip: tip,
      onPressed: onTap,
      icon: Icon(icon, color: active ? KColors.gold : Colors.white),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF15102B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF15102B),
        foregroundColor: Colors.white,
        title: const Text('Draw'),
        actions: [
          _toolButton(Icons.undo, 'Undo', _strokes.isEmpty
              ? null
              : () => setState(() => _undone.add(_strokes.removeLast()))),
          _toolButton(Icons.redo, 'Redo', _undone.isEmpty
              ? null
              : () => setState(() => _strokes.add(_undone.removeLast()))),
          _toolButton(Icons.delete_outline, 'Clear all', _strokes.isEmpty
              ? null
              : () => setState(() {
                    _strokes.clear();
                    _undone.clear();
                  })),
          TextButton(
            onPressed: _busy ? null : _done,
            child: const Text('Done', style: TextStyle(color: KColors.gold, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: LayoutBuilder(builder: (context, c) {
                  _size = Size(c.maxWidth, c.maxHeight);
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Stack(children: [
                      const Positioned.fill(child: ColoredBox(color: Color(0xFF2A2347))),
                      Positioned.fill(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onPanStart: (d) => _down(d.localPosition),
                          onPanUpdate: (d) => _move(d.localPosition),
                          child: CustomPaint(painter: _DrawingPainter(_strokes)),
                        ),
                      ),
                      if (_busy) const Positioned.fill(child: Center(child: CircularProgressIndicator())),
                    ]),
                  );
                }),
              ),
            ),
            Container(
              color: const Color(0xFF211A3F),
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      _toolButton(Icons.edit, 'Pen', () => setState(() => _erase = false), active: !_erase),
                      _toolButton(Icons.auto_fix_normal, 'Eraser', () => setState(() => _erase = true), active: _erase),
                      const SizedBox(width: 8),
                      for (final c in _palette)
                        GestureDetector(
                          onTap: () => setState(() {
                            _color = Color(c);
                            _erase = false;
                          }),
                          child: Container(
                            width: 30,
                            height: 30,
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              color: Color(c),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: !_erase && _color.value == c ? KColors.gold : Colors.white38,
                                width: !_erase && _color.value == c ? 3 : 1,
                              ),
                            ),
                          ),
                        ),
                      IconButton(
                        tooltip: 'More colours',
                        icon: const Icon(Icons.palette_outlined, color: Colors.white),
                        onPressed: () async {
                          final v = await pickColor(context, initial: _color.value, title: 'Pen colour');
                          if (v != null) setState(() {
                            _color = Color(v);
                            _erase = false;
                          });
                        },
                      ),
                    ]),
                  ),
                  Row(children: [
                    const Icon(Icons.brush, size: 18, color: Colors.white70),
                    Expanded(
                      child: Slider(
                        value: _width,
                        min: 2,
                        max: 40,
                        onChanged: (v) => setState(() => _width = v),
                      ),
                    ),
                    Text('${_width.round()}', style: const TextStyle(color: Colors.white70)),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

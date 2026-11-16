import 'dart:io';

import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';

/// Free crop: drag the corners, the edges or the whole frame over the picture.
/// Returns (left, right, top, bottom) as fractions cut from each side, or null if cancelled.
Future<(double, double, double, double)?> showCropEditor(
  BuildContext context, {
  required Layer layer,
  required double aspect,
}) {
  return Navigator.of(context).push<(double, double, double, double)>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _CropEditor(layer: layer, aspect: aspect > 0 ? aspect : 1.0),
    ),
  );
}

class _CropEditor extends StatefulWidget {
  const _CropEditor({required this.layer, required this.aspect});

  final Layer layer;
  final double aspect;

  @override
  State<_CropEditor> createState() => _CropEditorState();
}

class _CropEditorState extends State<_CropEditor> {
  // The kept part of the picture, as fractions (0 to 1) of its width and height.
  late double _l = widget.layer.cropL;
  late double _t = widget.layer.cropT;
  late double _r = 1 - widget.layer.cropR;
  late double _b = 1 - widget.layer.cropB;

  String _grab = '';
  static const double _min = 0.08;
  static const double _hit = 34;

  ImageProvider get _image => widget.layer.type == 'asset'
      ? AssetImage(widget.layer.path) as ImageProvider
      : FileImage(File(widget.layer.path));

  void _start(Offset p, Rect img) {
    final rect = Rect.fromLTRB(
      img.left + _l * img.width,
      img.top + _t * img.height,
      img.left + _r * img.width,
      img.top + _b * img.height,
    );
    final nearL = (p.dx - rect.left).abs() < _hit;
    final nearR = (p.dx - rect.right).abs() < _hit;
    final nearT = (p.dy - rect.top).abs() < _hit;
    final nearB = (p.dy - rect.bottom).abs() < _hit;
    final inX = p.dx > rect.left - _hit && p.dx < rect.right + _hit;
    final inY = p.dy > rect.top - _hit && p.dy < rect.bottom + _hit;
    var g = '';
    if (inY && nearT) g += 't';
    if (inY && nearB) g += 'b';
    if (inX && nearL) g += 'l';
    if (inX && nearR) g += 'r';
    if (g.isEmpty && rect.contains(p)) g = 'move';
    _grab = g;
  }

  void _update(Offset d, Rect img) {
    final dx = d.dx / img.width;
    final dy = d.dy / img.height;
    setState(() {
      if (_grab == 'move') {
        final w = _r - _l;
        final h = _b - _t;
        _l = (_l + dx).clamp(0.0, 1 - w).toDouble();
        _t = (_t + dy).clamp(0.0, 1 - h).toDouble();
        _r = _l + w;
        _b = _t + h;
        return;
      }
      if (_grab.contains('l')) _l = (_l + dx).clamp(0.0, _r - _min).toDouble();
      if (_grab.contains('r')) _r = (_r + dx).clamp(_l + _min, 1.0).toDouble();
      if (_grab.contains('t')) _t = (_t + dy).clamp(0.0, _b - _min).toDouble();
      if (_grab.contains('b')) _b = (_b + dy).clamp(_t + _min, 1.0).toDouble();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Crop'),
        actions: [
          TextButton(
            onPressed: () => setState(() {
              _l = 0;
              _t = 0;
              _r = 1;
              _b = 1;
            }),
            child: const Text('Reset'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop((_l, 1 - _r, _t, 1 - _b)),
            child: const Text('Done', style: TextStyle(color: KColors.gold, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _livePreview(),
            Expanded(child: Padding(
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(builder: (context, c) {
            var w = c.maxWidth;
            var h = w / widget.aspect;
            if (h > c.maxHeight) {
              h = c.maxHeight;
              w = h * widget.aspect;
            }
            final img = Rect.fromLTWH((c.maxWidth - w) / 2, (c.maxHeight - h) / 2, w, h);
            final rect = Rect.fromLTRB(
              img.left + _l * img.width,
              img.top + _t * img.height,
              img.left + _r * img.width,
              img.top + _b * img.height,
            );
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (d) => _start(d.localPosition, img),
              onPanUpdate: (d) => _update(d.delta, img),
              child: Stack(children: [
                Positioned.fromRect(
                  rect: img,
                  child: DecoratedBox(
                    decoration: const BoxDecoration(color: Color(0xFF2A2A2A)),
                    child: Image(image: _image, fit: BoxFit.fill),
                  ),
                ),
                Positioned.fill(child: CustomPaint(painter: _CropPainter(img, rect))),
              ]),
            );
          }),
        )),
          ],
        ),
      ),
    );
  }

  /// A mirror of the result at the top, so the finger never hides what is being cut.
  Widget _livePreview() {
    return Container(
      height: 150,
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF333333)),
      ),
      child: LayoutBuilder(builder: (context, c) {
        final keepW = (_r - _l).clamp(0.01, 1.0).toDouble();
        final keepH = (_b - _t).clamp(0.01, 1.0).toDouble();
        final cropAspect = keepW * widget.aspect / keepH;
        var w = c.maxWidth - 16;
        var h = w / cropAspect;
        if (h > c.maxHeight - 16) {
          h = c.maxHeight - 16;
          w = h * cropAspect;
        }
        return Center(
          child: ClipRect(
            child: SizedBox(
              width: w,
              height: h,
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  Positioned(
                    left: -_l / keepW * w,
                    top: -_t / keepH * h,
                    width: w / keepW,
                    height: h / keepH,
                    child: Image(image: _image, fit: BoxFit.fill, gaplessPlayback: true),
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _CropPainter extends CustomPainter {
  _CropPainter(this.img, this.rect);

  final Rect img;
  final Rect rect;

  @override
  void paint(Canvas canvas, Size size) {
    final shade = Paint()..color = const Color(0xAA000000);
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(img)
      ..addRect(rect);
    canvas.drawPath(path, shade);
    final line = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(rect, line);
    final thin = Paint()
      ..color = const Color(0x88FFFFFF)
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      final x = rect.left + rect.width * i / 3;
      final y = rect.top + rect.height * i / 3;
      canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), thin);
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), thin);
    }
    final handle = Paint()..color = KColors.gold;
    final pts = [
      rect.topLeft,
      rect.topRight,
      rect.bottomLeft,
      rect.bottomRight,
      rect.topCenter,
      rect.bottomCenter,
      rect.centerLeft,
      rect.centerRight,
    ];
    for (final p in pts) {
      canvas.drawCircle(p, 9, handle);
    }
  }

  @override
  bool shouldRepaint(covariant _CropPainter old) => old.rect != rect || old.img != img;
}

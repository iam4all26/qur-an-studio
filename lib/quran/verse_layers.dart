import 'dart:math' as math;

import '../models.dart';
import '../scene_canvas.dart';
import 'templates.dart';

/// Builds the text layers of one verse scene.
///
/// A long verse is split into pages that follow each other inside the same scene, so the
/// text stays large and readable instead of shrinking. Page times follow the share of
/// words; this is an estimate, not a match to the recitation. Only line breaks are added
/// to the text; no letter or mark is changed.
List<Layer> buildVerseLayers({
  required String arabic,
  required String translation,
  required bool tall,
  required int durationMs,
  required QTemplate look,
  required String fontFamily,
}) {
  final aWords = arabic.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  final tWords = translation.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  final cap = tall ? 14 : 18;
  final pages = math.max(1, (aWords.length / cap).ceil());
  final layers = <Layer>[];

  for (var k = 0; k < pages; k++) {
    final a0 = (aWords.length * k / pages).round();
    final a1 = (aWords.length * (k + 1) / pages).round();
    final t0 = (tWords.length * k / pages).round();
    final t1 = (tWords.length * (k + 1) / pages).round();
    final start = pages == 1 ? 0 : (durationMs * a0 / aWords.length).round();
    final end = (pages == 1 || k == pages - 1) ? -1 : (durationMs * a1 / aWords.length).round();

    final arLayer = Layer(
      id: newId(),
      type: 'text',
      text: _wrap(aWords.sublist(a0, a1), tall ? 4 : 8),
      cy: 0.5,
      color: look.arabicColor,
      bold: false,
      lineHeight: 1.7,
      fontFamily: fontFamily,
    );
    _fit(arLayer, tall ? look.arabicTall : look.arabicWide, 0.9);

    Layer? trLayer;
    if (t1 > t0) {
      trLayer = Layer(
        id: newId(),
        type: 'text',
        text: _wrap(tWords.sublist(t0, t1), tall ? 5 : 11),
        cy: 0.72,
        color: look.translationColor,
        bold: false,
        lineHeight: 1.3,
      );
      _fit(trLayer, tall ? look.translationTall : look.translationWide, 0.88);
    }

    // Stack the two texts so they never overlap, then centre the stack in the frame.
    const gap = 0.04;
    final hA = arLayer.h;
    final hT = trLayer?.h ?? 0.0;
    var total = hA + (trLayer == null ? 0 : gap + hT);
    if (total > 0.88) {
      final f = 0.88 / total;
      for (final l in [arLayer, if (trLayer != null) trLayer]) {
        l.w = l.w * f;
        l.h = l.h * f;
      }
      total = 0.88;
    }
    final aH = arLayer.h;
    final top = (1 - total) / 2;
    arLayer.cy = top + aH / 2;
    if (trLayer != null) trLayer.cy = top + aH + gap + trLayer.h / 2;

    for (final l in [arLayer, if (trLayer != null) trLayer]) {
      l.startMs = start;
      l.endMs = end;
      if (pages > 1) l.animIn = 'fade';
      layers.add(l);
    }
  }
  return layers;
}

String _wrap(List<String> words, int perLine) {
  final lines = <String>[];
  for (var i = 0; i < words.length; i += perLine) {
    lines.add(words.sublist(i, math.min(words.length, i + perLine)).join(' '));
  }
  return lines.join('\n');
}

void _fit(Layer layer, double px, double maxW) {
  setLayerTextSizePx(layer, px);
  if (layer.w > maxW) {
    final f = maxW / layer.w;
    layer.w = maxW;
    layer.h = layer.h * f;
  }
}

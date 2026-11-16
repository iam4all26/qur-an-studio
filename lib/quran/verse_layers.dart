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
  String? footer,
}) {
  // Display only: QuranEnc footnote markers such as [1] are not shown in the video.
  translation = translation.replaceAll(RegExp(r'\s*\[\d+\]'), '');
  final aWords = arabic.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  final tWords = translation.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  final cap = tall ? 14 : 18;
  final pages = math.max(1, (aWords.length / cap).ceil());
  final layers = <Layer>[];
  // Translation page breaks: start from the word share, then move to the nearest
  // sentence or clause end so a page does not begin in the middle of a phrase.
  final tb = <int>[0];
  for (var k = 1; k < pages; k++) {
    tb.add(_snap(tWords, (tWords.length * k / pages).round(), tb[k - 1] + 1, tWords.length - (pages - k)));
  }
  tb.add(tWords.length);

  for (var k = 0; k < pages; k++) {
    final a0 = (aWords.length * k / pages).round();
    final a1 = (aWords.length * (k + 1) / pages).round();
    final t0 = tb[k];
    final t1 = tb[k + 1];
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
    final lo = 0.05;
    final hi = footer == null ? 0.95 : 0.87;
    final maxTotal = hi - lo;
    var total = hA + (trLayer == null ? 0 : gap + hT);
    if (total > maxTotal) {
      final f = maxTotal / total;
      for (final l in [arLayer, if (trLayer != null) trLayer]) {
        l.w = l.w * f;
        l.h = l.h * f;
      }
      total = maxTotal;
    }
    final aH = arLayer.h;
    final top = (lo + hi) / 2 - total / 2;
    arLayer.cy = top + aH / 2;
    if (trLayer != null) trLayer.cy = top + aH + gap + trLayer.h / 2;

    for (final l in [arLayer, if (trLayer != null) trLayer]) {
      l.startMs = start;
      l.endMs = end;
      if (pages > 1) l.animIn = 'fade';
      layers.add(l);
    }
  }
  if (footer != null && footer.isNotEmpty) {
    final fl = Layer(
      id: newId(),
      type: 'text',
      text: footer,
      cy: 0.93,
      color: look.translationColor,
      bold: false,
      lineHeight: 1.2,
    );
    _fit(fl, (tall ? look.translationTall : look.translationWide) * 0.8, 0.8);
    fl.cy = 0.93;
    layers.add(fl);
  }
  return layers;
}

int _snap(List<String> t, int idx, int lo, int hi) {
  if (hi < lo) return idx.clamp(0, t.length);
  final start = idx.clamp(lo, hi);
  final window = math.max(3, (t.length / 4).round());
  bool ends(int i) => i > 0 && i <= t.length && RegExp(r'[,.;:?!"\u201D)]$').hasMatch(t[i - 1]);
  for (var d = 0; d <= window; d++) {
    final a = start - d;
    final b = start + d;
    if (a >= lo && a <= hi && ends(a)) return a;
    if (b >= lo && b <= hi && ends(b)) return b;
  }
  return start;
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

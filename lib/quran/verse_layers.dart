import 'dart:math' as math;

import 'package:kainuwa_encoder/kainuwa_encoder.dart';

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
  String translationFont = '',
  String translationAlign = 'center',
  String? footer,
  int endMark = 0,
  List<int> pauses = const [],
}) {
  // Display only: QuranEnc footnote markers such as [1] are not shown in the video.
  translation = translation.replaceAll(RegExp(r'\s*\[\d+\]'), '');
  final aWords = arabic.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  // End-of-verse sign (U+06DD) followed by the verse number in Arabic-Indic digits.
  if (endMark > 0 && aWords.isNotEmpty) {
    const digits = ['\u0660', '\u0661', '\u0662', '\u0663', '\u0664', '\u0665', '\u0666', '\u0667', '\u0668', '\u0669'];
    final num = '$endMark'.split('').map((c) => digits[int.parse(c)]).join();
    aWords[aWords.length - 1] = '${aWords.last}\u00A0\u06DD$num';
  }
  final tWords = translation.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  final cap = tall ? 14 : 18;
  final trCap = tall ? 26 : 38;
  // A long recitation gets a new page about every 8 seconds, so a wrong guess about the
  // reading speed can never drift far from what is being recited.
  final byTime = durationMs > 20000 ? (durationMs / 8000).ceil() : 1;
  final pages = math.max(
      1,
      math.min(aWords.length,
          math.max(math.max((aWords.length / cap).ceil(), (tWords.length / trCap).ceil()), byTime)));
  // Recitation time follows the letters more closely than the words, so page times are
  // weighted by letters; they are then moved to the nearest real pause in the recording.
  int letters(String w) => w.runes.where((r) => !(r >= 0x064B && r <= 0x065F) && r != 0x0670 && r != 0x06DD).length;
  final aW = [for (final w in aWords) math.max(1, letters(w))];
  final aTotal = aW.fold<int>(0, (a, b) => a + b);
  // Word index where page k starts: the one whose letter share is closest to k / pages.
  final aStart = <int>[0];
  for (var k = 1; k < pages; k++) {
    final want = aTotal * k / pages;
    var acc = 0;
    var best = aStart.last + 1;
    for (var i = 0; i < aWords.length; i++) {
      acc += aW[i];
      if (acc >= want) {
        best = i + 1;
        break;
      }
    }
    final lo = aStart.last + 1;
    final hi = aWords.length - (pages - k);
    aStart.add(hi < lo ? lo : best.clamp(lo, hi).toInt());
  }
  aStart.add(aWords.length);
  // Start time of every page (ms), moved to the closest pause within a window.
  final pageMs = <int>[0];
  for (var k = 1; k < pages; k++) {
    var acc = 0;
    for (var i = 0; i < aStart[k]; i++) {
      acc += aW[i];
    }
    var t = (durationMs * acc / aTotal).round();
    final window = math.max(1200, (durationMs / pages * 0.35).round());
    var bestD = window + 1;
    for (final pz in pauses) {
      final d = (pz - t).abs();
      if (d < bestD) {
        bestD = d;
        if (d <= window) t = pz;
      }
    }
    // Every page stays on screen for at least 1.5 s, and so does the last one.
    final floor = pageMs.last + 1500;
    final ceil = durationMs - 1500 * (pages - k);
    pageMs.add(ceil < floor ? floor : t.clamp(floor, ceil).toInt());
  }
  pageMs.add(durationMs);
  final layers = <Layer>[];
  // Translation page breaks: start from the word share, then move to the nearest
  // sentence or clause end so a page does not begin in the middle of a phrase.
  final tb = <int>[0];
  for (var k = 1; k < pages; k++) {
    tb.add(_snap(tWords, (tWords.length * aStart[k] / aWords.length).round(), tb[k - 1] + 1, tWords.length - (pages - k)));
  }
  tb.add(tWords.length);

  for (var k = 0; k < pages; k++) {
    final a0 = aStart[k];
    final a1 = aStart[k + 1];
    final t0 = tb[k];
    final t1 = tb[k + 1];
    final start = pages == 1 ? 0 : pageMs[k];
    final end = (pages == 1 || k == pages - 1) ? -1 : pageMs[k + 1];

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
    _shade(arLayer, look);
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
        fontFamily: translationFont,
        align: translationAlign,
      );
      _shade(trLayer, look);
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
    _shade(fl, look);
    _fit(fl, (tall ? look.translationTall : look.translationWide) * 0.8, 0.8);
    fl.cy = 0.93;
    layers.add(fl);
  }
  return layers;
}

/// A tight, strong shadow that works like a soft outline: the text stays readable on
/// bright skies, busy patterns and moving video. The user can still change it in the editor.
void _shade(Layer l, QTemplate look) {
  l.shadowOn = look.shadow;
  l.shadowColor = look.shadowColor;
  l.shadowBlur = 0.012;
  l.shadowX = 0.0;
  l.shadowY = 0.01;
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

/// Moments (ms, counted from the start of the trimmed verse) where the recitation dips: a
/// breath or the end of a phrase. Found as local lows in the loudness curve, so it also works
/// for reciters who never stop completely. Used to start a new text page where the recitation
/// really breaks. Returns an empty list when the recording cannot be analysed.
Future<List<int>> versePauses(String path, int totalMs, int trimStartMs, int durationMs) async {
  try {
    if (totalMs <= 0 || durationMs < 8000) return const [];
    final bins = (totalMs / 50).round().clamp(200, 4000).toInt();
    final peaks = await KainuwaEncoder.audioPeaks(path, bins: bins);
    if (peaks.length < 40) return const [];
    var top = 0.0;
    for (final p in peaks) {
      if (p > top) top = p;
    }
    if (top <= 0) return const [];
    final bin = totalMs / peaks.length;
    // Smooth over three bins, then take points much lower than the loudness around them.
    final sm = List<double>.filled(peaks.length, 0);
    for (var i = 0; i < peaks.length; i++) {
      final a = peaks[math.max(0, i - 1)];
      final b = peaks[i];
      final c = peaks[math.min(peaks.length - 1, i + 1)];
      sm[i] = (a + b + c) / 3;
    }
    final w = math.max(4, (600 / bin).round());
    final out = <int>[];
    var lastAt = -100000;
    for (var i = w; i < sm.length - w; i++) {
      var sum = 0.0;
      var lowest = true;
      for (var k = i - w; k <= i + w; k++) {
        sum += sm[k];
        if (sm[k] < sm[i]) lowest = false;
      }
      final avg = sum / (2 * w + 1);
      if (lowest && sm[i] < avg * 0.5 && avg > top * 0.08) {
        final at = (i * bin).round() - trimStartMs;
        if (at > 500 && at < durationMs - 500 && at - lastAt >= 700) {
          out.add(at);
          lastAt = at;
        }
      }
    }
    return out;
  } catch (_) {
    return const [];
  }
}

import 'dart:math' as math;

import 'models.dart';

/// The look of an item at one moment of its animation.
class AnimFrame {
  const AnimFrame(this.alpha, this.dx, this.scale, [this.scaleX = 1, this.rot = 0, this.dy = 0]);

  /// 0 (invisible) to 1 (fully visible)
  final double alpha;

  /// Sideways shift as a fraction of the slide width
  final double dx;
  final double scale;

  /// Extra stretch across the width only (used by Draw)
  final double scaleX;

  /// Turn in degrees, clockwise (overall animations)
  final double rot;

  /// Vertical shift as a fraction of the slide height, down is positive
  final double dy;
}

const List<String> kAnimKinds = ['none', 'appear', 'fade', 'slide', 'pop', 'zoom', 'draw'];
const List<String> kExitKinds = ['none', 'fade', 'slide', 'pop', 'zoom', 'draw'];

String animLabel(String kind) {
  switch (kind) {
    case 'appear':
      return 'Appear';
    case 'fade':
      return 'Fade';
    case 'slide':
      return 'Slide';
    case 'pop':
      return 'Pop';
    case 'zoom':
      return 'Zoom';
    case 'draw':
      return 'Draw';
    default:
      return 'None';
  }
}

/// Entrance. The same formulas are used by the video export (LessonOverlays.java),
/// so the preview matches the video.
/// Slide distances: a fifth of the slide width, and the same on screen for up and down.
const double kSlideX = 0.175;
const double kSlideY = 0.31;

const List<String> kSlideDirs = ['right', 'left', 'up', 'down'];

String slideDirLabel(String dir) {
  switch (dir) {
    case 'left':
      return 'Slide left';
    case 'up':
      return 'Slide up';
    case 'down':
      return 'Slide down';
    default:
      return 'Slide right';
  }
}

/// The kind as sent to the video encoder: a slide carries its direction, for example slide:up.
String kindWithDir(String kind, String dir) => kind == 'slide' ? 'slide:$dir' : kind;

AnimFrame animationFrame(String kind, int timeMs, int startMs, int durationMs, [String dir = 'right']) {
  if (kind == 'none') return const AnimFrame(1, 0, 1);
  final duration = math.max(1, durationMs);
  final double progress =
      timeMs <= startMs ? 0.0 : math.min(1.0, (timeMs - startMs) / duration);
  if (kind == 'appear') return AnimFrame(progress > 0 ? 1 : 0, 0, 1);

  final eased = 1 - math.pow(1 - progress, 3).toDouble();
  var alpha = eased;
  var dx = 0.0;
  var scale = 1.0;
  var scaleX = 1.0;
  var dy = 0.0;
  switch (kind) {
    case 'slide':
      switch (dir) {
        case 'left':
          dx = kSlideX * (1 - eased);
          break;
        case 'up':
          dy = kSlideY * (1 - eased);
          break;
        case 'down':
          dy = -kSlideY * (1 - eased);
          break;
        default:
          dx = -kSlideX * (1 - eased);
      }
      break;
    case 'pop':
      {
        final q = progress - 1;
        scale = 1 + 2.70158 * q * q * q + 1.70158 * q * q;
        alpha = math.min(1.0, progress * 4);
      }
      break;
    case 'zoom':
      scale = 1.6 - 0.6 * eased;
      break;
    case 'draw':
      alpha = 1;
      scaleX = math.max(0.01, eased);
      break;
  }
  if (progress <= 0) alpha = 0;
  return AnimFrame(alpha, dx, math.max(0.01, scale), scaleX, 0, dy);
}

/// Exit, played during the last [outDurMs] before the item leaves.
AnimFrame exitFrame(String kind, int timeMs, int outStartMs, int outDurMs, [String dir = 'right']) {
  if (kind == 'none') return const AnimFrame(1, 0, 1);
  final duration = math.max(1, outDurMs);
  final double p = timeMs <= outStartMs ? 0.0 : math.min(1.0, (timeMs - outStartMs) / duration);
  final e = p * p;
  switch (kind) {
    case 'fade':
      return AnimFrame(1 - e, 0, 1);
    case 'slide':
      switch (dir) {
        case 'left':
          return AnimFrame(1 - e, -kSlideX * e, 1);
        case 'up':
          return AnimFrame(1 - e, 0, 1, 1, 0, -kSlideY * e);
        case 'down':
          return AnimFrame(1 - e, 0, 1, 1, 0, kSlideY * e);
        default:
          return AnimFrame(1 - e, kSlideX * e, 1);
      }
    case 'pop':
      return AnimFrame(1 - e, 0, math.max(0.01, 1 - 0.5 * e));
    case 'zoom':
      return AnimFrame(1 - e, 0, 1 + 0.6 * e);
    case 'draw':
      return AnimFrame(1, 0, 1, math.max(0.01, 1 - e));
  }
  return const AnimFrame(1, 0, 1);
}

/// The last millisecond (exclusive) an item is on screen.
int layerEndMs(Layer layer, int sceneMs) =>
    layer.endMs < 0 ? sceneMs : math.min(layer.endMs, sceneMs);

/// Everything about an item at [timeMs] into its slide: timing, entrance and exit.
AnimFrame layerFrame(Layer layer, int timeMs, int sceneMs) {
  final end = layerEndMs(layer, sceneMs);
  if (timeMs < layer.startMs || timeMs >= end) return const AnimFrame(0, 0, 1);
  var f = animationFrame(
    layer.animIn,
    timeMs,
    layer.startMs + layer.animStartMs,
    layer.animDurationMs,
    layer.animInDir,
  );
  if (layer.animOut != 'none') {
    final out = exitFrame(layer.animOut, timeMs, end - layer.animOutDurationMs, layer.animOutDurationMs, layer.animOutDir);
    f = AnimFrame(f.alpha * out.alpha, f.dx + out.dx, f.scale * out.scale, f.scaleX * out.scaleX, f.rot, f.dy + out.dy);
  }
  if (layer.animLoop != 'none') {
    final lp = loopFrame(layer.animLoop, timeMs - layer.startMs, loopPeriodMs(layer));
    f = AnimFrame(
      f.alpha * lp.alpha,
      f.dx + lp.dx,
      f.scale * lp.scale,
      f.scaleX * lp.scaleX,
      f.rot + lp.rot,
      f.dy + lp.dy,
    );
  }
  return f;
}

/// Overall animations: they repeat the whole time the item is on screen.
/// The same maths is in LessonOverlays.java and must stay identical.
const List<String> kLoopKinds = [
  'none',
  'spin',
  'spinback',
  'swing',
  'wobble',
  'shake',
  'pulse',
  'heartbeat',
  'float',
  'bounce',
  'blink',
  'flip',
];

String loopLabel(String kind) {
  switch (kind) {
    case 'spin':
      return 'Spin 360';
    case 'spinback':
      return 'Spin back';
    case 'swing':
      return 'Swing';
    case 'wobble':
      return 'Wobble';
    case 'shake':
      return 'Shake';
    case 'pulse':
      return 'Pulse';
    case 'heartbeat':
      return 'Heartbeat';
    case 'float':
      return 'Float';
    case 'bounce':
      return 'Bounce';
    case 'blink':
      return 'Blink';
    case 'flip':
      return 'Flip';
    default:
      return 'None';
  }
}

int defaultLoopMs(String kind) {
  switch (kind) {
    case 'spin':
    case 'spinback':
      return 3000;
    case 'swing':
      return 1600;
    case 'wobble':
      return 1200;
    case 'shake':
      return 400;
    case 'pulse':
      return 1200;
    case 'heartbeat':
      return 1100;
    case 'float':
      return 2400;
    case 'bounce':
      return 900;
    case 'blink':
      return 1000;
    case 'flip':
      return 2400;
    default:
      return 1000;
  }
}

/// Time of one round of the overall animation.
int loopPeriodMs(Layer layer) => layer.animLoopMs > 0 ? layer.animLoopMs : defaultLoopMs(layer.animLoop);

/// [timeMs] is the time since the item appeared.
AnimFrame loopFrame(String kind, int timeMs, int periodMs) {
  if (kind == 'none' || timeMs < 0) return const AnimFrame(1, 0, 1);
  final period = math.max(100, periodMs);
  final phase = (timeMs % period) / period;
  final s = math.sin(2 * math.pi * phase);
  switch (kind) {
    case 'spin':
      return AnimFrame(1, 0, 1, 1, 360 * phase, 0);
    case 'spinback':
      return AnimFrame(1, 0, 1, 1, -360 * phase, 0);
    case 'swing':
      return AnimFrame(1, 0, 1, 1, 15 * s, 0);
    case 'wobble':
      return AnimFrame(1, 0, 1 + 0.04 * math.cos(2 * math.pi * phase), 1, 6 * s, 0);
    case 'shake':
      return AnimFrame(1, 0.012 * s, 1, 1, 2 * s, 0);
    case 'pulse':
      return AnimFrame(1, 0, 1 + 0.08 * s);
    case 'heartbeat':
      final beat = phase < 0.5 ? math.max(0.0, math.sin(4 * math.pi * phase)) : 0.0;
      return AnimFrame(1, 0, 1 + 0.12 * beat);
    case 'float':
      return AnimFrame(1, 0, 1, 1, 0, 0.02 * s);
    case 'bounce':
      return AnimFrame(1, 0, 1, 1, 0, -0.05 * math.sin(math.pi * phase).abs());
    case 'blink':
      return AnimFrame(0.35 + 0.65 * (0.5 + 0.5 * math.cos(2 * math.pi * phase)), 0, 1);
    case 'flip':
      return AnimFrame(1, 0, 1, math.max(0.03, math.cos(2 * math.pi * phase).abs()));
    default:
      return const AnimFrame(1, 0, 1);
  }
}

/// True when the item needs to be animated by the video encoder instead of
/// being part of the slide picture.
bool layerNeedsOverlay(Layer layer) =>
    layer.animIn != 'none' ||
    layer.animOut != 'none' ||
    (layer.type == 'text' && layer.textAnim != 'none') ||
    layer.hand.isNotEmpty ||
    layer.animLoop != 'none' ||
    layer.startMs > 0 ||
    layer.endMs >= 0;

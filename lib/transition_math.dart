import 'dart:math' as math;

import 'models.dart';

/// Transitions between two slides. The slide that ends moves out during the last half of the
/// transition and the next slide moves in during the first half. The maths here must stay the same
/// as in TransitionEffect.java.
const List<String> kTransitionKinds = ['none', 'push', 'zoompush', 'zoom', 'fade', 'glitch'];
const List<String> kTransitionDirs = ['left', 'right', 'up', 'down'];

String transitionLabel(String kind) {
  switch (kind) {
    case 'push':
      return 'Push';
    case 'zoompush':
      return 'Zoom push';
    case 'zoom':
      return 'Zoom';
    case 'fade':
      return 'Fade';
    case 'glitch':
      return 'Glitch push';
    default:
      return 'None';
  }
}

bool transitionUsesDirection(String kind) => kind == 'push' || kind == 'zoompush' || kind == 'glitch';

class TransFrame {
  const TransFrame(this.scale, this.dx, this.dy, this.alpha, this.split);

  /// Size of the picture (1 is normal).
  final double scale;

  /// Shift as a fraction of the width (right is positive).
  final double dx;

  /// Shift as a fraction of the height (up is positive).
  final double dy;
  final double alpha;

  /// Red and blue colour shift as a fraction of the width.
  final double split;

  static const TransFrame none = TransFrame(1, 0, 0, 1, 0);
}

double _ease(double t) {
  final x = t.clamp(0.0, 1.0).toDouble();
  return x < 0.5 ? 4 * x * x * x : 1 - math.pow(-2 * x + 2, 3) / 2;
}

/// [p] is how far through this half of the transition we are (0 to 1).
TransFrame transitionHalfFrame(String kind, String dir, double p, bool exiting) {
  final e = _ease(p);
  final a = exiting ? e : 1 - e; // 0 = normal picture, 1 = fully away
  var vx = 0.0;
  var vy = 0.0;
  switch (dir) {
    case 'right':
      vx = 1;
      break;
    case 'up':
      vy = 1;
      break;
    case 'down':
      vy = -1;
      break;
    default:
      vx = -1;
  }
  final sign = exiting ? 1.0 : -1.0;
  switch (kind) {
    case 'push':
      return TransFrame(1, vx * sign * a, vy * sign * a, 1, 0);
    case 'zoompush':
      return TransFrame(1 - 0.18 * a, vx * sign * a, vy * sign * a, 1, 0);
    case 'glitch':
      return TransFrame(1 - 0.08 * a, vx * sign * a, vy * sign * a, 1, 0.03 * 4 * a * (1 - a));
    case 'zoom':
      return TransFrame(exiting ? 1 + 0.6 * a : 1 - 0.3 * a, 0, 0, 1 - a, 0);
    case 'fade':
      return TransFrame(1, 0, 0, 1 - a, 0);
    default:
      return TransFrame.none;
  }
}

/// Half of the transition after [index], in milliseconds, kept short enough for both slides.
int transitionHalfMs(Lesson lesson, int index) {
  if (index < 0 || index >= lesson.scenes.length - 1) return 0;
  final a = lesson.scenes[index];
  if (a.transKind == 'none') return 0;
  final b = lesson.scenes[index + 1];
  final limit = math.min(a.durationMs, b.durationMs) ~/ 2;
  return math.min(a.transMs ~/ 2, math.max(0, limit - 50));
}

/// The background colour for the transition that is running at [localMs] of scene [index].
int transitionBgAt(Lesson lesson, int index, int localMs) {
  final scene = lesson.scenes[index];
  final out = transitionHalfMs(lesson, index);
  if (out > 0 && localMs >= scene.durationMs - out) return scene.transBg;
  if (index > 0) {
    final inn = transitionHalfMs(lesson, index - 1);
    if (inn > 0 && localMs < inn) return lesson.scenes[index - 1].transBg;
  }
  return 0xFF000000;
}

/// The transition frame to show at [localMs] of scene [index], or null for a normal frame.
TransFrame? sceneTransitionFrame(Lesson lesson, int index, int localMs) {
  final scene = lesson.scenes[index];
  final out = transitionHalfMs(lesson, index);
  if (out > 0 && localMs >= scene.durationMs - out) {
    final p = (localMs - (scene.durationMs - out)) / out;
    return transitionHalfFrame(scene.transKind, scene.transDir, p, true);
  }
  if (index > 0) {
    final inn = transitionHalfMs(lesson, index - 1);
    if (inn > 0 && localMs < inn) {
      final prev = lesson.scenes[index - 1];
      return transitionHalfFrame(prev.transKind, prev.transDir, localMs / inn, false);
    }
  }
  return null;
}

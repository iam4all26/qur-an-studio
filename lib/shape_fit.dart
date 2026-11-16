import 'dart:math' as math;

import 'models.dart';
import 'stage_shape.dart';

/// Changes the shape of a video. Every item keeps its proportions: the whole slide is
/// scaled to fit inside the new shape and centred, so nothing is stretched or cut off.
void applyVideoShape(Lesson lesson, int aw, int ah) {
  final old = lesson.stageSize;
  final next = stageSizeFor(aw, ah);
  final s = math.min(next.$1 / old.$1, next.$2 / old.$2);
  final ox = (next.$1 - old.$1 * s) / 2;
  final oy = (next.$2 - old.$2 * s) / 2;
  for (final scene in lesson.scenes) {
    for (final layer in scene.layers) {
      final px = layer.cx * old.$1 * s + ox;
      final py = layer.cy * old.$2 * s + oy;
      layer.cx = px / next.$1;
      layer.cy = py / next.$2;
      layer.w = layer.w * old.$1 * s / next.$1;
      layer.h = layer.h * old.$2 * s / next.$2;
    }
  }
  lesson.aspectW = aw;
  lesson.aspectH = ah;
}

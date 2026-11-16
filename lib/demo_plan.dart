import 'dart:math' as math;

import 'animation_math.dart';
import 'hands.dart';
import 'models.dart';
import 'text_reveal.dart';

/// How the editor shows an item's animation on the canvas while the Animate panel is open:
/// the item plays its entrance, text effect or hand and its overall animation, holds for a
/// moment, plays its exit, and starts again.
class DemoPlan {
  const DemoPlan(this.layer, this.total);

  /// A copy of the item that starts at 0 and ends where the demo ends.
  final Layer layer;

  /// Length of one demo round, in milliseconds.
  final int total;
}

DemoPlan demoPlan(Layer l) {
  var play = 800;
  if (l.animIn != 'none') play = math.max(play, l.animStartMs + l.animDurationMs);
  if (handById(l.hand) != null) {
    play = math.max(play, l.animStartMs + handTotalMs(l));
  } else if (l.type == 'text' && l.textAnim != 'none') {
    play = math.max(play, l.animStartMs + textRevealTotalMs(l));
  }
  if (l.animLoop != 'none') {
    final period = loopPeriodMs(l);
    play = math.max(play, period < 1500 ? period * 2 : period);
  }
  final hasExit = l.animOut != 'none';
  final endMs = hasExit ? play + 700 + l.animOutDurationMs : play + 700;
  final total = math.min(40000, hasExit ? endMs + 400 : endMs);
  final clone = Layer.fromJson({...l.toJson(), 'startMs': 0, 'endMs': endMs});
  return DemoPlan(clone, total);
}

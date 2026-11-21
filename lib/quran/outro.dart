import 'dart:math' as math;

import '../models.dart';
import '../scene_canvas.dart';

/// The built-in ending clip added to the end of an exported video: the app logo pops in, then
/// the credits fade in one after the other. It is built when the video is exported and is never
/// stored in the project. Durations are in milliseconds.
const int kOutroMs = 5500;

Scene buildOutroScene({required int aspectW, required int aspectH, String reciterName = ''}) {
  final tall = aspectH >= aspectW;
  final sceneId = newId();
  // Layer sizes are fractions of the frame, so a pixel size is divided by the frame size
  // (the frame is 1080 on its short side in the design values below).
  final short = 1080.0;
  final fw = tall ? short : short * aspectW / aspectH;
  final fh = tall ? short * aspectH / aspectW : short;

  final scene = Scene(
    id: sceneId,
    durationMs: kOutroMs,
    bgType: 'color',
    bgValue: '${0xFF0B2A24}',
  );

  Layer text(String t, double px, double cy, int color, int delay, {bool bold = false, String font = 'Manrope'}) {
    final l = Layer(
      id: newId(),
      type: 'text',
      text: t,
      cx: 0.5,
      cy: cy,
      color: color,
      bold: bold,
      align: 'center',
      fontFamily: font,
      animIn: 'fade',
      animStartMs: delay,
      animDurationMs: 700,
    );
    setLayerTextSizePx(l, px);
    if (l.w > 0.9) {
      final f = 0.9 / l.w;
      l.w = 0.9;
      l.h = l.h * f;
    }
    return l;
  }

  final logoSide = math.min(fw, fh) * (tall ? 0.34 : 0.30);
  final logoCy = tall ? 0.27 : 0.30;
  scene.layers.add(Layer(
    id: newId(),
    type: 'asset',
    path: 'assets/icon/app_icon.png',
    cx: 0.5,
    cy: logoCy,
    w: logoSide / fw,
    h: logoSide / fh,
    animIn: 'pop',
    animStartMs: 0,
    animDurationMs: 900,
  ));

  final k = tall ? 1.0 : 0.8;
  scene.layers.add(text("Qur'an Studio", 78 * k, tall ? 0.45 : 0.55, 0xFFFFFFFF, 700, bold: true));
  if (reciterName.isNotEmpty) {
    scene.layers.add(text('Recitation by $reciterName', 40 * k, tall ? 0.52 : 0.65, 0xFFE8C96A, 1200));
  }
  scene.layers.add(text('Developed by Kainuwa Digital Africa', 38 * k, tall ? 0.59 : 0.74, 0xFFFFFFFF, 1700));

  // Google Play line: the Play mark and the words next to each other.
  final iconSide = 64.0 * k;
  final playCy = tall ? 0.70 : 0.88;
  final label = text('Get it on Google Play', 42 * k, playCy, 0xFFFFFFFF, 2300, bold: true);
  final gap = 18.0 * k;
  final totalW = iconSide + gap + label.w * fw;
  final left = (fw - totalW) / 2;
  label.cx = (left + iconSide + gap + label.w * fw / 2) / fw;
  scene.layers.add(Layer(
    id: newId(),
    type: 'asset',
    path: 'assets/outro/play_icon.png',
    cx: (left + iconSide / 2) / fw,
    cy: playCy,
    w: iconSide / fw,
    h: iconSide / fh,
    animIn: 'pop',
    animStartMs: 2300,
    animDurationMs: 600,
  ));
  scene.layers.add(label);
  return scene;
}

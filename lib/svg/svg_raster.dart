import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:kainuwa_encoder/kainuwa_encoder.dart';
import 'package:vector_graphics/vector_graphics.dart';

class SvgRaster {
  SvgRaster(this.path, this.aspect);

  /// A PNG picture of the SVG.
  final String path;

  /// Width divided by height.
  final double aspect;
}

/// Turns an SVG file into a sharp PNG once, so slides and export use the same
/// picture code as every other image.
Future<SvgRaster?> rasterizeSvg(String svgPath, {int longSide = 1024}) async {
  try {
    final text = await File(svgPath).readAsString();
    return _rasterizeText(text, longSide);
  } catch (_) {
    return null;
  }
}

/// Same, for an SVG that ships inside the app (for example assets/icons_svg/06_Laptop.svg).
Future<SvgRaster?> rasterizeSvgAsset(String assetPath, {int longSide = 1024}) async {
  try {
    final text = await rootBundle.loadString(assetPath);
    return _rasterizeText(text, longSide);
  } catch (_) {
    return null;
  }
}

Future<SvgRaster?> _rasterizeText(String text, int longSide) async {
  try {
    final info = await vg.loadPicture(SvgStringLoader(text), null);
    final size = info.size;
    if (size.width <= 0 || size.height <= 0) {
      info.picture.dispose();
      return null;
    }
    final scale = longSide / math.max(size.width, size.height);
    final w = (size.width * scale).round().clamp(1, 4096);
    final h = (size.height * scale).round().clamp(1, 4096);
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.scale(scale);
    canvas.drawPicture(info.picture);
    final picture = recorder.endRecording();
    final image = await picture.toImage(w, h);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    info.picture.dispose();
    picture.dispose();
    image.dispose();
    if (data == null) return null;
    final base = await KainuwaEncoder.filesDir();
    final dir = Directory('$base/kainuwa_data/svg');
    if (!await dir.exists()) await dir.create(recursive: true);
    final file = File('${dir.path}/${text.hashCode.toRadixString(16)}_$longSide.png');
    await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
    return SvgRaster(file.path, w / h);
  } catch (_) {
    return null;
  }
}

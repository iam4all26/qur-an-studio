import 'dart:convert';

import 'package:flutter/services.dart';

/// A video template, read from assets/templates/templates.json (schemaVersion 2).
class QTemplate {
  QTemplate({
    required this.id,
    required this.name,
    required this.category,
    required this.portraitAsset,
    required this.landscapeAsset,
    this.squareAsset = '',
    required this.arabicColor,
    required this.translationColor,
    required this.arabicTall,
    required this.arabicWide,
    required this.translationTall,
    required this.translationWide,
    this.arabicFont = '',
    this.translationFont = '',
    this.shadow = true,
    this.shadowColor = 0xF2000000,
  });

  final String id;
  final String name;
  final String category;
  final String portraitAsset;
  final String landscapeAsset;
  final String squareAsset;
  final int arabicColor;
  final int translationColor;
  final double arabicTall;
  final double arabicWide;
  final double translationTall;
  final double translationWide;

  /// Font families the template wants. They are downloaded Qur'an fonts; when one is not
  /// installed the app falls back to Amiri Quran, then to the default font.
  final String arabicFont;
  final String translationFont;

  /// Shadow behind the text so it reads on any picture or video. On by default.
  final bool shadow;
  final int shadowColor;

  /// The picture made for the video shape: wide, square or tall. A template without a square
  /// picture uses the tall one.
  String assetFor(int w, int h) {
    if (w > h * 1.05) return landscapeAsset;
    if (h > w * 1.05) return portraitAsset;
    return squareAsset.isEmpty ? portraitAsset : squareAsset;
  }

  /// The picture shown in lists for the shape the person is working in.
  String previewFor(int w, int h) => assetFor(w, h);

  static int _color(dynamic v) => int.parse('$v');

  factory QTemplate.fromJson(Map<String, dynamic> j) {
    final bg = j['background'] as Map<String, dynamic>;
    final ar = j['arabic'] as Map<String, dynamic>;
    final tr = j['translation'] as Map<String, dynamic>;
    return QTemplate(
      id: j['id'] as String,
      name: j['name'] as String,
      category: j['category'] as String,
      portraitAsset: bg['portrait'] as String,
      landscapeAsset: bg['landscape'] as String,
      squareAsset: (bg['square'] as String?) ?? '',
      arabicColor: _color(ar['color']),
      translationColor: _color(tr['color']),
      arabicTall: (ar['sizeTall'] as num).toDouble(),
      arabicWide: (ar['sizeWide'] as num).toDouble(),
      translationTall: (tr['sizeTall'] as num).toDouble(),
      translationWide: (tr['sizeWide'] as num).toDouble(),
      arabicFont: (ar['font'] as String?) ?? '',
      translationFont: (tr['font'] as String?) ?? '',
      shadow: (j['shadow'] as bool?) ?? true,
      shadowColor: j['shadowColor'] == null ? 0xF2000000 : _color(j['shadowColor']),
    );
  }
}

class QTemplates {
  QTemplates._();
  static List<QTemplate>? _cache;

  static Future<List<QTemplate>> load() async {
    final cached = _cache;
    if (cached != null) return cached;
    final text = await rootBundle.loadString('assets/templates/templates.json');
    final j = jsonDecode(text) as Map<String, dynamic>;
    final list = [
      for (final t in (j['templates'] as List)) QTemplate.fromJson(t as Map<String, dynamic>)
    ];
    _cache = list;
    return list;
  }
}

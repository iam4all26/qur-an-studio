import 'dart:convert';

import 'package:flutter/services.dart';

/// A video template, read from assets/templates/templates.json (schemaVersion 1).
class QTemplate {
  QTemplate({
    required this.id,
    required this.name,
    required this.category,
    required this.portraitAsset,
    required this.landscapeAsset,
    required this.arabicColor,
    required this.translationColor,
    required this.arabicTall,
    required this.arabicWide,
    required this.translationTall,
    required this.translationWide,
  });

  final String id;
  final String name;
  final String category;
  final String portraitAsset;
  final String landscapeAsset;
  final int arabicColor;
  final int translationColor;
  final double arabicTall;
  final double arabicWide;
  final double translationTall;
  final double translationWide;

  /// Square and vertical videos use the portrait picture.
  String assetFor(int w, int h) => w > h ? landscapeAsset : portraitAsset;

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
      arabicColor: _color(ar['color']),
      translationColor: _color(tr['color']),
      arabicTall: (ar['sizeTall'] as num).toDouble(),
      arabicWide: (ar['sizeWide'] as num).toDouble(),
      translationTall: (tr['sizeTall'] as num).toDouble(),
      translationWide: (tr['sizeWide'] as num).toDouble(),
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

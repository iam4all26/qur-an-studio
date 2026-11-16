// Generated list of the built-in asset packs.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../store/store_service.dart';

class CatalogItem {
  const CatalogItem(this.path, this.name, {this.tint = false});
  final String path;
  final String name;

  /// Downloaded SVG icons that start white and can be recoloured.
  final bool tint;

  /// True for a downloaded item (stored on the phone) and false for a built-in one.
  bool get isFile => path.startsWith('/');
}

/// Shows a catalog item, whether built in or downloaded.
Widget catalogImage(CatalogItem item, {BoxFit fit = BoxFit.contain, int? cacheWidth}) {
  if (item.isFile) {
    if (item.path.toLowerCase().endsWith('.svg')) {
      return SvgPicture.file(
        File(item.path),
        fit: fit,
        colorFilter: item.tint ? const ColorFilter.mode(Colors.white, BlendMode.srcIn) : null,
      );
    }
    return Image.file(File(item.path), fit: fit, cacheWidth: cacheWidth);
  }
  if (item.path.toLowerCase().endsWith('.svg')) {
    return SvgPicture.asset(item.path, fit: fit);
  }
  return Image.asset(item.path, fit: fit, cacheWidth: cacheWidth);
}

/// Built-in backgrounds plus the ones downloaded from the store, as one list.
List<CatalogItem> allBackgrounds() => [
      ...kBackgrounds,
      for (final i in StoreService.instance.ofType('background')) CatalogItem(i.path, i.name),
    ];

/// Built-in icons plus downloaded icons, as one list.
List<CatalogItem> allIcons() => [
      ...kIcons,
      for (final i in StoreService.instance.ofType('icon')) CatalogItem(i.path, i.name, tint: true),
    ];

/// Downloaded shapes.
List<CatalogItem> storeShapes() => [
      for (final i in StoreService.instance.ofType('shape')) CatalogItem(i.path, i.name),
    ];

const List<CatalogItem> kBackgrounds = [];

const List<CatalogItem> kIcons = [];

const List<CatalogItem> kIllustrations = [];

const List<CatalogItem> kSocialIcons = [];

const List<CatalogItem> kDeveloperIcons = [];

const List<CatalogItem> kLanguageIcons = [];

const List<CatalogItem> kCryptoIcons = [];

// Backgrounds that are mostly dark: new text defaults to white on them.
const Set<String> kDarkBackgrounds = {
  'assets/backgrounds/01_Royal_Purple_Waves.jpg',
  'assets/backgrounds/05_Dark_Technology.jpg',
  'assets/backgrounds/08_Financial_Growth.jpg',
  'assets/backgrounds/10_Cryptocurrency_Blockchain.jpg',
  'assets/backgrounds/11_Video_Production.jpg',
  'assets/backgrounds/12_Green_Chalkboard.jpg',
  'assets/backgrounds/13_AI_Innovation.jpg',
};

const List<CatalogItem> kAppIcons = [];

const List<CatalogItem> kPaymentIcons = [];

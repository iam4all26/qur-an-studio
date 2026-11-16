import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:kainuwa_encoder/kainuwa_encoder.dart';

/// Change this to your GitHub name, or use the Store address button in the app.
const String kDefaultStoreBase =
    'https://raw.githubusercontent.com/Iam4all26/245stdstr/main/';

class StoreItem {
  StoreItem({
    required this.id,
    required this.type,
    required this.name,
    required this.file,
    this.preview = '',
    this.sizeKb = 0,
    this.family = '',
    this.category = '',
  });

  final String id;

  /// font or background
  final String type;
  final String name;
  final String file;
  final String preview;
  final int sizeKb;
  final String family;

  /// Group in the store (for fonts: Sans Serif, Serif, Display, Handwriting, Monospace ...).
  final String category;

  factory StoreItem.fromJson(Map<String, dynamic> j) => StoreItem(
        id: '${j['id'] ?? ''}',
        type: '${j['type'] ?? ''}',
        name: '${j['name'] ?? ''}',
        file: '${j['file'] ?? ''}',
        preview: '${j['preview'] ?? ''}',
        sizeKb: j['sizeKb'] is num ? (j['sizeKb'] as num).round() : 0,
        family: '${j['family'] ?? ''}',
        category: '${j['category'] ?? ''}',
      );
}

class InstalledItem {
  InstalledItem({
    required this.id,
    required this.type,
    required this.name,
    required this.path,
    this.family = '',
    this.category = '',
  });

  final String id;
  final String type;
  final String name;
  final String path;
  final String family;
  final String category;

  Map<String, dynamic> toJson() =>
      {'id': id, 'type': type, 'name': name, 'path': path, 'family': family, 'category': category};

  factory InstalledItem.fromJson(Map<String, dynamic> j) => InstalledItem(
        id: '${j['id'] ?? ''}',
        type: '${j['type'] ?? ''}',
        name: '${j['name'] ?? ''}',
        path: '${j['path'] ?? ''}',
        family: '${j['family'] ?? ''}',
        category: '${j['category'] ?? ''}',
      );
}

/// Downloads items from the store repository and keeps them on the phone.
class StoreService extends ChangeNotifier {
  StoreService._();

  static final StoreService instance = StoreService._();

  String base = kDefaultStoreBase;
  final List<InstalledItem> installed = [];
  Directory? _dir;

  Future<Directory> _root() async {
    final existing = _dir;
    if (existing != null) return existing;
    final files = await KainuwaEncoder.filesDir();
    final dir = Directory('$files/kainuwa_data/store');
    if (!await dir.exists()) await dir.create(recursive: true);
    _dir = dir;
    return dir;
  }

  Future<void> init() async {
    try {
      final dir = await _root();
      final baseFile = File('${dir.path}/base.txt');
      if (await baseFile.exists()) {
        final text = (await baseFile.readAsString()).trim();
        if (text.isNotEmpty) base = text;
      }
      final listFile = File('${dir.path}/installed.json');
      if (await listFile.exists()) {
        final data = jsonDecode(await listFile.readAsString());
        if (data is List) {
          for (final entry in data) {
            if (entry is Map<String, dynamic>) {
              final item = InstalledItem.fromJson(entry);
              if (await File(item.path).exists()) installed.add(item);
            }
          }
        }
      }
      for (final item in installed) {
        if (item.type == 'font') await _loadFont(item);
      }
    } catch (_) {
      // The store is optional. The app works without it.
    }
    notifyListeners();
  }

  Future<void> _save() async {
    final dir = await _root();
    await File('${dir.path}/installed.json')
        .writeAsString(jsonEncode([for (final i in installed) i.toJson()]));
  }

  Future<void> setBase(String value) async {
    var text = value.trim();
    if (text.isNotEmpty && !text.endsWith('/')) text = '$text/';
    base = text.isEmpty ? kDefaultStoreBase : text;
    final dir = await _root();
    await File('${dir.path}/base.txt').writeAsString(base);
    notifyListeners();
  }

  String urlFor(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    return Uri.encodeFull('$base$path');
  }

  bool isInstalled(String id) => installed.any((i) => i.id == id);

  List<InstalledItem> ofType(String type) =>
      installed.where((i) => i.type == type).toList();

  Future<List<StoreItem>> fetchCatalog() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(Uri.parse(urlFor('catalog.json')));
      final response = await request.close().timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw HttpException('The store answered with code ${response.statusCode}.');
      }
      final text = await response.transform(utf8.decoder).join();
      final data = jsonDecode(text);
      final list = data is Map<String, dynamic> ? data['items'] : data;
      final items = <StoreItem>[];
      if (list is List) {
        for (final entry in list) {
          if (entry is Map<String, dynamic>) {
            final item = StoreItem.fromJson(entry);
            if (item.id.isNotEmpty && item.file.isNotEmpty) items.add(item);
          }
        }
      }
      return items;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> download(StoreItem item, ValueChanged<double> onProgress) async {
    final dir = await _root();
    final dot = item.file.lastIndexOf('.');
    final ext = dot >= 0 ? item.file.substring(dot) : '';
    final target = File('${dir.path}/${item.id}$ext');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(Uri.parse(urlFor(item.file)));
      final response = await request.close().timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw HttpException('The file was not found (code ${response.statusCode}).');
      }
      final total = response.contentLength;
      var got = 0;
      final sink = target.openWrite();
      try {
        await for (final chunk in response) {
          sink.add(chunk);
          got += chunk.length;
          if (total > 0) onProgress(got / total);
        }
      } finally {
        await sink.close();
      }
    } catch (e) {
      if (await target.exists()) await target.delete();
      rethrow;
    } finally {
      client.close(force: true);
    }
    final family = item.type == 'font' ? 'store_${item.id}' : '';
    final record = InstalledItem(
      id: item.id,
      type: item.type,
      name: item.name,
      path: target.path,
      family: family,
      category: item.category,
    );
    installed.removeWhere((i) => i.id == item.id);
    installed.add(record);
    if (item.type == 'font') await _loadFont(record);
    await _save();
    notifyListeners();
  }

  Future<void> remove(String id) async {
    final matches = installed.where((i) => i.id == id).toList();
    for (final item in matches) {
      try {
        final f = File(item.path);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    installed.removeWhere((i) => i.id == id);
    await _save();
    notifyListeners();
  }

  Future<void> _loadFont(InstalledItem item) async {
    final bytes = await File(item.path).readAsBytes();
    final loader = FontLoader(item.family)
      ..addFont(Future<ByteData>.value(ByteData.sublistView(Uint8List.fromList(bytes))));
    await loader.load();
  }
}

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:kainuwa_encoder/kainuwa_encoder.dart';

/// Where the data build job publishes its files.
const String kDataBase =
    'https://raw.githubusercontent.com/Iam4all26/qurans-data/main/data/';

class ResourceEntry {
  ResourceEntry({
    required this.id,
    required this.type,
    required this.path,
    required this.sizeBytes,
    required this.sha256,
    this.family,
    this.language,
    this.langName,
    this.translator,
  });

  final String id;
  final String type;
  final String path;
  final int sizeBytes;
  final String sha256;
  final String? family;

  /// For translations: language code, language name and translator, shown in the pickers.
  final String? language;
  final String? langName;
  final String? translator;

  factory ResourceEntry.fromJson(Map<String, dynamic> j) => ResourceEntry(
        id: j['id'] as String,
        type: j['type'] as String,
        path: j['path'] as String,
        sizeBytes: (j['sizeBytes'] as num).toInt(),
        sha256: j['sha256'] as String,
        family: j['family'] as String?,
        language: j['language'] as String?,
        langName: j['name'] as String?,
        translator: j['translator'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'path': path,
        'sizeBytes': sizeBytes,
        'sha256': sha256,
        if (family != null) 'family': family,
        if (language != null) 'language': language,
        if (langName != null) 'name': langName,
        if (translator != null) 'translator': translator,
      };
}

enum ResourceState { missing, ready, outdated }

/// Downloads the Qur'an data files into app-private storage, checks their
/// SHA-256 against the catalog and keeps a small record of what is installed.
class ResourceManager extends ChangeNotifier {
  ResourceManager._();
  static final ResourceManager instance = ResourceManager._();

  List<ResourceEntry> catalog = [];
  final Map<String, String> _installed = {};
  final Map<String, double> progress = {};
  String? error;
  bool busy = false;
  bool _loaded = false;
  final Set<String> _fontsLoaded = {};
  String? _root;

  Future<String> rootPath() async {
    final existing = _root;
    if (existing != null) return existing;
    final base = await KainuwaEncoder.filesDir();
    final dir = Directory('$base/quran/data');
    if (!await dir.exists()) await dir.create(recursive: true);
    _root = dir.path;
    return dir.path;
  }

  Future<String> pathOf(ResourceEntry e) async => '${await rootPath()}/${e.path}';

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final root = await rootPath();
      final inst = File('$root/installed.json');
      if (await inst.exists()) {
        final m = jsonDecode(await inst.readAsString());
        if (m is Map) {
          m.forEach((k, v) => _installed['$k'] = '$v');
        }
      }
      final cat = File('$root/catalog.json');
      if (await cat.exists()) {
        _parseCatalog(await cat.readAsString());
      }
    } catch (e) {
      error = 'Could not read saved state: $e';
    }
    notifyListeners();
  }

  void _parseCatalog(String text) {
    final j = jsonDecode(text) as Map<String, dynamic>;
    catalog = [
      for (final f in (j['files'] as List)) ResourceEntry.fromJson(f as Map<String, dynamic>)
    ];
  }

  ResourceState stateOf(ResourceEntry e) {
    final have = _installed[e.id];
    if (have == null) return ResourceState.missing;
    return have == e.sha256 ? ResourceState.ready : ResourceState.outdated;
  }

  bool get allReady =>
      catalog.isNotEmpty && catalog.every((e) => stateOf(e) == ResourceState.ready);

  bool isReady(String id) {
    for (final e in catalog) {
      if (e.id == id) return stateOf(e) == ResourceState.ready;
    }
    return false;
  }

  /// The family name when a downloaded font with that family is installed, otherwise [fallback].
  String familyIfReady(String family, {String fallback = ''}) {
    if (family.isEmpty) return fallback;
    for (final e in catalog) {
      if (e.type == 'font' && e.family == family && stateOf(e) == ResourceState.ready) return family;
    }
    return fallback;
  }

  /// The translations in the catalog as (id, language name, translator), English first, then
  /// Hausa, then the rest by language name.
  List<(String, String, String)> translationEditions() {
    final out = <(String, String, String)>[];
    for (final e in catalog) {
      if (e.type != 'translation') continue;
      final lang = e.langName ??
          (e.id == 'en_sahih' ? 'English' : e.id == 'ha_gumi' ? 'Hausa' : e.id);
      final who = e.translator ??
          (e.id == 'en_sahih' ? 'Sahih International' : e.id == 'ha_gumi' ? 'Abu Bakr Gumi' : '');
      out.add((e.id, lang, who));
    }
    if (out.isEmpty) {
      out.add(('en_sahih', 'English', 'Sahih International'));
      out.add(('ha_gumi', 'Hausa', 'Abu Bakr Gumi'));
    }
    int rank(String id) => id == 'en_sahih' ? 0 : (id == 'ha_gumi' ? 1 : 2);
    out.sort((a, b) {
      final r = rank(a.$1).compareTo(rank(b.$1));
      return r != 0 ? r : a.$2.compareTo(b.$2);
    });
    return out;
  }

  /// Families of the downloaded fonts that are installed, in catalog order.
  List<String> readyFonts() {
    final out = <String>[];
    for (final e in catalog) {
      final f = e.family;
      if (e.type == 'font' && f != null && stateOf(e) == ResourceState.ready && !out.contains(f)) out.add(f);
    }
    return out;
  }

  /// SHA-256 of the installed copy of a resource, or null when not installed.
  String? installedHash(String id) => _installed[id];

  ResourceEntry? byId(String id) {
    for (final e in catalog) {
      if (e.id == id) return e;
    }
    return null;
  }

  Future<List<int>> _fetch(String url, {void Function(int got)? onBytes}) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      // A changing query value stops raw.githubusercontent.com from serving a cached copy of a
      // file next to a newer catalog.json (that caused "Checksum mismatch" right after a data build).
      final fresh = Uri.parse(url).replace(
        queryParameters: {'cb': DateTime.now().millisecondsSinceEpoch.toString()},
      );
      final req = await client.getUrl(fresh);
      final res = await req.close();
      if (res.statusCode != 200) {
        throw HttpException('HTTP ${res.statusCode} for $url');
      }
      final out = BytesBuilder(copy: false);
      await for (final chunk in res) {
        out.add(chunk);
        onBytes?.call(out.length);
      }
      return out.takeBytes();
    } finally {
      client.close(force: true);
    }
  }

  Future<void> refreshCatalog() async {
    error = null;
    busy = true;
    notifyListeners();
    try {
      final bytes = await _fetch('${kDataBase}catalog.json');
      final text = utf8.decode(bytes);
      _parseCatalog(text);
      final root = await rootPath();
      await File('$root/catalog.json').writeAsString(text);
    } catch (e) {
      error = 'Could not get the catalog: $e';
    }
    busy = false;
    notifyListeners();
  }

  Future<void> download(ResourceEntry e) async {
    error = null;
    busy = true;
    progress[e.id] = 0;
    notifyListeners();
    try {
      final bytes = await _fetch('$kDataBase${e.path}', onBytes: (got) {
        progress[e.id] = e.sizeBytes == 0 ? 0 : (got / e.sizeBytes).clamp(0.0, 1.0);
        notifyListeners();
      });
      final digest = sha256.convert(bytes).toString();
      if (digest != e.sha256) {
        throw StateError('Checksum mismatch for ${e.id}. Nothing was saved.');
      }
      final target = File(await pathOf(e));
      await target.parent.create(recursive: true);
      final part = File('${target.path}.part');
      await part.writeAsBytes(bytes, flush: true);
      if (await target.exists()) await target.delete();
      await part.rename(target.path);
      _installed[e.id] = e.sha256;
      await _saveInstalled();
    } catch (err) {
      error = 'Download failed (${e.id}): $err';
    }
    progress.remove(e.id);
    busy = false;
    notifyListeners();
  }

  Future<void> downloadAll() async {
    for (final e in catalog) {
      if (stateOf(e) != ResourceState.ready) {
        await download(e);
        if (error != null) return;
      }
    }
  }

  Future<void> _saveInstalled() async {
    final root = await rootPath();
    await File('$root/installed.json').writeAsString(jsonEncode(_installed));
  }

  /// Registers every downloaded font with Flutter so Text can use it.
  Future<void> loadFonts() async {
    for (final e in catalog) {
      if (e.type != 'font' || e.family == null) continue;
      if (_fontsLoaded.contains(e.id) || stateOf(e) != ResourceState.ready) continue;
      final f = File(await pathOf(e));
      if (!await f.exists()) continue;
      final bytes = await f.readAsBytes();
      final loader = FontLoader(e.family!)
        ..addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
      await loader.load();
      _fontsLoaded.add(e.id);
    }
  }
}

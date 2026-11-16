import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:kainuwa_encoder/kainuwa_encoder.dart';

import 'resource_manager.dart' show kDataBase;

/// One video background in the catalog (data/backgrounds.json in qurans-data).
class BgClip {
  BgClip({
    required this.id,
    required this.name,
    required this.category,
    required this.path,
    required this.preview,
    required this.sizeBytes,
    required this.sha256,
    required this.durationMs,
    required this.source,
    required this.licence,
    required this.attribution,
  });

  final String id;
  final String name;
  final String category;
  final String path;
  final String preview;
  final int sizeBytes;
  final String sha256;
  final int durationMs;
  final String source;
  final String licence;
  final String attribution;

  factory BgClip.fromJson(Map<String, dynamic> j) => BgClip(
        id: '${j['id']}',
        name: '${j['name'] ?? j['id']}',
        category: '${j['category'] ?? 'Other'}',
        path: '${j['path']}',
        preview: '${j['preview'] ?? ''}',
        sizeBytes: (j['sizeBytes'] as num?)?.toInt() ?? 0,
        sha256: '${j['sha256'] ?? ''}',
        durationMs: (j['durationMs'] as num?)?.toInt() ?? 0,
        source: '${j['source'] ?? ''}',
        licence: '${j['licence'] ?? ''}',
        attribution: '${j['attribution'] ?? ''}',
      );
}

/// Downloads and keeps the video background clips. Separate from ResourceManager so the
/// large clips are never part of the "update everything" button.
class BackgroundManager extends ChangeNotifier {
  BackgroundManager._();
  static final BackgroundManager instance = BackgroundManager._();

  List<BgClip> clips = [];
  final Map<String, String> _installed = {};
  final Map<String, double> progress = {};
  bool busy = false;
  bool _loaded = false;
  String? error;
  String? _root;

  Future<String> root() async {
    final existing = _root;
    if (existing != null) return existing;
    final base = await KainuwaEncoder.filesDir();
    final dir = Directory('$base/quran/backgrounds');
    if (!await dir.exists()) await dir.create(recursive: true);
    return _root = dir.path;
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final r = await root();
      final inst = File('$r/installed.json');
      if (await inst.exists()) {
        final m = jsonDecode(await inst.readAsString());
        if (m is Map) _installed.addAll(m.map((k, v) => MapEntry('$k', '$v')));
      }
      final cat = File('$r/backgrounds.json');
      if (await cat.exists()) _parse(await cat.readAsString());
    } catch (_) {}
    notifyListeners();
  }

  void _parse(String text) {
    final j = jsonDecode(text) as Map<String, dynamic>;
    clips = [
      for (final c in (j['clips'] as List? ?? const [])) BgClip.fromJson(c as Map<String, dynamic>)
    ];
  }

  Future<List<int>> _fetch(String url, {void Function(int got)? onBytes}) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close();
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
      final out = BytesBuilder(copy: false);
      var got = 0;
      await for (final chunk in res) {
        out.add(chunk);
        got += chunk.length;
        onBytes?.call(got);
      }
      return out.takeBytes();
    } finally {
      client.close(force: true);
    }
  }

  Future<void> refresh() async {
    error = null;
    busy = true;
    notifyListeners();
    try {
      final bytes = await _fetch('${kDataBase}backgrounds.json');
      final text = utf8.decode(bytes);
      _parse(text);
      await File('${await root()}/backgrounds.json').writeAsString(text);
    } catch (e) {
      error = 'Could not read the clip list: $e';
    }
    busy = false;
    notifyListeners();
  }

  bool isReady(String id) {
    for (final c in clips) {
      if (c.id == id) return _installed[id] == c.sha256 && c.sha256.isNotEmpty;
    }
    return false;
  }

  Future<String> clipPath(String id) async => '${await root()}/$id.mp4';
  Future<String> previewPath(String id) async => '${await root()}/$id.jpg';

  Future<void> download(BgClip c) async {
    error = null;
    busy = true;
    progress[c.id] = 0;
    notifyListeners();
    try {
      final bytes = await _fetch('$kDataBase${c.path}', onBytes: (got) {
        progress[c.id] = c.sizeBytes == 0 ? 0 : (got / c.sizeBytes).clamp(0.0, 1.0);
        notifyListeners();
      });
      if (sha256.convert(bytes).toString() != c.sha256) {
        throw StateError('Checksum mismatch. Nothing was saved.');
      }
      final target = File(await clipPath(c.id));
      final part = File('${target.path}.part');
      await part.writeAsBytes(bytes, flush: true);
      if (await target.exists()) await target.delete();
      await part.rename(target.path);
      if (c.preview.isNotEmpty) {
        try {
          final p = await _fetch('$kDataBase${c.preview}');
          await File(await previewPath(c.id)).writeAsBytes(p, flush: true);
        } catch (_) {}
      }
      _installed[c.id] = c.sha256;
      await File('${await root()}/installed.json').writeAsString(jsonEncode(_installed));
    } catch (e) {
      error = 'Download failed (${c.name}): $e';
    }
    progress.remove(c.id);
    busy = false;
    notifyListeners();
  }

  Future<void> remove(BgClip c) async {
    try {
      final f = File(await clipPath(c.id));
      if (await f.exists()) await f.delete();
    } catch (_) {}
    _installed.remove(c.id);
    await File('${await root()}/installed.json').writeAsString(jsonEncode(_installed));
    notifyListeners();
  }
}

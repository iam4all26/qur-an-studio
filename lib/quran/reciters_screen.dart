import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:kainuwa_encoder/kainuwa_encoder.dart';

import '../theme.dart';
import 'reciter_media.dart';
import 'resource_manager.dart' show ResourceManager, kDataBase;

class _R {
  _R(this.id, this.name, this.folder, [this.country = '', this.image = '', this.urlTemplate = '']);
  final String urlTemplate;
  String image;
  String local = ''; // path of the saved picture on this phone, empty until downloaded
  String country;
  final String id;
  final String name;
  final String folder;
  int downloaded = 0;
}

class _Mine {
  _Mine(this.name, this.path, this.ms);
  final String name;
  final String path;
  final int ms;
  Map<String, dynamic> toJson() => {'name': name, 'path': path, 'ms': ms};
}

class RecitersScreen extends StatefulWidget {
  const RecitersScreen({super.key});

  @override
  State<RecitersScreen> createState() => _RecitersScreenState();
}

class _RecitersScreenState extends State<RecitersScreen> {
  final rm = ResourceManager.instance;
  List<_R> _list = [];
  final Set<String> _fav = {};
  final List<_Mine> _mine = [];
  String _filter = 'All';
  bool _loading = true;
  String? _note;
  String _root = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await rm.load();
    _root = '${await KainuwaEncoder.filesDir()}/quran';
    await Directory(_root).create(recursive: true);
    final list = <_R>[];
    final e = rm.byId('reciters');
    if (e != null && rm.isReady('reciters')) {
      final j = jsonDecode(await File(await rm.pathOf(e)).readAsString()) as Map<String, dynamic>;
      for (final r in (j['reciters'] as List)) {
        if ((r as Map)['verified'] == true) list.add(_R('${r['id']}', '${r['name']}', '${r['folder']}', '${r['country'] ?? ''}', '${r['image'] ?? ''}', '${r['per_ayah_url'] ?? ''}'));
      }
    }
    final fav = File('$_root/favorites.json');
    if (await fav.exists()) {
      try {
        _fav.addAll([for (final x in jsonDecode(await fav.readAsString()) as List) '$x']);
      } catch (_) {}
    }
    final mine = File('$_root/imports.json');
    if (await mine.exists()) {
      try {
        for (final x in jsonDecode(await mine.readAsString()) as List) {
          final m = x as Map<String, dynamic>;
          if (await File('${m['path']}').exists()) {
            _mine.add(_Mine('${m['name']}', '${m['path']}', (m['ms'] as num?)?.toInt() ?? 0));
          }
        }
      } catch (_) {}
    }
    _list = list;
    for (final r in _list) {
      final f = File('$_root/pictures/${r.id}.jpg');
      if (await f.exists()) r.local = f.path;
    }
    await _count();
    if (mounted) setState(() => _loading = false);
    _fetchPictures();
  }

  /// Reads the published reciters.json for picture and country fields, so pictures show
  /// without updating the saved copy in Resources. Failure (offline) is ignored.
  Future<void> _fetchPictures() async {
    try {
      final c = HttpClient()..connectionTimeout = const Duration(seconds: 10);
      final req = await c.getUrl(Uri.parse('${kDataBase}reciters.json'));
      final res = await req.close();
      if (res.statusCode != 200) {
        c.close();
        return;
      }
      final text = await res.transform(utf8.decoder).join();
      c.close();
      final j = jsonDecode(text) as Map<String, dynamic>;
      final byId = <String, Map>{
        for (final r in (j['reciters'] as List)) '${(r as Map)['id']}': r,
      };
      for (final r in _list) {
        final m = byId[r.id];
        if (m == null) continue;
        final img = '${m['image'] ?? ''}';
        if (img.isNotEmpty) r.image = img;
        final cc = '${m['country'] ?? ''}';
        if (cc.isNotEmpty) r.country = cc;
      }
      if (mounted) setState(() {});
      // Save each picture once on this phone; later the screen works offline.
      await Directory('$_root/pictures').create(recursive: true);
      for (final r in _list) {
        if (r.image.isEmpty || r.local.isNotEmpty) continue;
        try {
          final c2 = HttpClient()..connectionTimeout = const Duration(seconds: 10);
          final res2 = await (await c2.getUrl(Uri.parse('$kDataBase${r.image}'))).close();
          if (res2.statusCode == 200) {
            final bytes = await res2.fold<List<int>>(<int>[], (a, b) => a..addAll(b));
            if (bytes.length > 1000) {
              final f = File('$_root/pictures/${r.id}.jpg');
              await f.writeAsBytes(bytes);
              r.local = f.path;
              if (mounted) setState(() {});
            }
          }
          c2.close();
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<void> _count() async {
    final dir = Directory('$_root/audio');
    final names = await dir.exists()
        ? [await for (final f in dir.list()) f.path.split('/').last]
        : <String>[];
    for (final r in _list) {
      r.downloaded = names.where((n) => n.startsWith('${r.folder}_')).length;
    }
  }

  Future<void> _saveFav() =>
      File('$_root/favorites.json').writeAsString(jsonEncode(_fav.toList()));

  Future<void> _saveMine() => File('$_root/imports.json')
      .writeAsString(jsonEncode([for (final m in _mine) m.toJson()]));

  Future<void> _clear(_R r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete downloads'),
        content: Text('Delete the ${r.downloaded} verse recordings of ${r.name} from this phone?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    final dir = Directory('$_root/audio');
    if (await dir.exists()) {
      await for (final f in dir.list()) {
        if (f.path.split('/').last.startsWith('${r.folder}_')) await f.delete();
      }
    }
    await _count();
    if (mounted) setState(() {});
  }

  Future<void> _import() async {
    try {
      final picked = await KainuwaEncoder.pickAudio();
      if (picked == null || picked.isEmpty) return;
      final dir = Directory('$_root/imports');
      await dir.create(recursive: true);
      final name = picked.split('/').last;
      var path = picked;
      try {
        path = (await File(picked).copy('${dir.path}/$name')).path;
      } catch (_) {}
      final ms = await KainuwaEncoder.audioDuration(path);
      _mine.add(_Mine(name, path, ms));
      await _saveMine();
      if (mounted) setState(() => _note = 'Added $name');
    } catch (e) {
      if (mounted) setState(() => _note = 'Could not import: $e');
    }
  }

  List<_R> get _shown => _list.where((r) {
        if (_filter == 'Favorites') return _fav.contains(r.id);
        if (_filter == 'Downloaded') return r.downloaded > 0;
        return true;
      }).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(centerTitle: true, title: const Text('Reciters')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Row(
                    children: [
                      for (final f in const ['All', 'Favorites', 'Downloaded'])
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: GestureDetector(
                            onTap: () => setState(() => _filter = f),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                              decoration: BoxDecoration(
                                color: _filter == f ? KColors.selected : KColors.lavender,
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Text(
                                f,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    children: [
                      if (_list.isEmpty)
                        const Text('The reciter list is not downloaded. Open Library, Resources first.'),
                      for (final r in _shown) _row(r),
                      if (_shown.isEmpty && _list.isNotEmpty) const Text('Nothing here yet.'),
                      if (_note != null)
                        Padding(padding: const EdgeInsets.only(top: 8), child: Text(_note!)),
                      for (var i = 0; i < _mine.length; i++)
                        Card(
                          child: ListTile(
                            title: Text(_mine[i].name, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(_mine[i].ms > 0
                                ? '${(_mine[i].ms / 1000).toStringAsFixed(1)} s'
                                : 'Length unknown'),
                            trailing: IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () async {
                                _mine.removeAt(i);
                                await _saveMine();
                                if (mounted) setState(() {});
                              },
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: _import,
                      child: Ink(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: KColors.selected,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.upload_file, color: Colors.white),
                            SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Import My Audio',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                    ),
                                  ),
                                  Text(
                                    'Use your own recitation (MP3, M4A, WAV)',
                                    style: TextStyle(color: Colors.white70, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  @override
  void dispose() {
    ReciterPreview.stop();
    super.dispose();
  }

  String _initials(String name) {
    final clean = name.replaceAll(RegExp(r'\([^)]*\)'), ' ').trim();
    final parts = clean.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  Widget _row(_R r) {
    final fav = _fav.contains(r.id);
    const dark = Color(0xFF1B1633);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F4FB),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          ReciterAvatar(id: r.id, name: r.name, image: r.image, radius: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.name,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: dark),
                ),
                Text(
                  [
                    "Complete Qur'an",
                    if (r.country.isNotEmpty) r.country,
                    if (r.downloaded > 0) '${r.downloaded} verses on this phone',
                  ].join('  \u2022  '),
                  style: const TextStyle(fontSize: 12, color: Color(0xFF6B6785)),
                ),
              ],
            ),
          ),
          ReciterPreviewButton(id: r.id, urlTemplate: r.urlTemplate),
          if (r.downloaded > 0)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Color(0xFF6B6785)),
              onPressed: () => _clear(r),
            ),
          IconButton(
            icon: Icon(
              fav ? Icons.favorite : Icons.favorite_border,
              color: fav ? KColors.selected : const Color(0xFF6B6785),
            ),
            onPressed: () async {
              setState(() => fav ? _fav.remove(r.id) : _fav.add(r.id));
              await _saveFav();
            },
          ),
        ],
      ),
    );
  }
}

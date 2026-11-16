import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:kainuwa_encoder/kainuwa_encoder.dart';

import '../theme.dart';
import 'resource_manager.dart';

class _R {
  _R(this.id, this.name, this.folder);
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
        if ((r as Map)['verified'] == true) list.add(_R('${r['id']}', '${r['name']}', '${r['folder']}'));
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
    await _count();
    if (mounted) setState(() => _loading = false);
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
      appBar: AppBar(title: const Text('Reciters')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_list.isEmpty)
                  const Text('The reciter list is not downloaded. Open Library, Resources first.'),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final f in const ['All', 'Favorites', 'Downloaded'])
                      ChoiceChip(
                        label: Text(f),
                        selected: _filter == f,
                        selectedColor: KColors.selected,
                        onSelected: (_) => setState(() => _filter = f),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                for (final r in _shown) _row(r),
                if (_shown.isEmpty && _list.isNotEmpty) const Text('Nothing here yet.'),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _import,
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Import My Audio'),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Use your own recitation (MP3, M4A, WAV). Using it inside a project comes with the sync studio.',
                  style: TextStyle(fontSize: 12, color: KColors.accent),
                ),
                if (_note != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_note!)),
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
    );
  }

  Widget _row(_R r) {
    final fav = _fav.contains(r.id);
    return Card(
      child: ListTile(
        title: Text(r.name),
        subtitle: Text(r.downloaded > 0
            ? '${r.downloaded} verse recordings on this phone'
            : 'Downloaded when you create a video'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (r.downloaded > 0)
              IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _clear(r)),
            IconButton(
              icon: Icon(fav ? Icons.favorite : Icons.favorite_border,
                  color: fav ? KColors.gold : null),
              onPressed: () async {
                setState(() => fav ? _fav.remove(r.id) : _fav.add(r.id));
                await _saveFav();
              },
            ),
          ],
        ),
      ),
    );
  }
}

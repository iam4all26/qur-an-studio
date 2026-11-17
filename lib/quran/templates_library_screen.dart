import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:kainuwa_encoder/kainuwa_encoder.dart';

import '../theme.dart';
import 'new_project_wizard.dart';
import 'resource_manager.dart';
import 'templates.dart';

class TemplatesLibraryScreen extends StatefulWidget {
  const TemplatesLibraryScreen({super.key});

  @override
  State<TemplatesLibraryScreen> createState() => _TemplatesLibraryScreenState();
}

class _TemplatesLibraryScreenState extends State<TemplatesLibraryScreen> {
  List<QTemplate> _all = [];
  final Set<String> _fav = {};
  String _filter = 'All';
  bool _loading = true;
  bool _searching = false;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<File> _favFile() async =>
      File('${await KainuwaEncoder.filesDir()}/quran/template_favorites.json');

  Future<void> _load() async {
    final list = await QTemplates.load();
    try {
      final f = await _favFile();
      if (await f.exists()) {
        _fav.addAll([for (final x in jsonDecode(await f.readAsString()) as List) '$x']);
      }
    } catch (_) {}
    if (mounted) {
      setState(() {
        _all = list;
        _loading = false;
      });
    }
  }

  Future<void> _toggle(String id) async {
    setState(() => _fav.contains(id) ? _fav.remove(id) : _fav.add(id));
    try {
      final f = await _favFile();
      await f.parent.create(recursive: true);
      await f.writeAsString(jsonEncode(_fav.toList()));
    } catch (_) {}
  }

  List<QTemplate> get _shown => _all.where((t) {
        if (_filter == 'All') return true;
        if (_filter == 'Favorites') return _fav.contains(t.id);
        return t.category == _filter;
      }).where((t) {
        final q = _q.trim().toLowerCase();
        return q.isEmpty || t.name.toLowerCase().contains(q) || t.category.toLowerCase().contains(q);
      }).toList();

  @override
  Widget build(BuildContext context) {
    final cats = ['All', 'Modern', 'Cinematic', 'Minimal', 'Natural', 'Favorites'];
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
            child: Row(
              children: [
                const Expanded(
                  child: Text('Templates', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                ),
                IconButton(
                  icon: Icon(_searching ? Icons.close : Icons.search),
                  onPressed: () => setState(() {
                    _searching = !_searching;
                    if (!_searching) _q = '';
                  }),
                ),
              ],
            ),
          ),
          if (_searching)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                autofocus: true,
                onChanged: (v) => setState(() => _q = v),
                decoration: InputDecoration(
                  hintText: 'Search templates',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: KColors.lavender,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final c in cats)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => setState(() => _filter = c),
                      child: Container(
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        decoration: BoxDecoration(
                          color: _filter == c ? KColors.selected : KColors.lavender,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Text(
                          c,
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
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _shown.isEmpty
                    ? const Center(child: Text('No templates here yet'))
                    : GridView.builder(
                        padding: const EdgeInsets.all(16),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 0.62,
                        ),
                        itemCount: _shown.length,
                        itemBuilder: (context, i) => _card(_shown[i]),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _card(QTemplate t) {
    final fav = _fav.contains(t.id);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => NewProjectWizard(templateId: t.id)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(t.portraitAsset, fit: BoxFit.cover, cacheWidth: 400),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  '\u0628\u0650\u0633\u0652\u0645\u0650 \u0671\u0644\u0644\u0651\u064e\u0647\u0650',
                  textAlign: TextAlign.center,
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    color: Color(t.arabicColor),
                    fontSize: 22,
                    fontFamily: ResourceManager.instance.familyIfReady(t.arabicFont, fallback: ''),
                    shadows: const [Shadow(color: Colors.black54, blurRadius: 6, offset: Offset(0, 1))],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 18, 12, 10),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black87],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.name, style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
                    const Text('9:16', style: TextStyle(fontSize: 11, color: Colors.white70)),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 6,
              right: 6,
              child: IconButton(
                style: IconButton.styleFrom(backgroundColor: Colors.black38),
                visualDensity: VisualDensity.compact,
                icon: Icon(fav ? Icons.favorite : Icons.favorite_border,
                    size: 20, color: fav ? KColors.gold : Colors.white),
                onPressed: () => _toggle(t.id),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

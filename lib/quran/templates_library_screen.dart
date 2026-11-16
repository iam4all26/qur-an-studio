import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:kainuwa_encoder/kainuwa_encoder.dart';

import '../theme.dart';
import 'new_project_wizard.dart';
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
      }).toList();

  @override
  Widget build(BuildContext context) {
    final cats = ['All', 'Modern', 'Cinematic', 'Minimal', 'Natural', 'Favorites'];
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text('Templates', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final c in cats)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(c),
                      selected: _filter == c,
                      selectedColor: KColors.selected,
                      onSelected: (_) => setState(() => _filter = c),
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
                  'Qur\'an',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(t.arabicColor), fontSize: 20, fontWeight: FontWeight.w700),
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
                    Text(t.category, style: const TextStyle(fontSize: 11, color: Colors.white70)),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                icon: Icon(fav ? Icons.favorite : Icons.favorite_border,
                    color: fav ? KColors.gold : Colors.white),
                onPressed: () => _toggle(t.id),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

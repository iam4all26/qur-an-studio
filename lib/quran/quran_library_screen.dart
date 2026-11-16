import 'package:flutter/material.dart';

import '../theme.dart';
import 'quran_db.dart';
import 'resource_manager.dart';
import 'resources_screen.dart';
import 'verse_select_screen.dart';

class QuranLibraryScreen extends StatefulWidget {
  const QuranLibraryScreen({super.key});

  @override
  State<QuranLibraryScreen> createState() => _QuranLibraryScreenState();
}

class _QuranLibraryScreenState extends State<QuranLibraryScreen> {
  List<SurahInfo>? _all;
  bool _missing = false;
  String _q = '';
  String _filter = 'All';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rm = ResourceManager.instance;
    await rm.load();
    await rm.loadFonts();
    final db = await QuranDb.open();
    if (db == null) {
      if (mounted) setState(() => _missing = true);
      return;
    }
    final list = await db.surahs();
    if (mounted) setState(() => _all = list);
  }

  List<SurahInfo> get _shown {
    final q = _q.trim().toLowerCase();
    return _all!.where((s) {
      if (_filter == 'Makki' && s.type != 'Meccan') return false;
      if (_filter == 'Madani' && s.type != 'Medinan') return false;
      if (q.isEmpty) return true;
      return s.number.toString() == q ||
          s.nameEn.toLowerCase().contains(q) ||
          s.meaning.toLowerCase().contains(q) ||
          s.nameAr.contains(_q.trim());
    }).toList();
  }

  Future<void> _open(SurahInfo s) async {
    final sel = await Navigator.of(context).push<VerseSelection>(
      MaterialPageRoute(builder: (_) => VerseSelectScreen(surah: s)),
    );
    if (sel == null || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Selection ready'),
        content: Text(
          '${s.nameEn}: ${sel.label}.\n\nThe project wizard that uses this '
          'selection arrives in the next batch.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Qur'an")),
      body: _body(),
    );
  }

  Widget _body() {
    if (_missing) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("The Qur'an data is not downloaded yet.", textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const ResourcesScreen()),
                  );
                  if (!mounted) return;
                  setState(() => _missing = false);
                  _load();
                },
                child: const Text('Open Resources'),
              ),
            ],
          ),
        ),
      );
    }
    if (_all == null) return const Center(child: CircularProgressIndicator());
    final list = _shown;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            onChanged: (v) => setState(() => _q = v),
            decoration: InputDecoration(
              hintText: 'Search surah name or number',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: KColors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _chip('All', 'All (${_all!.length})'),
              _chip('Makki', 'Makki'),
              _chip('Madani', 'Madani'),
            ],
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? const Center(child: Text('No surah found'))
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 16),
                  itemCount: list.length,
                  itemBuilder: (context, i) => _row(list[i]),
                ),
        ),
      ],
    );
  }

  Widget _chip(String value, String label) {
    final on = _filter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: on,
        selectedColor: KColors.selected,
        onSelected: (_) => setState(() => _filter = value),
      ),
    );
  }

  Widget _row(SurahInfo s) {
    return InkWell(
      onTap: () => _open(s),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: KColors.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: KColors.lavender,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('${s.number}', style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.nameEn, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(height: 2),
                  Text(
                    '${s.meaning}  -  ${s.ayahCount} verses',
                    style: const TextStyle(fontSize: 12, color: KColors.accent),
                  ),
                ],
              ),
            ),
            Text(
              s.nameAr,
              textDirection: TextDirection.rtl,
              style: const TextStyle(fontFamily: 'Amiri Quran', fontSize: 20),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}

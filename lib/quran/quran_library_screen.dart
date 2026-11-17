import 'package:flutter/material.dart';

import '../theme.dart';
import 'quran_db.dart';
import 'resource_manager.dart';
import 'resources_screen.dart';
import 'verse_select_screen.dart';

class QuranLibraryScreen extends StatefulWidget {
  const QuranLibraryScreen({super.key, this.pick = false});

  /// When true the chosen verses are returned to the caller instead of shown.
  final bool pick;

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
    if (widget.pick) {
      Navigator.of(context).pop(sel);
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Selection ready'),
        content: Text(
          '${s.nameEn}: ${sel.label}.\n\nTo make a video from it, use Create New Project on Home.',
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
      appBar: AppBar(centerTitle: true, title: const Text("Qur'an")),
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
              hintText: 'Search surah or verse...',
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
                  padding: const EdgeInsets.only(top: 8, bottom: 16),
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
      child: GestureDetector(
        onTap: () => setState(() => _filter = value),
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: on ? KColors.selected : KColors.lavender,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Text(
            label,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ),
      ),
    );
  }

  Widget _row(SurahInfo s) {
    const dark = Color(0xFF1B1633);
    const grey = Color(0xFF6B6785);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _open(s),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF6F4FB),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFE6DFFB),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${s.number}',
                style: const TextStyle(fontWeight: FontWeight.w700, color: dark),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.nameEn,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: dark),
                  ),
                  const SizedBox(height: 2),
                  Text(s.meaning, style: const TextStyle(fontSize: 12, color: grey)),
                  Text('${s.ayahCount} verses', style: const TextStyle(fontSize: 12, color: grey)),
                ],
              ),
            ),
            Text(
              s.nameAr,
              textDirection: TextDirection.rtl,
              style: const TextStyle(fontFamily: 'Amiri Quran', fontSize: 22, color: dark),
            ),
            const Icon(Icons.chevron_right, color: grey),
          ],
        ),
      ),
    );
  }
}

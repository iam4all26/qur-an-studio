import 'package:flutter/material.dart';

import '../theme.dart';
import 'quran_db.dart';

/// The verses chosen for a project: one surah and a sorted list of verse numbers.
class VerseSelection {
  VerseSelection(this.surah, this.ayahs);
  final SurahInfo surah;
  final List<int> ayahs;

  int get first => ayahs.first;
  int get last => ayahs.last;
  bool get isContiguous => ayahs.length == last - first + 1;

  String get label {
    if (ayahs.length == 1) return 'verse $first';
    if (isContiguous) return 'verses $first - $last';
    return '${ayahs.length} verses ($first - $last)';
  }
}

class VerseSelectScreen extends StatefulWidget {
  const VerseSelectScreen({super.key, required this.surah});
  final SurahInfo surah;

  @override
  State<VerseSelectScreen> createState() => _VerseSelectScreenState();
}

class _VerseSelectScreenState extends State<VerseSelectScreen> {
  List<VerseRow>? _verses;
  final Set<int> _selected = {};
  bool _byRange = false;
  final _from = TextEditingController(text: '1');
  final _to = TextEditingController();

  @override
  void initState() {
    super.initState();
    _to.text = '${widget.surah.ayahCount}';
    _load();
  }

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final db = await QuranDb.open();
    if (db == null) return;
    final rows = await db.verses(widget.surah.number, 1, widget.surah.ayahCount);
    if (!mounted) return;
    setState(() => _verses = rows);
  }

  void _applyRange() {
    final max = widget.surah.ayahCount;
    var a = int.tryParse(_from.text.trim()) ?? 1;
    var b = int.tryParse(_to.text.trim()) ?? max;
    a = a.clamp(1, max);
    b = b.clamp(1, max);
    if (b < a) {
      final t = a;
      a = b;
      b = t;
    }
    setState(() {
      _selected
        ..clear()
        ..addAll([for (var i = a; i <= b; i++) i]);
    });
  }

  String get _summary {
    if (_selected.isEmpty) return 'No verses selected';
    final list = _selected.toList()..sort();
    final n = list.length;
    return '$n ${n == 1 ? 'verse' : 'verses'} selected (${list.first} \u2013 ${list.last})';
  }

  void _next() {
    final list = _selected.toList()..sort();
    Navigator.of(context).pop(VerseSelection(widget.surah, list));
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.surah;
    return Scaffold(
      appBar: AppBar(centerTitle: true, title: Text('${s.nameEn} (${s.number})')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: KColors.lavender,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  _tab('Select Verses', !_byRange, () => setState(() => _byRange = false)),
                  _tab('By Range', _byRange, () => setState(() => _byRange = true)),
                ],
              ),
            ),
          ),
          if (_byRange) _rangeBox() else _quickRow(),
          Expanded(child: _list()),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF6F4FB),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.check_circle,
                    size: 20,
                    color: _selected.isEmpty ? const Color(0xFFB5B1C9) : KColors.selected,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _summary,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: Color(0xFF1B1633),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: KColors.selected,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: _selected.isEmpty ? null : _next,
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Next', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      SizedBox(width: 8),
                      Icon(Icons.arrow_forward, size: 18),
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

  Widget _tab(String label, bool on, VoidCallback tap) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: tap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? KColors.selected : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
        ),
      ),
    );
  }

  Widget _quickRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          TextButton(
            onPressed: () => setState(() {
              _selected
                ..clear()
                ..addAll([for (var i = 1; i <= widget.surah.ayahCount; i++) i]);
            }),
            child: const Text('Select all'),
          ),
          TextButton(
            onPressed: () => setState(_selected.clear),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  Widget _rangeBox() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          Expanded(child: _numField(_from, 'From verse')),
          const SizedBox(width: 12),
          Expanded(child: _numField(_to, 'To verse')),
          const SizedBox(width: 12),
          FilledButton(onPressed: _applyRange, child: const Text('Apply')),
        ],
      ),
    );
  }

  Widget _numField(TextEditingController c, String label) {
    return TextField(
      controller: c,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      onSubmitted: (_) => _applyRange(),
    );
  }

  Widget _list() {
    final verses = _verses;
    if (verses == null) return const Center(child: CircularProgressIndicator());
    return ListView.builder(
      itemCount: verses.length,
      itemBuilder: (context, i) {
        final v = verses[i];
        final on = _selected.contains(v.ayah);
        return InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => setState(() {
            on ? _selected.remove(v.ayah) : _selected.add(v.ayah);
          }),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF6F4FB),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: on ? KColors.selected : Colors.transparent, width: 1.5),
            ),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE6DFFB),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(
                    '${v.ayah}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1B1633),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    v.text,
                    textDirection: TextDirection.rtl,
                    style: const TextStyle(
                      fontFamily: 'Amiri Quran',
                      fontSize: 22,
                      height: 1.9,
                      color: Color(0xFF1B1633),
                    ),
                  ),
                ),
                Checkbox(
                  value: on,
                  activeColor: KColors.selected,
                  checkColor: Colors.white,
                  side: const BorderSide(color: Color(0xFF9A95B5), width: 1.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                  onChanged: (_) => setState(() {
                    on ? _selected.remove(v.ayah) : _selected.add(v.ayah);
                  }),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

import 'package:sqflite/sqflite.dart';

import 'resource_manager.dart';

class SurahInfo {
  SurahInfo(this.number, this.nameAr, this.nameEn, this.meaning, this.type, this.ayahCount);
  final int number;
  final String nameAr;
  final String nameEn;
  final String meaning;
  final String type;
  final int ayahCount;
}

class VerseRow {
  VerseRow(this.surah, this.ayah, this.text);
  final int surah;
  final int ayah;
  final String text;
}

/// Read-only access to quran.db. Verse text is returned exactly as stored.
/// Only the invisible byte order mark (U+FEFF) is removed, because it is not
/// part of the text.
class QuranDb {
  QuranDb._(this._db, this._hash);
  final Database _db;
  final String? _hash;
  static QuranDb? _instance;

  static String _clean(String s) => s.replaceAll('\uFEFF', '');

  static Future<QuranDb?> open() async {
    final rm = ResourceManager.instance;
    final existing = _instance;
    // Reopen when a newer quran.db has been downloaded since it was opened.
    if (existing != null && existing._hash == rm.installedHash('quran')) return existing;
    await close();
    final entry = rm.byId('quran');
    if (entry == null || !rm.isReady('quran')) return null;
    final db = await openDatabase(await rm.pathOf(entry), readOnly: true);
    _instance = QuranDb._(db, rm.installedHash('quran'));
    return _instance;
  }

  static Future<void> close() async {
    await _instance?._db.close();
    _instance = null;
  }

  Future<List<SurahInfo>> surahs() async {
    final rows = await _db.query('surahs', orderBy: 'number');
    return [
      for (final r in rows)
        SurahInfo(
          r['number'] as int,
          _clean(r['name_ar'] as String),
          r['name_en'] as String,
          r['name_en_translation'] as String,
          r['revelation_type'] as String,
          r['ayah_count'] as int,
        )
    ];
  }

  Future<List<VerseRow>> verses(int surah, int from, int to) async {
    final rows = await _db.query(
      'verses',
      where: 'surah = ? AND ayah >= ? AND ayah <= ?',
      whereArgs: [surah, from, to],
      orderBy: 'ayah',
    );
    return [
      for (final r in rows)
        VerseRow(surah, r['ayah'] as int, _clean(r['text'] as String)),
    ];
  }

  /// Number of verses in all earlier surahs. Translation files are one flat
  /// list in Qur'an order, so verse (surah, ayah) sits at offsetOf(surah) + ayah - 1.
  Future<int> offsetOf(int surah) async {
    final n = Sqflite.firstIntValue(
        await _db.rawQuery('SELECT COUNT(*) FROM verses WHERE surah < ?', [surah]));
    return n ?? 0;
  }

  Future<String> basmala() async {
    final rows = await _db.query('meta', where: 'key = ?', whereArgs: ['basmala']);
    return rows.isEmpty ? '' : _clean(rows.first['value'] as String);
  }

  /// Quick integrity check: 114 surahs, 6236 verses, per-surah counts match.
  Future<String?> selfCheck() async {
    final s = Sqflite.firstIntValue(await _db.rawQuery('SELECT COUNT(*) FROM surahs'));
    final v = Sqflite.firstIntValue(await _db.rawQuery('SELECT COUNT(*) FROM verses'));
    if (s != 114 || v != 6236) return 'Unexpected counts: $s surahs, $v verses';
    final bad = await _db.rawQuery(
        'SELECT s.number FROM surahs s WHERE s.ayah_count != '
        '(SELECT COUNT(*) FROM verses x WHERE x.surah = s.number)');
    if (bad.isNotEmpty) return 'Verse count mismatch in surah ${bad.first['number']}';
    // The Basmala must be stored once, not glued to the first verse of a surah.
    final bas = (await basmala()).split(' ');
    final firsts = await _db.query('verses',
        where: 'ayah = 1 AND surah NOT IN (1, 9)', orderBy: 'surah');
    for (final r in firsts) {
      final words = _clean(r['text'] as String).split(' ');
      if (words.length >= bas.length && words.take(bas.length).join(' ') == bas.join(' ')) {
        return 'The Basmala is attached to verse 1 of surah ${r['surah']}. '
            'Run the data build again and update the Qur\'an text.';
      }
    }
    return null;
  }
}

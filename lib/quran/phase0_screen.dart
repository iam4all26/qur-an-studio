import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:kainuwa_encoder/kainuwa_encoder.dart';

import '../app_state.dart';
import '../models.dart';
import '../scene_canvas.dart';
import '../screens/lesson_editor_screen.dart';
import '../stage_shape.dart';
import '../theme.dart';

/// Phase 0 proof of concept: one verse, Arabic text, optional translation, a
/// background and the verse audio, built into a normal project and opened in the
/// editor, where Export makes the MP4.
///
/// The text here comes from the AlQuran Cloud API at run time, only for this test.
/// The real app reads it from the checked quran.db built by the data repository.
class Phase0Screen extends StatefulWidget {
  const Phase0Screen({super.key});

  @override
  State<Phase0Screen> createState() => _Phase0ScreenState();
}

class _Reciter {
  const _Reciter(this.name, this.folder);
  final String name;
  final String folder;
}

const List<_Reciter> _reciters = [
  _Reciter('Alafasy', 'Alafasy_128kbps'),
  _Reciter('Husary', 'Husary_128kbps'),
  _Reciter('Abdul Basit (Murattal)', 'Abdul_Basit_Murattal_192kbps'),
  _Reciter('Maher Al Muaiqly', 'MaherAlMuaiqly128kbps'),
  _Reciter('As-Sudais', 'Abdurrahmaan_As-Sudais_192kbps'),
  _Reciter('Al-Ghamdi', 'Ghamadi_40kbps'),
];

const String _fontFamily = 'Amiri Quran';
const String _fontUrl = 'https://raw.githubusercontent.com/google/fonts/main/ofl/amiriquran/AmiriQuran-Regular.ttf';

class _Phase0ScreenState extends State<Phase0Screen> {
  final TextEditingController _surah = TextEditingController(text: '1');
  final TextEditingController _ayah = TextEditingController(text: '2');
  final TextEditingController _arabic = TextEditingController();
  final TextEditingController _english = TextEditingController();
  final TextEditingController _hausa = TextEditingController();

  int _reciter = 0;
  String _translation = 'english'; // none | english | hausa
  int _shapeIndex = 0; // 0 = 9:16, 1 = 16:9, 2 = 1:1

  String _audioPath = '';
  int _audioMs = 0;
  String _audioNote = '';
  bool _fontReady = false;
  String _fontNote = '';
  bool _busy = false;
  final List<String> _log = <String>[];

  @override
  void initState() {
    super.initState();
    unawaited(_loadFont(download: false));
  }

  @override
  void dispose() {
    _surah.dispose();
    _ayah.dispose();
    _arabic.dispose();
    _english.dispose();
    _hausa.dispose();
    super.dispose();
  }

  void _say(String line) {
    if (!mounted) return;
    setState(() {
      _log.insert(0, line);
      if (_log.length > 12) _log.removeLast();
    });
  }

  // ---------------------------------------------------------------- network

  Future<Uint8List> _get(String url) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set('User-Agent', 'QuranStudio/0.1');
      final response = await request.close().timeout(const Duration(seconds: 60));
      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode} for $url');
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(const Duration(seconds: 60))) {
        builder.add(chunk);
      }
      return builder.takeBytes();
    } finally {
      client.close(force: true);
    }
  }

  Future<Directory> _dir(String name) async {
    final base = await KainuwaEncoder.filesDir();
    final dir = Directory('$base/quran/$name');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  // ------------------------------------------------------------------- font

  Future<void> _loadFont({required bool download}) async {
    try {
      final dir = await _dir('fonts');
      final file = File('${dir.path}/AmiriQuran-Regular.ttf');
      if (!await file.exists()) {
        if (!download) return;
        _say('Downloading the Arabic font...');
        final bytes = await _get(_fontUrl);
        await file.writeAsBytes(bytes, flush: true);
      }
      final bytes = await file.readAsBytes();
      final loader = FontLoader(_fontFamily)
        ..addFont(Future<ByteData>.value(ByteData.sublistView(Uint8List.fromList(bytes))));
      await loader.load();
      if (!mounted) return;
      setState(() {
        _fontReady = true;
        _fontNote = 'Amiri Quran loaded';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _fontReady = false;
        _fontNote = 'Font not loaded: $e';
      });
    }
  }

  // ------------------------------------------------------------------ verse

  int? _int(TextEditingController c) => int.tryParse(c.text.trim());

  Future<List<Map<String, dynamic>>> _ayahEditions(int s, int a, String editions) async {
    final bytes = await _get('https://api.alquran.cloud/v1/ayah/$s:$a/editions/$editions');
    final json = jsonDecode(utf8.decode(bytes));
    if (json is! Map || json['data'] is! List) throw const FormatException('Unexpected answer from the API.');
    return [
      for (final item in json['data'] as List)
        if (item is Map<String, dynamic>) item,
    ];
  }

  String _edition(Map<String, dynamic> item) {
    final e = item['edition'];
    return e is Map ? '${e['identifier']}' : '';
  }

  Future<void> _fetchVerse() async {
    final s = _int(_surah);
    final a = _int(_ayah);
    if (s == null || a == null || s < 1 || s > 114 || a < 1) {
      _say('Enter a surah from 1 to 114 and a verse number.');
      return;
    }
    setState(() => _busy = true);
    try {
      _say('Fetching $s:$a ...');
      final main = await _ayahEditions(s, a, 'quran-uthmani,en.sahih');
      for (final item in main) {
        final id = _edition(item);
        final text = '${item['text'] ?? ''}';
        if (id == 'quran-uthmani') _arabic.text = text;
        if (id == 'en.sahih') _english.text = text;
      }
      try {
        final ha = await _ayahEditions(s, a, 'ha.gumi');
        if (ha.isNotEmpty) _hausa.text = '${ha.first['text'] ?? ''}';
      } catch (e) {
        _hausa.clear();
        _say('Hausa text not fetched ($e). You can paste it by hand.');
      }
      _say('Verse text received.');
    } catch (e) {
      _say('Could not fetch the verse: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ------------------------------------------------------------------ audio

  Future<void> _downloadAudio() async {
    final s = _int(_surah);
    final a = _int(_ayah);
    if (s == null || a == null) {
      _say('Enter the surah and verse first.');
      return;
    }
    setState(() => _busy = true);
    final code = '${s.toString().padLeft(3, '0')}${a.toString().padLeft(3, '0')}';
    final reciter = _reciters[_reciter];
    final url = 'https://everyayah.com/data/${reciter.folder}/$code.mp3';
    try {
      _say('Downloading audio: ${reciter.name} $s:$a ...');
      final dir = await _dir('audio');
      final file = File('${dir.path}/${reciter.folder}_$code.mp3');
      if (!await file.exists() || await file.length() == 0) {
        final bytes = await _get(url);
        await file.writeAsBytes(bytes, flush: true);
      }
      await _useAudio(file.path, 'Downloaded: ${reciter.name}');
    } catch (e) {
      _say('Audio download failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickAudio() async {
    try {
      final path = await KainuwaEncoder.pickAudio();
      if (path == null || path.isEmpty) return;
      await _useAudio(path, 'Your own file');
    } catch (e) {
      _say('Could not open the audio file: $e');
    }
  }

  Future<void> _useAudio(String path, String label) async {
    final ms = await KainuwaEncoder.audioDuration(path);
    if (!mounted) return;
    setState(() {
      _audioPath = path;
      _audioMs = ms;
      _audioNote = '$label, ${(ms / 1000).toStringAsFixed(1)} s';
    });
    _say(ms > 0 ? 'Audio ready: ${(ms / 1000).toStringAsFixed(1)} s.' : 'Audio saved but its length is unknown.');
  }

  // ------------------------------------------------------------------ build

  /// Splits long text into short lines so it fits the frame. Only line breaks are
  /// added; no letter or mark is changed.
  String _wrap(String text, int wordsPerLine) {
    final words = text.trim().split(RegExp(r'\s+'));
    final lines = <String>[];
    for (var i = 0; i < words.length; i += wordsPerLine) {
      lines.add(words.sublist(i, (i + wordsPerLine).clamp(0, words.length)).join(' '));
    }
    return lines.join('\n');
  }

  void _fit(Layer layer, double px, double maxW) {
    setLayerTextSizePx(layer, px);
    if (layer.w > maxW) {
      final f = maxW / layer.w;
      layer.w = maxW;
      layer.h = layer.h * f;
    }
  }

  Future<void> _build() async {
    final arabic = _arabic.text.trim();
    if (arabic.isEmpty) {
      _say('Fetch the verse first (or paste the Arabic text).');
      return;
    }
    if (_audioPath.isEmpty) {
      _say('Choose the audio first (download or your own file).');
      return;
    }
    setState(() => _busy = true);
    try {
      final state = AppScope.read(context);
      final shapes = const [(9, 16), (16, 9), (1, 1)];
      final (aw, ah) = shapes[_shapeIndex];
      final s = _int(_surah) ?? 0;
      final a = _int(_ayah) ?? 0;
      final ids = await state.addVideo(title: 'Verse $s:$a', aspectW: aw, aspectH: ah);
      final lesson = state.lessonById(ids.$1, ids.$2);
      if (lesson == null) throw StateError('The new project was not found.');

      Stage.use(aw, ah);
      final tall = ah > aw;
      final translation = _translation == 'english'
          ? _english.text.trim()
          : _translation == 'hausa'
              ? _hausa.text.trim()
              : '';

      final arabicLayer = Layer(
        id: newId(),
        type: 'text',
        text: _wrap(arabic, tall ? 4 : 8),
        cy: translation.isEmpty ? 0.5 : 0.38,
        color: 0xFFFFFFFF,
        bold: false,
        lineHeight: 1.7,
        fontFamily: _fontReady ? _fontFamily : '',
      );
      _fit(arabicLayer, tall ? 78 : 64, 0.9);

      final layers = <Layer>[arabicLayer];
      if (translation.isNotEmpty) {
        final tl = Layer(
          id: newId(),
          type: 'text',
          text: _wrap(translation, tall ? 5 : 11),
          cy: 0.7,
          color: 0xFFF6C101,
          bold: false,
          lineHeight: 1.3,
        );
        _fit(tl, tall ? 40 : 34, 0.88);
        layers.add(tl);
      }

      final scene = Scene(
        id: newId(),
        durationMs: (_audioMs > 0 ? _audioMs : 6000) + 800,
        bgType: 'color',
        bgValue: 0xFF0B3D2E.toString(),
        narrationPath: _audioPath,
        narrationMs: _audioMs,
        narrationClean: false,
        layers: layers,
      );
      lesson.scenes.add(scene);
      await state.persist();
      Stage.reset();

      if (!mounted) return;
      _say('Project built. Opening the editor: tap Export there.');
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => LessonEditorScreen(courseId: ids.$1, lessonId: ids.$2),
        ),
      );
    } catch (e) {
      Stage.reset();
      _say('Could not build the project: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // --------------------------------------------------------------------- UI

  Widget _field(TextEditingController c, String label, {int lines = 1, bool rtl = false, bool number = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        minLines: lines,
        maxLines: lines == 1 ? 1 : 6,
        textDirection: rtl ? TextDirection.rtl : null,
        keyboardType: number ? TextInputType.number : TextInputType.multiline,
        style: TextStyle(fontSize: rtl ? 22 : 15, fontFamily: rtl && _fontReady ? _fontFamily : null),
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      ),
    );
  }

  Widget _title(String text) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 8),
        child: Text(text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: KColors.gold)),
      );

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          const Text('Phase 0: one verse to MP4', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text(
            'Proof of concept. Fetch a verse, get its audio, build the project, then tap Export in the editor.',
            style: TextStyle(fontSize: 13),
          ),
          _title('1. Verse'),
          Row(
            children: [
              Expanded(child: _field(_surah, 'Surah (1-114)', number: true)),
              const SizedBox(width: 10),
              Expanded(child: _field(_ayah, 'Verse', number: true)),
            ],
          ),
          FilledButton.icon(
            onPressed: _busy ? null : _fetchVerse,
            icon: const Icon(Icons.cloud_download_outlined),
            label: const Text('Fetch verse text'),
          ),
          const SizedBox(height: 10),
          _field(_arabic, 'Arabic (Uthmani)', lines: 2, rtl: true),
          _field(_english, 'English (Sahih International)', lines: 2),
          _field(_hausa, 'Hausa (Gumi)', lines: 2),
          Wrap(
            spacing: 8,
            children: [
              for (final entry in const [('none', 'No translation'), ('english', 'English'), ('hausa', 'Hausa')])
                ChoiceChip(
                  label: Text(entry.$2),
                  selected: _translation == entry.$1,
                  onSelected: (_) => setState(() => _translation = entry.$1),
                ),
            ],
          ),
          _title('2. Arabic font'),
          Row(
            children: [
              Expanded(
                child: Text(_fontNote.isEmpty ? 'Using the phone font until Amiri Quran is downloaded.' : _fontNote,
                    style: const TextStyle(fontSize: 13)),
              ),
              OutlinedButton(
                onPressed: _busy ? null : () => _loadFont(download: true),
                child: Text(_fontReady ? 'Reload' : 'Download'),
              ),
            ],
          ),
          _title('3. Audio'),
          DropdownButtonFormField<int>(
            value: _reciter,
            decoration: const InputDecoration(labelText: 'Reciter', border: OutlineInputBorder()),
            items: [
              for (var i = 0; i < _reciters.length; i++) DropdownMenuItem(value: i, child: Text(_reciters[i].name)),
            ],
            onChanged: (v) => setState(() => _reciter = v ?? 0),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy ? null : _downloadAudio,
                  icon: const Icon(Icons.download),
                  label: const Text('Download verse audio'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _pickAudio,
                  icon: const Icon(Icons.audio_file_outlined),
                  label: const Text('My own audio'),
                ),
              ),
            ],
          ),
          if (_audioNote.isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 6), child: Text(_audioNote, style: const TextStyle(fontSize: 13))),
          _title('4. Video shape'),
          Wrap(
            spacing: 8,
            children: [
              for (final entry in const [(0, 'Vertical 9:16'), (1, 'Horizontal 16:9'), (2, 'Square 1:1')])
                ChoiceChip(
                  label: Text(entry.$2),
                  selected: _shapeIndex == entry.$1,
                  onSelected: (_) => setState(() => _shapeIndex = entry.$1),
                ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: _busy ? null : _build,
              child: _busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                  : const Text('Build project and open editor', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ),
          ),
          if (_log.isNotEmpty) ...[
            _title('Messages'),
            for (final line in _log) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(line, style: const TextStyle(fontSize: 12.5))),
          ],
        ],
      ),
    );
  }
}

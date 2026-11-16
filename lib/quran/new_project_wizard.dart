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
import 'quran_db.dart';
import 'quran_library_screen.dart';
import 'resource_manager.dart';
import 'templates.dart';
import 'verse_layers.dart';
import 'verse_select_screen.dart';

class _Rec {
  const _Rec(this.id, this.name, this.folder, this.urlTemplate);
  final String id;
  final String name;
  final String folder;
  final String urlTemplate;
}

const String _family = 'Amiri Quran';
const List<String> _steps = ['Details', 'Verses', 'Translation', 'Reciter', 'Template'];

class _Item {
  _Item(this.arabic, this.translation, this.audioCode);
  final String arabic;
  final String translation;
  final String audioCode;
}

/// Five-step wizard from the mockup. It builds one scene per verse (plus the
/// Basmala scene where the rules call for it) and opens the result in the editor.
class NewProjectWizard extends StatefulWidget {
  const NewProjectWizard({super.key, this.templateId});

  /// Template to preselect (from the Templates screen).
  final String? templateId;

  @override
  State<NewProjectWizard> createState() => _NewProjectWizardState();
}

class _NewProjectWizardState extends State<NewProjectWizard> {
  final rm = ResourceManager.instance;
  final _name = TextEditingController(text: 'My Qur\'an video');
  int _step = 0;
  int _shape = 0; // 0 = 9:16, 1 = 16:9, 2 = 1:1
  VerseSelection? _sel;
  bool _withTr = true;
  String _lang = 'en_sahih';
  List<_Rec> _recs = [];
  int _rec = 0;
  List<QTemplate> _tpls = [];
  int _look = 0;
  bool _busy = false;
  String _status = '';
  String? _error;

  static const _shapes = [(9, 16), (16, 9), (1, 1)];
  static const _shapeNames = ['Vertical 9:16', 'Horizontal 16:9', 'Square 1:1'];

  @override
  void initState() {
    super.initState();
    _loadReciters();
    _loadTemplates();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _loadTemplates() async {
    final list = await QTemplates.load();
    if (!mounted) return;
    setState(() {
      _tpls = list;
      final i = list.indexWhere((t) => t.id == widget.templateId);
      if (i >= 0) _look = i;
    });
  }

  Future<void> _loadReciters() async {
    await rm.load();
    final e = rm.byId('reciters');
    if (e == null || !rm.isReady('reciters')) return;
    try {
      final j = jsonDecode(await File(await rm.pathOf(e)).readAsString()) as Map<String, dynamic>;
      final list = <_Rec>[
        for (final r in (j['reciters'] as List))
          if ((r as Map)['verified'] == true)
            _Rec('${r['id']}', '${r['name']}', '${r['folder']}', '${r['per_ayah_url']}')
      ];
      if (mounted) setState(() => _recs = list);
    } catch (_) {}
  }

  // ------------------------------------------------------------- navigation

  bool get _canNext {
    switch (_step) {
      case 0:
        return _name.text.trim().isNotEmpty;
      case 1:
        return _sel != null;
      case 3:
        return _recs.isNotEmpty;
      default:
        return true;
    }
  }

  Future<void> _pickVerses() async {
    final sel = await Navigator.of(context).push<VerseSelection>(
      MaterialPageRoute(builder: (_) => const QuranLibraryScreen(pick: true)),
    );
    if (sel == null || !mounted) return;
    setState(() {
      _sel = sel;
      if (_name.text.trim().isEmpty || _name.text == 'My Qur\'an video') {
        _name.text = 'Surah ${sel.surah.nameEn}';
      }
    });
  }

  // ---------------------------------------------------------------- network

  Future<Uint8List> _get(String url) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set('User-Agent', 'QuranStudio/0.1');
      final res = await req.close().timeout(const Duration(seconds: 60));
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode} for $url');
      final out = BytesBuilder(copy: false);
      await for (final c in res.timeout(const Duration(seconds: 60))) {
        out.add(c);
      }
      return out.takeBytes();
    } finally {
      client.close(force: true);
    }
  }

  Future<String> _audio(_Rec r, String code) async {
    final base = await KainuwaEncoder.filesDir();
    final dir = Directory('$base/quran/audio');
    if (!await dir.exists()) await dir.create(recursive: true);
    final file = File('${dir.path}/${r.folder}_$code.mp3');
    if (!await file.exists() || await file.length() == 0) {
      final url = r.urlTemplate
          .replaceAll('{SSS}', code.substring(0, 3))
          .replaceAll('{AAA}', code.substring(3));
      await file.writeAsBytes(await _get(url), flush: true);
    }
    return file.path;
  }

  // ------------------------------------------------------------------ build

  String _wrap(String text, int wordsPerLine) {
    final words = text.trim().split(RegExp(r'\s+'));
    final lines = <String>[];
    for (var i = 0; i < words.length; i += wordsPerLine) {
      lines.add(words.sublist(i, (i + wordsPerLine).clamp(0, words.length)).join(' '));
    }
    return lines.join('\n');
  }

  int _lineCount(String s) => s.split('\n').length;

  double _scale(int lines, int maxLines) =>
      lines <= maxLines ? 1.0 : (maxLines / lines).clamp(0.4, 1.0);

  void _fit(Layer layer, double px, double maxW) {
    setLayerTextSizePx(layer, px);
    if (layer.w > maxW) {
      final f = maxW / layer.w;
      layer.w = maxW;
      layer.h = layer.h * f;
    }
  }

  String _code(int s, int a) => '${s.toString().padLeft(3, '0')}${a.toString().padLeft(3, '0')}';

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
      _status = 'Reading the Qur\'an data...';
    });
    var stageUsed = false;
    try {
      final sel = _sel!;
      final db = await QuranDb.open();
      if (db == null) throw StateError('The Qur\'an data is not downloaded. Open Library, Resources.');
      await rm.loadFonts();
      final fontOk = rm.isReady('AmiriQuran-Regular');
      final wanted = sel.ayahs.toSet();
      final rows = (await db.verses(sel.surah.number, sel.first, sel.last))
          .where((v) => wanted.contains(v.ayah))
          .toList();

      List<String>? tr;
      var offset = 0;
      if (_withTr) {
        final e = rm.byId(_lang);
        if (e == null || !rm.isReady(_lang)) {
          throw StateError('The translation is not downloaded. Open Library, Resources.');
        }
        final j = jsonDecode(await File(await rm.pathOf(e)).readAsString()) as Map<String, dynamic>;
        tr = [for (final v in (j['verses'] as List)) '$v'];
        if (tr.length != 6236) throw StateError('The translation file is incomplete.');
        offset = await db.offsetOf(sel.surah.number);
      }
      String trOf(int s, int a, int off) => tr == null ? '' : tr[off + a - 1];

      final items = <_Item>[];
      final surahNo = sel.surah.number;
      if (sel.first == 1 && surahNo != 1 && surahNo != 9) {
        items.add(_Item(await db.basmala(), tr == null ? '' : tr[0], _code(1, 1)));
      }
      for (final v in rows) {
        items.add(_Item(v.text, trOf(surahNo, v.ayah, offset), _code(surahNo, v.ayah)));
      }

      final rec = _recs[_rec];
      final paths = <String>[];
      final durations = <int>[];
      for (var i = 0; i < items.length; i++) {
        if (mounted) setState(() => _status = 'Preparing audio ${i + 1} of ${items.length}...');
        final p = await _audio(rec, items[i].audioCode);
        paths.add(p);
        durations.add(await KainuwaEncoder.audioDuration(p));
      }

      if (mounted) setState(() => _status = 'Building scenes...');
      final state = AppScope.read(context);
      final (aw, ah) = _shapes[_shape];
      final ids = await state.addVideo(title: _name.text.trim(), aspectW: aw, aspectH: ah);
      final lesson = state.lessonById(ids.$1, ids.$2);
      if (lesson == null) throw StateError('The new project was not found.');

      Stage.use(aw, ah);
      stageUsed = true;
      final tall = ah > aw;
      final look = _tpls[_look];
      for (var i = 0; i < items.length; i++) {
        final it = items[i];
        final dur = (durations[i] > 0 ? durations[i] : 6000) + 800;
        final layers = buildVerseLayers(
          arabic: it.arabic,
          translation: it.translation,
          tall: tall,
          durationMs: dur,
          look: look,
          fontFamily: fontOk ? _family : '',
        );
        lesson.scenes.add(Scene(
          id: newId(),
          durationMs: dur,
          bgType: 'asset',
          bgValue: look.assetFor(aw, ah),
          narrationPath: paths[i],
          narrationMs: durations[i],
          narrationClean: false,
          layers: layers,
        ));
      }
      await state.persist();
      Stage.reset();
      stageUsed = false;

      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => LessonEditorScreen(courseId: ids.$1, lessonId: ids.$2),
        ),
      );
    } catch (e) {
      if (stageUsed) Stage.reset();
      if (mounted) setState(() => _error = 'Could not create the project: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // --------------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('New Project')),
        body: Column(
          children: [
            _indicator(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_step == 0) ..._details(),
                  if (_step == 1) ..._verses(),
                  if (_step == 2) ..._translation(),
                  if (_step == 3) ..._reciter(),
                  if (_step == 4) ..._template(),
                  if (_busy) ...[
                    const SizedBox(height: 16),
                    const LinearProgressIndicator(),
                    const SizedBox(height: 8),
                    Text(_status),
                  ],
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    ),
                ],
              ),
            ),
            _footer(),
          ],
        ),
      ),
    );
  }

  Widget _indicator() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Row(
        children: [
          for (var i = 0; i < _steps.length; i++)
            Expanded(
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: i <= _step ? KColors.selected : KColors.surface,
                    child: Text('${i + 1}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(height: 4),
                  Text(_steps[i], style: const TextStyle(fontSize: 10), maxLines: 1),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _footer() {
    final last = _step == _steps.length - 1;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: const BoxDecoration(
        color: KColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            if (_step > 0)
              OutlinedButton(
                onPressed: _busy ? null : () => setState(() => _step--),
                child: const Text('Back'),
              ),
            if (_step > 0) const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: _busy || !_canNext
                    ? null
                    : () {
                        if (last) {
                          _create();
                        } else {
                          setState(() => _step++);
                        }
                      },
                child: Text(last ? 'Create video' : 'Next'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _details() => [
        const Text('Project name', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        TextField(
          controller: _name,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        const SizedBox(height: 20),
        const Text('Video format', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Row(
          children: [
            for (var i = 0; i < 3; i++)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: i < 2 ? 8 : 0),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => setState(() => _shape = i),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 6),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _shape == i ? KColors.selected.withValues(alpha: 0.25) : KColors.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: _shape == i ? KColors.selected : Colors.transparent),
                      ),
                      child: Text(_shapeNames[i], textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ];

  List<Widget> _verses() {
    final sel = _sel;
    return [
      const Text('Surah and verses', style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      if (sel != null)
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: KColors.surface, borderRadius: BorderRadius.circular(14)),
          child: Text('${sel.surah.nameEn} (${sel.surah.number}): ${sel.label}'),
        ),
      const SizedBox(height: 12),
      FilledButton(
        onPressed: _busy ? null : _pickVerses,
        child: Text(sel == null ? 'Choose surah and verses' : 'Change selection'),
      ),
      const SizedBox(height: 12),
      const Text(
        'When the selection starts at verse 1, the Basmala is added as its own first scene '
        '(not for Al-Fatihah, where it is verse 1, and not for At-Tawbah).',
        style: TextStyle(fontSize: 12, color: KColors.accent),
      ),
    ];
  }

  List<Widget> _translation() => [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Include translation'),
          value: _withTr,
          onChanged: (v) => setState(() => _withTr = v),
        ),
        if (_withTr) ...[
          const SizedBox(height: 8),
          RadioListTile<String>(
            contentPadding: EdgeInsets.zero,
            title: const Text('English: Sahih International'),
            value: 'en_sahih',
            groupValue: _lang,
            onChanged: (v) => setState(() => _lang = v!),
          ),
          RadioListTile<String>(
            contentPadding: EdgeInsets.zero,
            title: const Text('Hausa: Abu Bakr Gumi'),
            subtitle: const Text('QuranEnc.com, version 1.2.2'),
            value: 'ha_gumi',
            groupValue: _lang,
            onChanged: (v) => setState(() => _lang = v!),
          ),
        ],
      ];

  List<Widget> _reciter() {
    if (_recs.isEmpty) {
      return [
        const Text('The reciter list is not downloaded. Open Library, Resources, then come back.'),
      ];
    }
    return [
      const Text(
        'Each verse recording is downloaded once when you create the video, then kept on the phone.',
        style: TextStyle(fontSize: 12, color: KColors.accent),
      ),
      const SizedBox(height: 8),
      for (var i = 0; i < _recs.length; i++)
        RadioListTile<int>(
          contentPadding: EdgeInsets.zero,
          title: Text(_recs[i].name),
          value: i,
          groupValue: _rec,
          onChanged: (v) => setState(() => _rec = v!),
        ),
    ];
  }

  List<Widget> _template() {
    if (_tpls.isEmpty) return [const Center(child: CircularProgressIndicator())];
    return [
      GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.6,
        ),
        itemCount: _tpls.length,
        itemBuilder: (context, i) {
          final t = _tpls[i];
          return InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => setState(() => _look = i),
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _look == i ? KColors.gold : Colors.white24,
                  width: _look == i ? 3 : 1,
                ),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(t.portraitAsset, fit: BoxFit.cover, cacheWidth: 300),
                  Positioned(
                    left: 6,
                    bottom: 6,
                    child: Text(t.name,
                        style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white, fontSize: 12)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ];
  }
}

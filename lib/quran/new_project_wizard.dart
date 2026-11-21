import 'dart:math' as math;
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
import 'reciter_media.dart';
import 'resource_manager.dart';
import 'templates.dart';
import 'background_choice.dart';
import 'verse_layers.dart';
import 'verse_select_screen.dart';

class _Rec {
  const _Rec(this.id, this.name, this.folder, this.urlTemplate, [this.country = '', this.image = '']);
  final String country;
  final String image;
  final String id;
  final String name;
  final String folder;
  final String urlTemplate;
}

const String _family = 'Amiri Quran';
const List<String> _steps = ['Details', 'Verses', 'Translation', 'Reciter', 'Template', 'Style'];

class _Item {
  _Item(this.arabic, this.translation, this.audioCode, [this.label = '']);
  final String label;
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
  int _shape = 0; // 0 = 9:16, 1 = 16:9, 2 = 1:1, 3 = custom
  (int, int) _custom = (4, 5);
  String _align = 'center';
  VerseSelection? _sel;
  bool _withTr = true;
  bool _showFooter = true;
  bool _endMark = true;
  bool _darken = true;
  String _autoName = '';
  // Choices that replace the template's own look (null = use the template).
  String? _arFont;
  String? _trFont;
  int? _arColor;
  int? _trColor;
  double _sizeK = 1.0;
  BgChoice _bg = BgChoice();
  String _lang = 'en_sahih';
  List<_Rec> _recs = [];
  int _rec = 0;
  List<QTemplate> _tpls = [];
  int _look = 0;
  bool _busy = false;
  int _done = 0;
  int _total = 0;
  String _status = '';
  String? _error;

  static const _shapes = [(9, 16), (16, 9), (1, 1)];
  QTemplate get _effLook => _tpls[_look.clamp(0, _tpls.length - 1).toInt()].copyWith(
        arabicFont: _arFont,
        translationFont: _trFont,
        arabicColor: _arColor,
        translationColor: _trColor,
        scale: _sizeK,
      );

  (int, int) get _dims => _shape == 3 ? _custom : _shapes[_shape];

  @override
  void initState() {
    super.initState();
    _loadReciters();
    _loadTemplates();
  }

  @override
  void dispose() {
    ReciterPreview.stop();
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
            _Rec('${r['id']}', '${r['name']}', '${r['folder']}', '${r['per_ayah_url']}',
                '${r['country'] ?? ''}', '${r['image'] ?? ''}')
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
      case 4:
        return _bg.template || _bg.items.isNotEmpty;
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
      final rangeText = sel.first == sel.last ? '${sel.first}' : '${sel.first}-${sel.last}';
      final auto = 'Surah ${sel.surah.nameEn} $rangeText';
      // Replace the name when it is empty, the default, or the one made from an earlier selection.
      if (_name.text.trim().isEmpty || _name.text == 'My Qur\'an video' || _name.text == _autoName) {
        _name.text = auto;
      }
      _autoName = auto;
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

  /// Start and end (ms) of the audible part of a recording: silence at both ends is cut so
  /// verses follow each other without a gap.
  Future<(int, int)> _trim(String path, int total) async {
    if (total <= 0) return (0, 6000);
    try {
      final peaks = await KainuwaEncoder.audioPeaks(path, bins: 200);
      if (peaks.isEmpty) return (0, total);
      var top = 0.0;
      for (final p in peaks) {
        if (p > top) top = p;
      }
      if (top <= 0) return (0, total);
      final limit = top * 0.08;
      var first = 0;
      while (first < peaks.length - 1 && peaks[first] < limit) {
        first++;
      }
      var last = peaks.length - 1;
      while (last > first && peaks[last] < limit) {
        last--;
      }
      final bin = total / peaks.length;
      final start = math.max(0, (first * bin).round() - 40);
      final end = math.min(total, ((last + 1) * bin).round() + 60);
      if (end - start < 300) return (0, total);
      return (start, end);
    } catch (_) {
      return (0, total);
    }
  }

  String _code(int s, int a) => '${s.toString().padLeft(3, '0')}${a.toString().padLeft(3, '0')}';

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
      _total = 0;
      _done = 0;
      _status = 'Reading';
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
        items.add(_Item(v.text, trOf(surahNo, v.ayah, offset), _code(surahNo, v.ayah),
            '${sel.surah.nameEn} - $surahNo:${v.ayah}'));
      }

      final rec = _recs[_rec];
      final paths = <String>[];
      final durations = <int>[];
      final trims = <(int, int)>[];
      if (mounted) {
        setState(() {
          _total = items.length;
          _done = 0;
          _status = 'Downloading';
        });
      }
      for (var i = 0; i < items.length; i++) {
        final p = await _audio(rec, items[i].audioCode);
        paths.add(p);
        final total = await KainuwaEncoder.audioDuration(p);
        durations.add(total);
        trims.add(await _trim(p, total));
        if (mounted) setState(() => _done = i + 1);
      }

      if (mounted) setState(() => _status = 'Building');
      final plan = await BackgroundPlan.create(_bg);
      final bgProblem = plan.problem;
      if (bgProblem != null) throw StateError(bgProblem);
      final state = AppScope.read(context);
      final (aw, ah) = _dims;
      final ids = await state.addVideo(title: _name.text.trim(), aspectW: aw, aspectH: ah);
      final lesson = state.lessonById(ids.$1, ids.$2);
      if (lesson == null) throw StateError('The new project was not found.');
      final lookNow = _tpls[_look];
      lesson.qTemplate = lookNow.id;
      lesson.qReciter = _recs[_rec].id;
      lesson.qLang = _withTr ? _lang : '';
      lesson.qAlign = _align;
      lesson.qFooter = _showFooter;

      Stage.use(aw, ah);
      stageUsed = true;
      final tall = ah > aw;
      final look = _effLook;
      var pos = 0;
      for (var i = 0; i < items.length; i++) {
        final it = items[i];
        final dur = trims[i].$2 - trims[i].$1;
        final pauses = await versePauses(paths[i], durations[i], trims[i].$1, dur);
        final layers = buildVerseLayers(
          pauses: pauses,
          arabic: it.arabic,
          translation: it.translation,
          tall: tall,
          durationMs: dur,
          look: look,
          fontFamily: rm.familyIfReady(look.arabicFont, fallback: fontOk ? _family : ''),
          translationFont: rm.familyIfReady(look.translationFont),
          translationAlign: _align,
          footer: _showFooter && it.label.isNotEmpty ? it.label : null,
          endMark: _endMark && it.label.isNotEmpty ? int.parse(it.audioCode.substring(3)) : 0,
        );
        final made = plan.scenesFor(durationMs: dur, layers: layers, imageAsset: look.assetFor(aw, ah));
        for (final sc in made) {
          // Remember which verse this slide shows (the Basmala slide has an empty label and ayah 0).
          sc.qSurah = it.label.isEmpty ? surahNo : int.parse(it.audioCode.substring(0, 3));
          sc.qAyah = it.label.isEmpty ? 0 : int.parse(it.audioCode.substring(3));
          if (_darken) sc.layers.insert(0, darkOverlayLayer(sc.id, 0.5));
        }
        lesson.scenes.addAll(made);
        if (durations[i] > 0) {
          lesson.audioClips.add(AudioClip(
            id: newId(),
            path: paths[i],
            label: 'Verse',
            kind: 'voice',
            startMs: pos,
            trimMs: trims[i].$1,
            durationMs: dur,
            sourceMs: durations[i],
          ));
        }
        pos += dur;
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
      if (mounted) setState(() => _error = friendlyError(e, 'Could not create the project'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // --------------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_busy && _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_busy && _step > 0) setState(() {
          ReciterPreview.stop();
          _step--;
        });
      },
      child: Scaffold(
        appBar: AppBar(
          centerTitle: true,
          title: const Text('New Project'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _busy
                ? null
                : () {
                    if (_step > 0) {
                      setState(() {
          ReciterPreview.stop();
          _step--;
        });
                    } else {
                      Navigator.of(context).maybePop();
                    }
                  },
          ),
        ),
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
                  if (_step == 5) ..._style(),
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
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
      child: Row(
        children: [
          for (var i = 0; i < _steps.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _busy || i >= _step
                    ? null
                    : () => setState(() {
                          ReciterPreview.stop();
                          _step = i;
                        }),
                child: Column(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i <= _step ? KColors.selected : KColors.surface,
                      border: Border.all(
                        color: i == _step ? Colors.white : Colors.white24,
                        width: i == _step ? 2 : 1,
                      ),
                    ),
                    child: i < _step
                        ? const Icon(Icons.check, size: 16, color: Colors.white)
                        : Text('${i + 1}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    _steps[i],
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: i == _step ? FontWeight.w700 : FontWeight.w400,
                      color: i == _step ? Colors.white : Colors.white60,
                    ),
                    maxLines: 1,
                  ),
                ],
              ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _footer() {
    final last = _step == _steps.length - 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            if (_step > 0 && !_busy) ...[
              SizedBox(
                height: 52,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () => setState(() {
                    ReciterPreview.stop();
                    _step--;
                  }),
                  icon: const Icon(Icons.arrow_back, size: 20),
                  label: const Text('Back'),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: SizedBox(
          height: 52,
          child: _busy && last
              ? _progressButton()
              : FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: KColors.selected,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: _busy || !_canNext
                ? null
                : () {
                    if (last) {
                      _create();
                    } else {
                      setState(() {
          ReciterPreview.stop();
          _step++;
        });
                    }
                  },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(last ? 'Create video' : 'Next', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                if (!last) ...[const SizedBox(width: 8), const Icon(Icons.arrow_forward, size: 20)],
              ],
            ),
          ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The Create video button while the video is being made: it fills like a progress bar and
  /// shows how many recordings are done, for example "Downloading 3/12".
  Widget _progressButton() {
    final reading = _total == 0;
    final value = _total == 0 ? null : (_done / _total).clamp(0.0, 1.0).toDouble();
    final text = _status == 'Building'
        ? 'Building video...'
        : reading
            ? 'Reading the Qur\'an data...'
            : 'Downloading $_done/$_total';
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: KColors.surface),
          if (_status == 'Building')
            Container(color: KColors.selected)
          else if (value != null)
            Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: value,
                heightFactor: 1,
                child: Container(color: KColors.selected),
              ),
            )
          else
            const LinearProgressIndicator(backgroundColor: Colors.transparent),
          Center(
            child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
          ),
        ],
      ),
    );
  }

  /// A light card, as in the mockup, with dark text inside.
  Widget _whiteCard({required Widget child, EdgeInsets padding = const EdgeInsets.all(16)}) {
    return Theme(
      data: ThemeData.light(useMaterial3: true).copyWith(
        colorScheme: const ColorScheme.light(primary: KColors.selected),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF3F1FA),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        ),
      ),
      child: Builder(
        builder: (context) => Container(
          width: double.infinity,
          padding: padding,
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
          child: DefaultTextStyle.merge(style: const TextStyle(color: Color(0xFF1E1840)), child: child),
        ),
      ),
    );
  }

  Future<void> _askCustom() async {
    final w = TextEditingController(text: '${_custom.$1}');
    final h = TextEditingController(text: '${_custom.$2}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Custom size'),
        content: Row(
          children: [
            Expanded(child: TextField(controller: w, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Width'))),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text(':')),
            Expanded(child: TextField(controller: h, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Height'))),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Use this size')),
        ],
      ),
    );
    if (ok != true) return;
    final a = int.tryParse(w.text.trim()) ?? 0;
    final b = int.tryParse(h.text.trim()) ?? 0;
    // A ratio between 1:3 and 3:1 keeps the text and export sizes sensible.
    if (a < 1 || b < 1 || a > 100 || b > 100 || a / b > 3 || b / a > 3) {
      setState(() => _error = 'Use a ratio between 1:3 and 3:1, for example 4:5.');
      return;
    }
    setState(() {
      _error = null;
      _custom = (a, b);
      _shape = 3;
    });
  }

  List<Widget> _details() {
    const formats = [
      (Icons.smartphone, 'Vertical', '9:16'),
      (Icons.slideshow, 'Horizontal', '16:9'),
      (Icons.crop_square, 'Square', '1:1'),
    ];
    return [
      _whiteCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Project Details', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            const Text('Project Name', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextField(
              controller: _name,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(color: Color(0xFF1E1840)),
            ),
            const SizedBox(height: 16),
            const Text('Video Format (Aspect Ratio)', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              children: [
                for (var i = 0; i < 3; i++)
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(right: i < 2 ? 8 : 0),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => setState(() => _shape = i),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
                          decoration: BoxDecoration(
                            color: _shape == i ? const Color(0xFFEDE8FF) : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _shape == i ? KColors.selected : const Color(0xFFDDD8EE),
                              width: _shape == i ? 2 : 1,
                            ),
                          ),
                          child: Column(
                            children: [
                              Icon(formats[i].$1, size: 24, color: const Color(0xFF3A2C8F)),
                              const SizedBox(height: 6),
                              Text(formats[i].$2, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                              Text(formats[i].$3, style: const TextStyle(fontSize: 11.5)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _askCustom,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _shape == 3 ? const Color(0xFFEDE8FF) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _shape == 3 ? KColors.selected : const Color(0xFFDDD8EE),
                    width: _shape == 3 ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.settings_outlined, color: Color(0xFF3A2C8F)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Custom', style: TextStyle(fontWeight: FontWeight.w700)),
                          Text(
                            _shape == 3 ? '${_custom.$1}:${_custom.$2}' : 'Set your own size',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ];
  }

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

  List<Widget> _translation() {
    final editions = {
      for (final e in rm.translationEditions()) e.$1: (e.$2, e.$3),
    };
    final cur = editions[_lang] ?? editions.values.first;
    Widget label(String t) => Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 6),
          child: Text(t, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
        );
    Widget alignButton(String value, IconData icon) => Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => setState(() => _align = value),
              child: Container(
                height: 42,
                decoration: BoxDecoration(
                  color: _align == value ? KColors.selected : const Color(0xFFF3F1FA),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: _align == value ? Colors.white : const Color(0xFF3A2C8F)),
              ),
            ),
          ),
        );
    return [
      _whiteCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(child: Text('Include Translation', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
                Switch(value: _withTr, onChanged: (v) => setState(() => _withTr = v)),
              ],
            ),
            if (_withTr) ...[
              label('Translation language'),
              InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => _pickTranslation(editions),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: KColors.selected.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: KColors.selected.withOpacity(0.35)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: const BoxDecoration(color: KColors.selected, shape: BoxShape.circle),
                        child: const Icon(Icons.translate, color: Colors.white, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(cur.$1, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                            Text(cur.$2, style: const TextStyle(fontSize: 12.5)),
                          ],
                        ),
                      ),
                      Text('${editions.length} languages', style: const TextStyle(fontSize: 11.5)),
                      const SizedBox(width: 4),
                      const Icon(Icons.keyboard_arrow_right),
                    ],
                  ),
                ),
              ),
              if (_lang != 'en_sahih')
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text('Translation text from QuranEnc.com (credit shown in About).',
                      style: TextStyle(fontSize: 11.5)),
                ),
              if (!rm.isReady(_lang))
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text('This translation is not downloaded yet. Open Library, Resources to download it.',
                      style: TextStyle(fontSize: 11.5, color: KColors.accent)),
                ),
              label('Display Style'),
              Row(
                children: [
                  alignButton('left', Icons.format_align_left),
                  alignButton('center', Icons.format_align_center),
                  alignButton('right', Icons.format_align_right),
                ],
              ),
              label('Preview'),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: const Color(0xFFF3F1FA), borderRadius: BorderRadius.circular(12)),
                child: Column(
                  children: [
                    Text(
                      '\u062a\u064e\u0628\u064e\u0627\u0631\u064e\u0643\u064e \u0671\u0644\u0651\u064e\u0630\u0650\u064a \u0628\u0650\u064a\u064e\u062f\u0650\u0647\u0650 \u0671\u0644\u0652\u0645\u064f\u0644\u0652\u0643\u064f',
                      textDirection: TextDirection.rtl,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 22, fontFamily: rm.familyIfReady(_family, fallback: '')),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _lang == 'en_sahih' ? 'Blessed is He in whose hand is dominion' : '${cur.$1}: ${cur.$2}',
                      textAlign: _align == 'left'
                          ? TextAlign.left
                          : _align == 'right'
                              ? TextAlign.right
                              : TextAlign.center,
                      style: const TextStyle(fontSize: 13.5),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    ];
  }

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
      const SizedBox(height: 10),
      for (var i = 0; i < _recs.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => setState(() => _rec = i),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _rec == i ? KColors.selected : Colors.transparent, width: 2),
              ),
              child: Row(
                children: [
                  ReciterAvatar(id: _recs[i].id, name: _recs[i].name, image: _recs[i].image, radius: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_recs[i].name,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Color(0xFF1E1840), fontWeight: FontWeight.w800, fontSize: 14.5, height: 1.2)),
                        Text(
                            _recs[i].country.isEmpty ? "Complete Qur'an" : "Complete Qur'an  \u2022  ${_recs[i].country}",
                            style: const TextStyle(color: Color(0xFF6B648F), fontSize: 12.5)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  ReciterPreviewButton(id: _recs[i].id, urlTemplate: _recs[i].urlTemplate),
                  const SizedBox(width: 10),
                  Icon(
                    _rec == i ? Icons.check_circle : Icons.radio_button_unchecked,
                    color: _rec == i ? KColors.selected : const Color(0xFFB9B2D8),
                  ),
                ],
              ),
            ),
          ),
        ),
    ];
  }

  List<Widget> _template() {
    if (_tpls.isEmpty) return [const Center(child: CircularProgressIndicator())];
    return [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Show surah and verse at the bottom'),
        value: _showFooter,
onChanged: (v) => setState(() => _showFooter = v),
      ),
      const Padding(
        padding: EdgeInsets.only(top: 6, bottom: 6),
        child: Text('Background', style: TextStyle(fontWeight: FontWeight.w800, color: KColors.gold)),
      ),
      BackgroundChooser(choice: _bg, onChanged: (c) => setState(() => _bg = c)),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Darken the background (50%)'),
        subtitle: const Text('Keeps the text readable. It can be changed later in the editor.',
            style: TextStyle(fontSize: 11.5)),
        value: _darken,
        onChanged: (v) => setState(() => _darken = v),
      ),
      const SizedBox(height: 12),
      if (!_bg.template) ...[
        const Text('Text style', style: TextStyle(fontWeight: FontWeight.w800, color: KColors.gold)),
        const SizedBox(height: 6),
        DropdownButtonFormField<int>(
          value: _look.clamp(0, _tpls.length - 1).toInt(),
          isExpanded: true,
          items: [
            for (var i = 0; i < _tpls.length; i++) DropdownMenuItem(value: i, child: Text(_tpls[i].name)),
          ],
          onChanged: (v) => setState(() => _look = v ?? _look),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text('Fonts, colours and sizes of the chosen template are used for the text. '
              'Pick the Template tab above to see the template pictures.',
              style: TextStyle(fontSize: 11.5, color: Colors.white60)),
        ),
      ],
      if (_bg.template) ...[
      const Text('Template', style: TextStyle(fontWeight: FontWeight.w800, color: KColors.gold)),
      const SizedBox(height: 8),
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
                  Image.asset(t.previewFor(_dims.$1, _dims.$2), fit: BoxFit.cover, cacheWidth: 300),
                  Center(
                    child: Text(
                      '\u0628\u0650\u0633\u0652\u0645\u0650 \u0671\u0644\u0644\u0651\u064e\u0647\u0650',
                      textDirection: TextDirection.rtl,
                      style: TextStyle(
                        fontSize: 18,
                        color: Color(t.arabicColor),
                        fontFamily: ResourceManager.instance.familyIfReady(t.arabicFont, fallback: _family),
                      ),
                    ),
                  ),
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
      ],
    ];
  }

  /// Step six: fonts, colours, size and the live preview.
  List<Widget> _style() {
    if (_tpls.isEmpty) return [const Center(child: CircularProgressIndicator())];
    return [_stylePreview()];
  }

  /// A searchable list of translations: language, translator and whether it is downloaded.
  Future<void> _pickTranslation(Map<String, (String, String)> editions) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) {
        var query = '';
        return StatefulBuilder(
          builder: (c, setSheet) {
            final list = [
              for (final e in editions.entries)
                if (query.isEmpty ||
                    e.value.$1.toLowerCase().contains(query) ||
                    e.value.$2.toLowerCase().contains(query))
                  e,
            ];
            return SizedBox(
              height: MediaQuery.of(c).size.height * 0.75,
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Translation language', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: TextField(
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Search language or translator',
                      ),
                      onChanged: (v) => setSheet(() => query = v.trim().toLowerCase()),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (c, i) {
                        final e = list[i];
                        final on = e.key == _lang;
                        final ready = rm.isReady(e.key);
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: on ? KColors.selected : KColors.selected.withOpacity(0.15),
                            child: Text(
                              e.value.$1.substring(0, 1),
                              style: TextStyle(color: on ? Colors.white : KColors.selected, fontWeight: FontWeight.w800),
                            ),
                          ),
                          title: Text(e.value.$1, style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(e.value.$2, maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: on
                              ? const Icon(Icons.check_circle, color: KColors.selected)
                              : Text(ready ? 'Ready' : 'Download first', style: const TextStyle(fontSize: 11.5)),
                          onTap: () => Navigator.of(c).pop(e.key),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    if (picked != null && mounted) setState(() => _lang = picked);
  }

  static const _palette = <int>[
    0xFFFFFFFF, 0xFFFFF4D6, 0xFFF6C101, 0xFFE8C96A, 0xFFFFD9C7, 0xFFBDEBD8,
    0xFFBFE0FF, 0xFFB9C4F5, 0xFF6B4A1E, 0xFF3B2410, 0xFF2B1B08, 0xFF000000,
  ];

  Widget _swatches(int? current, int fallback, ValueChanged<int> onPick) {
    final cur = current ?? fallback;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final c in _palette)
          InkWell(
            onTap: () => onPick(c),
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: Color(c),
                shape: BoxShape.circle,
                border: Border.all(color: cur == c ? KColors.gold : Colors.white30, width: cur == c ? 3 : 1),
              ),
            ),
          ),
      ],
    );
  }

  /// Fonts, colours and size chosen by the person; they replace the template's own values.
  List<Widget> _textOptions() {
    final rm = ResourceManager.instance;
    final base = _tpls[_look.clamp(0, _tpls.length - 1).toInt()];
    const latin = {'Noto Sans', 'Noto Serif', 'Lora', 'Poppins'};
    final fonts = rm.readyFonts();
    final arFonts = [for (final f in fonts) if (!latin.contains(f)) f];
    final trFonts = [for (final f in fonts) if (latin.contains(f)) f];
    String? valid(String? v, String fallback, List<String> list) {
      final x = v ?? fallback;
      return list.contains(x) ? x : null;
    }

    Widget drop(String label, String? value, List<String> list, ValueChanged<String?> on) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: DropdownButtonFormField<String>(
            value: value,
            isExpanded: true,
            decoration: InputDecoration(labelText: label),
            items: [
              for (final f in list)
                DropdownMenuItem(value: f, child: Text(f, style: TextStyle(fontFamily: f))),
            ],
            onChanged: on,
          ),
        );

    return [
      const Text('Customize text', style: TextStyle(fontWeight: FontWeight.w800, color: KColors.gold)),
      const SizedBox(height: 6),
      drop('Arabic font', valid(_arFont, base.arabicFont, arFonts), arFonts, (v) => setState(() => _arFont = v)),
      if (_withTr)
        drop('Translation font', valid(_trFont, base.translationFont, trFonts), trFonts,
            (v) => setState(() => _trFont = v)),
      if (arFonts.length < 2)
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text('More fonts appear here after they are downloaded in Library, Resources.',
              style: TextStyle(fontSize: 11.5, color: Colors.white60)),
        ),
      const Text('Arabic colour', style: TextStyle(fontSize: 12.5)),
      const SizedBox(height: 4),
      _swatches(_arColor, base.arabicColor, (c) => setState(() => _arColor = c)),
      if (_withTr) ...[
        const SizedBox(height: 8),
        const Text('Translation colour', style: TextStyle(fontSize: 12.5)),
        const SizedBox(height: 4),
        _swatches(_trColor, base.translationColor, (c) => setState(() => _trColor = c)),
      ],
      const SizedBox(height: 8),
      Row(
        children: [
          const Text('Text size', style: TextStyle(fontSize: 12.5)),
          Expanded(
            child: Slider(
              value: _sizeK,
              min: 0.7,
              max: 1.3,
              divisions: 12,
              label: '${(_sizeK * 100).round()}%',
              onChanged: (v) => setState(() => _sizeK = v),
            ),
          ),
        ],
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Show the end-of-verse sign with the verse number'),
        value: _endMark,
        onChanged: (v) => setState(() => _endMark = v),
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: () => setState(() {
            _arFont = null;
            _trFont = null;
            _arColor = null;
            _trColor = null;
            _sizeK = 1.0;
          }),
          child: const Text('Reset to the template look'),
        ),
      ),
      const SizedBox(height: 6),
    ];
  }

  /// Shows the chosen template's fonts, colours and shadow on a sample verse, in the shape of
  /// the video, so the look can be checked before the video is made.
  Widget _stylePreview() {
    final t = _effLook;
    final rm = ResourceManager.instance;
    final (w, h) = _dims;
    final ar = rm.familyIfReady(t.arabicFont, fallback: _family);
    final tr = rm.familyIfReady(t.translationFont);
    final shadows = t.shadow
        ? [Shadow(color: Color(t.shadowColor), blurRadius: 6, offset: const Offset(1, 2))]
        : <Shadow>[];
    final ratio = (w / h).clamp(0.45, 2.0).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ..._textOptions(),
        const Text('Font preview', style: TextStyle(fontWeight: FontWeight.w800, color: KColors.gold)),
        const SizedBox(height: 6),
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: ratio < 1 ? 220 : 340),
            child: AspectRatio(
              aspectRatio: ratio,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_bg.template)
                      Image.asset(t.assetFor(w, h), fit: BoxFit.cover, cacheWidth: 600)
                    else
                      Container(color: const Color(0xFF14121F)),
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '\u062a\u064e\u0628\u064e\u0627\u0631\u064e\u0643\u064e \u0671\u0644\u0651\u064e\u0630\u0650\u064a \u0628\u0650\u064a\u064e\u062f\u0650\u0647\u0650 \u0671\u0644\u0652\u0645\u064f\u0644\u0652\u0643\u064f${_endMark ? '\u00A0\u06DD\u0661' : ''}',
                              textDirection: TextDirection.rtl,
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 22 * _sizeK, height: 1.6, color: Color(t.arabicColor), fontFamily: ar, shadows: shadows),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Blessed is He in whose hand is dominion',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12.5, color: Color(t.translationColor), fontFamily: tr, shadows: shadows),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text('Arabic: ${t.arabicFont.isEmpty ? 'default' : t.arabicFont}   Translation: ${t.translationFont.isEmpty ? 'default' : t.translationFont}',
            style: const TextStyle(fontSize: 11.5, color: Colors.white60)),
      ],
    );
  }
}

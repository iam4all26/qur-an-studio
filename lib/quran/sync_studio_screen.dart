import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:kainuwa_encoder/kainuwa_encoder.dart';

import '../app_state.dart';
import '../models.dart';
import '../scene_canvas.dart';
import '../screens/lesson_editor_screen.dart';
import '../stage_shape.dart';
import '../theme.dart';
import 'ai_settings_screen.dart';
import 'ai_sync.dart';
import 'quran_db.dart';
import 'quran_library_screen.dart';
import 'resource_manager.dart';
import 'templates.dart';
import 'verse_select_screen.dart';
import 'background_choice.dart';
import 'verse_layers.dart';

const String _family = 'Amiri Quran';
const String _clipId = 'sync_preview';
const int _minGapMs = 100;
const int _peakSpanMs = 300000; // the native waveform covers the first 5 minutes

/// Sync studio (mockup screen 10). The user brings a recording that holds several
/// verses, marks where each verse starts and ends, and the app builds a project with
/// one scene per verse over one continuous audio clip.
///
/// Boundaries: with n verses there are n + 1 boundaries b[0..n]. Verse i plays from
/// b[i] to b[i + 1], so there are never gaps or overlaps between verses.
class SyncStudioScreen extends StatefulWidget {
  const SyncStudioScreen({super.key});

  @override
  State<SyncStudioScreen> createState() => _SyncStudioScreenState();
}

class _SyncStudioScreenState extends State<SyncStudioScreen> {
  final rm = ResourceManager.instance;
  final TextEditingController _name = TextEditingController(text: 'My synced video');

  // Setup
  VerseSelection? _selection;
  String _audio = '';
  int _total = 0;
  int _shape = 0;
  String _tr = 'none'; // none | en_sahih | ha_gumi
  bool _footer = true;
  BgChoice _bg = BgChoice();
  List<QTemplate> _tpls = [];
  int _look = 0;
  bool _busy = false;
  String _status = '';
  String? _error;

  // Sync
  bool _syncing = false;
  List<VerseRow> _rows = [];
  List<double> _peaks = const [];
  List<int> _b = [];
  int _cur = 0;
  int _pos = 0;
  int _win = 0;
  bool _playing = false;
  int _playFrom = 0;
  int? _stopAt;
  Timer? _tick;
  final Stopwatch _sw = Stopwatch();
  String _note = '';

  static const _shapes = [(9, 16), (16, 9), (1, 1)];
  static const _shapeNames = ['Vertical 9:16', 'Horizontal 16:9', 'Square 1:1'];

  @override
  void initState() {
    super.initState();
    QTemplates.load().then((list) {
      if (mounted) setState(() => _tpls = list);
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    KainuwaEncoder.stopClip(_clipId);
    _name.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------ setup

  Future<void> _pickVerses() async {
    final sel = await Navigator.of(context).push<VerseSelection>(
      MaterialPageRoute(builder: (_) => const QuranLibraryScreen(pick: true)),
    );
    if (sel == null || !mounted) return;
    setState(() {
      _selection = sel;
      if (_name.text.trim().isEmpty || _name.text == 'My synced video') {
        _name.text = 'Surah ${sel.surah.nameEn}';
      }
    });
  }

  Future<void> _pickAudio() async {
    try {
      final path = await KainuwaEncoder.pickAudio();
      if (path == null || path.isEmpty) return;
      final ms = await KainuwaEncoder.audioDuration(path);
      if (!mounted) return;
      if (ms <= 0) {
        setState(() => _error = 'The length of this audio file could not be read.');
        return;
      }
      setState(() {
        _audio = path;
        _total = ms;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not open the audio file: $e');
    }
  }

  Future<void> _startSync() async {
    final sel = _selection;
    if (sel == null || _audio.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
      _status = 'Reading the verses...';
    });
    try {
      final db = await QuranDb.open();
      if (db == null) throw StateError('The Qur\'an data is not downloaded. Open Library, Resources.');
      final wanted = sel.ayahs.toSet();
      final rows = (await db.verses(sel.surah.number, sel.first, sel.last))
          .where((v) => wanted.contains(v.ayah))
          .toList();
      if (rows.isEmpty) throw StateError('No verses were found.');
      if (mounted) setState(() => _status = 'Reading the waveform...');
      var peaks = const <double>[];
      try {
        peaks = await KainuwaEncoder.audioPeaks(_audio, bins: 1500);
      } catch (_) {}
      final n = rows.length;
      final b = <int>[for (var i = 0; i <= n; i++) (_total * i / n).round()];
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _peaks = peaks;
        _b = b;
        _cur = 0;
        _pos = b[0];
        _win = 0;
        _note = 'Boundaries start evenly spread. Play, then set each verse start and end.';
        _syncing = true;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // --------------------------------------------------------------- playback

  int get _winMs => math.min(20000, _total);

  void _followWindow() {
    final span = _winMs;
    if (_pos < _win || _pos > _win + span * 0.9) {
      _win = (_pos - span * 0.1).round().clamp(0, math.max(0, _total - span)).toInt();
    }
  }

  Future<void> _play({int? stopAt}) async {
    await _stopSound();
    var from = _pos.clamp(0, _total).toInt();
    if (from >= _total - 50) from = 0;
    _playFrom = from;
    _stopAt = stopAt;
    try {
      await KainuwaEncoder.playClip(_clipId, _audio, seekMs: from);
    } catch (e) {
      if (mounted) setState(() => _note = 'Could not play: $e');
      return;
    }
    _sw
      ..reset()
      ..start();
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(milliseconds: 40), (_) {
      final p = _playFrom + _sw.elapsedMilliseconds;
      final end = _stopAt ?? _total;
      if (p >= end) {
        _pause(at: end);
        return;
      }
      if (!mounted) return;
      setState(() {
        _pos = p;
        _followWindow();
      });
    });
    if (mounted) setState(() => _playing = true);
  }

  Future<void> _stopSound() async {
    _tick?.cancel();
    _sw.stop();
    try {
      await KainuwaEncoder.stopClip(_clipId);
    } catch (_) {}
  }

  Future<void> _pause({int? at}) async {
    await _stopSound();
    if (!mounted) return;
    setState(() {
      _playing = false;
      if (at != null) _pos = at.clamp(0, _total).toInt();
      _followWindow();
    });
  }

  void _seek(int ms, {bool follow = true}) {
    final target = ms.clamp(0, _total).toInt();
    if (_playing) {
      _pos = target;
      _play(stopAt: _stopAt);
      return;
    }
    setState(() {
      _pos = target;
      if (follow) _followWindow();
    });
  }

  void _selectVerse(int i) {
    final index = i.clamp(0, _rows.length - 1).toInt();
    setState(() {
      _cur = index;
      _note = '';
    });
    _seek(_b[index]);
  }

  // ------------------------------------------------------------ boundaries

  void _setStart() {
    final i = _cur;
    final lo = i == 0 ? 0 : _b[i - 1] + _minGapMs;
    final hi = _b[i + 1] - _minGapMs;
    if (_pos < lo || _pos > hi) {
      setState(() => _note = 'The start of verse ${i + 1} must be between ${_fmt(lo)} and ${_fmt(hi)}.');
      return;
    }
    setState(() {
      _b = [..._b]..[i] = _pos;
      _note = 'Verse ${i + 1} starts at ${_fmt(_pos)}.';
    });
  }

  void _setEnd() {
    final j = _cur + 1;
    final lo = _b[_cur] + _minGapMs;
    final hi = j < _rows.length ? _b[j + 1] - _minGapMs : _total;
    if (_pos < lo || _pos > hi) {
      setState(() => _note = 'The end of verse ${_cur + 1} must be between ${_fmt(lo)} and ${_fmt(hi)}.');
      return;
    }
    setState(() {
      _b = [..._b]..[j] = _pos;
      _note = 'Verse ${_cur + 1} ends at ${_fmt(_pos)}.';
    });
  }

  Future<void> _autoSync() async {
    await _pause();
    final cfg = AiConfig.instance;
    await cfg.load();
    final provider = cfg.active;
    if (!mounted) return;
    if (provider == null) {
      final go = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Auto Sync'),
          content: const Text(
            'Auto Sync uses an AI service to find where each verse starts. Add the API key of a service '
            'you have an account with (OpenAI, Groq, Gemini or another).',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Not now')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Add API key')),
          ],
        ),
      );
      if (go == true && mounted) {
        await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AiSettingsScreen()));
      }
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Auto Sync'),
        content: Text(
          'The recording will be sent to ${provider.name} (model ${cfg.modelOf(provider.id)}) to find where each '
          'verse starts. The service may charge you for it. Your current marks are replaced; you can then adjust them.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Send and sync')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (c) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('Auto Sync'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const LinearProgressIndicator(),
              const SizedBox(height: 12),
              Text('Waiting for ${provider.name}. This can take a minute or more.'),
            ],
          ),
        ),
      ),
    );
    AiSyncResult? result;
    String? failure;
    try {
      result = await AiSync.run(
        provider: provider,
        config: cfg,
        audioPath: _audio,
        totalMs: _total,
        verses: [for (final r in _rows) r.text],
      );
    } catch (e) {
      failure = '$e';
    }
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    final r = result;
    if (r == null || r.boundaries.length != _rows.length + 1) {
      setState(() => _note = 'Auto Sync failed: ${failure ?? 'unexpected answer'}');
      return;
    }
    setState(() {
      _b = r.boundaries;
      _cur = 0;
      _pos = _b[0];
      _win = 0;
      _note = r.note;
    });
  }

  String _fmt(int ms) {
    final m = ms ~/ 60000;
    final s = (ms % 60000) ~/ 1000;
    final r = ms % 1000;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}.${r.toString().padLeft(3, '0')}';
  }

  // ----------------------------------------------------------------- create

  String _wrap(String text, int wordsPerLine) {
    final words = text.trim().split(RegExp(r'\s+'));
    final lines = <String>[];
    for (var i = 0; i < words.length; i += wordsPerLine) {
      lines.add(words.sublist(i, (i + wordsPerLine).clamp(0, words.length)).join(' '));
    }
    return lines.join('\n');
  }

  int _lineCount(String s) => s.split('\n').length;

  double _scale(int lines, int maxLines) => lines <= maxLines ? 1.0 : (maxLines / lines).clamp(0.4, 1.0);

  void _fit(Layer layer, double px, double maxW) {
    setLayerTextSizePx(layer, px);
    if (layer.w > maxW) {
      final f = maxW / layer.w;
      layer.w = maxW;
      layer.h = layer.h * f;
    }
  }

  Future<void> _create() async {
    final n = _rows.length;
    for (var i = 0; i < n; i++) {
      if (_b[i + 1] - _b[i] < 300) {
        setState(() => _note = 'Verse ${i + 1} is shorter than 0.3 seconds. Fix its start or end.');
        return;
      }
    }
    await _pause();
    setState(() {
      _busy = true;
      _error = null;
      _status = 'Building the project...';
    });
    var stageUsed = false;
    try {
      final sel = _selection!;
      final plan = await BackgroundPlan.create(_bg);
      final bgProblem = plan.problem;
      if (bgProblem != null) throw StateError(bgProblem);
      final db = await QuranDb.open();
      if (db == null) throw StateError('The Qur\'an data is not downloaded.');
      await rm.loadFonts();
      final fontOk = rm.isReady('AmiriQuran-Regular');

      List<String>? tr;
      var offset = 0;
      if (_tr != 'none') {
        final e = rm.byId(_tr);
        if (e == null || !rm.isReady(_tr)) {
          throw StateError('The translation is not downloaded. Open Library, Resources.');
        }
        final j = jsonDecode(await File(await rm.pathOf(e)).readAsString()) as Map<String, dynamic>;
        tr = [for (final v in (j['verses'] as List)) '$v'];
        if (tr.length != 6236) throw StateError('The translation file is incomplete.');
        offset = await db.offsetOf(sel.surah.number);
      }

      final state = AppScope.read(context);
      final (aw, ah) = _shapes[_shape];
      final ids = await state.addVideo(title: _name.text.trim(), aspectW: aw, aspectH: ah);
      final lesson = state.lessonById(ids.$1, ids.$2);
      if (lesson == null) throw StateError('The new project was not found.');

      Stage.use(aw, ah);
      stageUsed = true;
      final tall = ah > aw;
      final look = _tpls[_look];
      for (var i = 0; i < n; i++) {
        final v = _rows[i];
        final translation = tr == null ? '' : tr[offset + v.ayah - 1];
        final layers = buildVerseLayers(
          arabic: v.text,
          translation: translation,
          tall: tall,
          durationMs: _b[i + 1] - _b[i],
          look: look,
          fontFamily: rm.familyIfReady(look.arabicFont, fallback: fontOk ? _family : ''),
          translationFont: rm.familyIfReady(look.translationFont),
          footer: _footer ? '${sel.surah.nameEn} - ${sel.surah.number}:${v.ayah}' : null,
        );
        final made = plan.scenesFor(
          durationMs: _b[i + 1] - _b[i],
          layers: layers,
          imageAsset: look.assetFor(aw, ah),
        );
        for (final sc in made) {
          sc.layers.insert(0, darkOverlayLayer(sc.id, 0.5));
        }
        lesson.scenes.addAll(made);
      }
      lesson.audioClips.add(AudioClip(
        id: newId(),
        path: _audio,
        label: 'Recording',
        kind: 'voice',
        startMs: 0,
        trimMs: _b[0],
        durationMs: _b[n] - _b[0],
        sourceMs: _total,
      ));
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
        appBar: AppBar(
          title: Text(_syncing ? 'Synchronize Verses' : 'Sync my recording'),
          leading: _syncing
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () async {
                    await _pause();
                    if (mounted) setState(() => _syncing = false);
                  },
                )
              : null,
        ),
        body: _syncing ? _syncBody() : _setupBody(),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 8),
        child: Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: KColors.gold)),
      );

  Widget _setupBody() {
    final sel = _selection;
    final ready = sel != null && _audio.isNotEmpty && _tpls.isNotEmpty && !_busy;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Use a recording that holds several verses. You mark where each verse starts and ends, '
          'and the app builds the video.',
          style: TextStyle(fontSize: 13),
        ),
        _label('Project name'),
        TextField(controller: _name, decoration: const InputDecoration(border: OutlineInputBorder())),
        _label('Verses'),
        OutlinedButton.icon(
          onPressed: _busy ? null : _pickVerses,
          icon: const Icon(Icons.menu_book_outlined),
          label: Text(sel == null ? 'Choose surah and verses' : 'Surah ${sel.surah.nameEn}, ${sel.label}'),
        ),
        _label('Recording'),
        OutlinedButton.icon(
          onPressed: _busy ? null : _pickAudio,
          icon: const Icon(Icons.audio_file_outlined),
          label: Text(_audio.isEmpty ? 'Choose audio file' : 'Audio ready, ${_fmt(_total)}'),
        ),
        _label('Video shape'),
        Wrap(
          spacing: 8,
          children: [
            for (var i = 0; i < _shapeNames.length; i++)
              ChoiceChip(
                label: Text(_shapeNames[i]),
                selected: _shape == i,
                onSelected: (_) => setState(() => _shape = i),
              ),
          ],
        ),
        _label('Translation'),
        Wrap(
          spacing: 8,
          children: [
            for (final e in [('none', 'None'), for (final x in rm.translationEditions()) (x.$1, x.$2)])
              ChoiceChip(
                label: Text(e.$2),
                selected: _tr == e.$1,
                onSelected: (_) => setState(() => _tr = e.$1),
              ),
          ],
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Show surah and verse at the bottom'),
          value: _footer,
          onChanged: (v) => setState(() => _footer = v),
        ),
        _label('Background'),
        BackgroundChooser(choice: _bg, onChanged: (c) => setState(() => _bg = c)),
        _label('Template'),
        if (_tpls.isEmpty)
          const Text('Loading templates...')
        else
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (var i = 0; i < _tpls.length; i++)
                ChoiceChip(
                  label: Text(_tpls[i].name),
                  selected: _look == i,
                  onSelected: (_) => setState(() => _look = i),
                ),
            ],
          ),
        const SizedBox(height: 20),
        SizedBox(
          height: 50,
          child: FilledButton(
            onPressed: ready ? _startSync : null,
            child: const Text('Next: sync the verses', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ),
        if (_busy) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
          const SizedBox(height: 6),
          Text(_status),
        ],
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
      ],
    );
  }

  Widget _syncBody() {
    final i = _cur;
    final n = _rows.length;
    final start = _b[i];
    final end = _b[i + 1];
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Container(
          height: 130,
          decoration: BoxDecoration(color: KColors.surface, borderRadius: BorderRadius.circular(14)),
          clipBehavior: Clip.antiAlias,
          child: LayoutBuilder(
            builder: (context, box) {
              final span = _winMs;
              int msAt(double dx) => (_win + dx / box.maxWidth * span).round().clamp(0, _total).toInt();
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => _seek(msAt(d.localPosition.dx), follow: false),
                onHorizontalDragUpdate: (d) => _seek(msAt(d.localPosition.dx), follow: false),
                child: CustomPaint(
                  size: Size(box.maxWidth, 130),
                  painter: _WavePainter(
                    peaks: _peaks,
                    total: _total,
                    winStart: _win,
                    winMs: span,
                    pos: _pos,
                    b: _b,
                    cur: _cur,
                  ),
                ),
              );
            },
          ),
        ),
        if (_total > _peakSpanMs)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('The waveform shows the first 5 minutes of the file.', style: TextStyle(fontSize: 11)),
          ),
        Slider(
          value: _pos.clamp(0, _total).toDouble(),
          min: 0,
          max: math.max(1, _total).toDouble(),
          onChanged: (v) => _seek(v.round()),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(_fmt(_pos), style: const TextStyle(fontWeight: FontWeight.w700)),
            Row(children: [
              TextButton(onPressed: () => _seek(_pos - 100), child: const Text('-0.1s')),
              TextButton(onPressed: () => _seek(_pos + 100), child: const Text('+0.1s')),
            ]),
            Text(_fmt(_total), style: const TextStyle(fontSize: 12)),
          ],
        ),
        Container(
          margin: const EdgeInsets.only(top: 6),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: KColors.surface, borderRadius: BorderRadius.circular(14)),
          child: Column(
            children: [
              Text('Verse ${_rows[i].ayah}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(
                _rows[i].text,
                textAlign: TextAlign.center,
                textDirection: TextDirection.rtl,
                style: const TextStyle(fontSize: 22, height: 1.7, fontFamily: _family),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Start  ${_fmt(start)}', style: const TextStyle(fontSize: 13)),
                  Text('End  ${_fmt(end)}', style: const TextStyle(fontSize: 13)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton.filledTonal(
              onPressed: () => _selectVerse(i - 1),
              icon: const Icon(Icons.skip_previous),
            ),
            const SizedBox(width: 14),
            IconButton.filled(
              iconSize: 36,
              onPressed: () => _playing ? _pause() : _play(),
              icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
            ),
            const SizedBox(width: 14),
            IconButton.filledTonal(
              onPressed: () => _selectVerse(i + 1),
              icon: const Icon(Icons.skip_next),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Center(
          child: TextButton.icon(
            onPressed: () {
              _pos = _b[i];
              _play(stopAt: _b[i + 1]);
            },
            icon: const Icon(Icons.replay),
            label: const Text('Play this verse'),
          ),
        ),
        Row(
          children: [
            Expanded(child: OutlinedButton(onPressed: _setStart, child: const Text('Set Start'))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton(onPressed: _setEnd, child: const Text('Set End'))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton(onPressed: _autoSync, child: const Text('Auto Sync'))),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('${i + 1} / $n', style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        if (_note.isNotEmpty) Text(_note, style: const TextStyle(fontSize: 12.5), textAlign: TextAlign.center),
        const SizedBox(height: 12),
        SizedBox(
          height: 50,
          child: FilledButton(
            onPressed: _busy ? null : _create,
            child: _busy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                : const Text('Create video', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
      ],
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter({
    required this.peaks,
    required this.total,
    required this.winStart,
    required this.winMs,
    required this.pos,
    required this.b,
    required this.cur,
  });

  final List<double> peaks;
  final int total;
  final int winStart;
  final int winMs;
  final int pos;
  final List<int> b;
  final int cur;

  double _x(int ms, double w) => (ms - winStart) / winMs * w;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (winMs <= 0) return;

    // Selected verse region.
    final x1 = _x(b[cur], w).clamp(0.0, w);
    final x2 = _x(b[cur + 1], w).clamp(0.0, w);
    if (x2 > x1) {
      canvas.drawRect(Rect.fromLTRB(x1, 0, x2, h), Paint()..color = const Color(0x337351FF));
    }

    // Waveform bars.
    final cover = math.min(total, _peakSpanMs);
    final bar = Paint()
      ..color = const Color(0xFFB07CFF)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (double x = 1; x < w; x += 4) {
      final t = winStart + x / w * winMs;
      var a = 0.03;
      if (peaks.isNotEmpty && t <= cover && cover > 0) {
        final idx = (t / cover * (peaks.length - 1)).round().clamp(0, peaks.length - 1);
        a = math.max(0.03, peaks[idx].clamp(0.0, 1.0));
      }
      final half = a * h * 0.45;
      canvas.drawLine(Offset(x, h / 2 - half), Offset(x, h / 2 + half), bar);
    }

    // Verse boundaries with numbers.
    for (var i = 0; i < b.length; i++) {
      final x = _x(b[i], w);
      if (x < -1 || x > w + 1) continue;
      final selected = i == cur || i == cur + 1;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, h),
        Paint()
          ..color = selected ? KColors.gold : const Color(0xAAF6C101)
          ..strokeWidth = selected ? 2.5 : 1.5,
      );
      final label = i < b.length - 1 ? '${i + 1}' : 'end';
      final tp = TextPainter(
        text: TextSpan(text: label, style: const TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.w800)),
        textDirection: TextDirection.ltr,
      )..layout();
      final box = Rect.fromLTWH(x - tp.width / 2 - 4, 2, tp.width + 8, tp.height + 2);
      canvas.drawRRect(RRect.fromRectAndRadius(box, const Radius.circular(4)), Paint()..color = KColors.gold);
      tp.paint(canvas, Offset(box.left + 4, box.top + 1));
    }

    // Playhead.
    final px = _x(pos, w);
    if (px >= 0 && px <= w) {
      canvas.drawLine(Offset(px, 0), Offset(px, h), Paint()
        ..color = Colors.white
        ..strokeWidth = 2);
    }
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) =>
      old.pos != pos || old.winStart != winStart || old.cur != cur || old.b != b || old.peaks != peaks;
}

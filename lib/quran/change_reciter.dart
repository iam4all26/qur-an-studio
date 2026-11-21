import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:kainuwa_encoder/kainuwa_encoder.dart';

import '../models.dart';
import '../stage_shape.dart';
import '../theme.dart';
import 'background_choice.dart';
import 'quran_db.dart';
import 'reciter_media.dart';
import 'resource_manager.dart';
import 'templates.dart';
import 'verse_layers.dart';

class _Choice {
  const _Choice(this.id, this.name, this.folder, this.urlTemplate, this.country, this.image);
  final String id;
  final String name;
  final String folder;
  final String urlTemplate;
  final String country;
  final String image;
}

/// Replaces the recitation of a whole video made with New Project by another reciter.
/// Every verse is downloaded, trimmed, and its scenes are re-timed to the new length.
/// Returns true when the video was changed.
Future<bool> changeReciter(BuildContext context, Lesson lesson) async {
  final scenes = lesson.scenes;
  if (scenes.isEmpty || scenes.any((s) => s.qSurah <= 0)) {
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Change reciter'),
        content: const Text(
          'This works only for videos made with New Project after this update, because the app '
          'must know which verse each slide shows. Create the video again to use it.',
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
      ),
    );
    return false;
  }

  final choices = await _loadChoices();
  if (!context.mounted) return false;
  if (choices.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('The reciter list is not downloaded. Open More, Resources.')),
    );
    return false;
  }
  final pick = await showModalBottomSheet<_Choice>(
    context: context,
    isScrollControlled: true,
    backgroundColor: KColors.surface,
    builder: (c) => _Picker(choices: choices),
  );
  await ReciterPreview.stop();
  if (pick == null || !context.mounted) return false;

  // Reciters speak at different speeds, so offer to rebuild the whole timeline.
  final redo = await _askRedo(context);
  if (redo == null || !context.mounted) return false;
  _Settings? settings;
  if (redo) {
    settings = await _settingsFor(context, lesson);
    if (settings == null || !context.mounted) return false;
  }

  final status = ValueNotifier<String>('Starting...');
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (c) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('Changing reciter'),
        content: ValueListenableBuilder<String>(
          valueListenable: status,
          builder: (_, v, __) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [const LinearProgressIndicator(), const SizedBox(height: 12), Text(v)],
          ),
        ),
      ),
    ),
  );

  String? error;
  try {
    if (redo) {
      await _rebuild(lesson, pick, settings!, status);
    } else {
      await _apply(lesson, pick, status);
    }
    lesson.qReciter = pick.id;
  } catch (e) {
    error = '$e';
  }
  if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  status.dispose();
  if (error != null && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(error, 'Could not change the reciter'))));
    return false;
  }
  return true;
}

/// true = redo the timeline, false = keep the slides and only re-time them, null = cancel.
Future<bool?> _askRedo(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Redo the timeline?'),
      content: const Text(
        'Some reciters are faster and some are slower. Redo the timeline entirely to build the video '
        'again as a new project, with the same verses, translation and background, timed to the new '
        'voice. Changes you made by hand to the slides are lost.\n\n'
        'Or keep your slides and only stretch their timing to the new voice.',
        style: TextStyle(fontSize: 14),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
        OutlinedButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep my edits')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Redo timeline')),
      ],
    ),
  );
}

class _Settings {
  _Settings(this.look, this.lang, this.align, this.footer);
  final QTemplate look;
  final String lang; // en_sahih, ha_gumi or '' for none
  final String align;
  final bool footer;
}

bool _isArabic(String t) => RegExp(r'[\u0600-\u06FF]').hasMatch(t);

/// The settings the video was made with. Videos made before they were stored are read from their
/// slides (best guess) and the person can correct the guess.
Future<_Settings?> _settingsFor(BuildContext context, Lesson lesson) async {
  final tpls = await QTemplates.load();
  if (tpls.isEmpty) return null;
  if (lesson.qTemplate.isNotEmpty) {
    final i = tpls.indexWhere((t) => t.id == lesson.qTemplate);
    if (i >= 0) return _Settings(tpls[i], lesson.qLang, lesson.qAlign, lesson.qFooter);
  }
  // Guess from the first verse slide.
  final scene = lesson.scenes.firstWhere((s) => s.qAyah > 0, orElse: () => lesson.scenes.first);
  var look = tpls.first;
  var lang = '';
  var align = 'center';
  var footer = false;
  final label = RegExp(r'\d+:\d+\s*$');
  var arabicSeen = false;
  for (final l in scene.layers) {
    if (l.type != 'text' || l.id.startsWith('overlay_')) continue;
    if (_isArabic(l.text)) {
      if (!arabicSeen) {
        arabicSeen = true;
        final m = tpls.indexWhere((t) => t.arabicColor == l.color);
        if (m >= 0) look = tpls[m];
      }
    } else if (label.hasMatch(l.text.trim())) {
      footer = true;
    } else {
      lang = 'en_sahih';
      align = l.align;
    }
  }
  if (!context.mounted) return null;
  var tIndex = tpls.indexOf(look);
  return showDialog<_Settings>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setD) => AlertDialog(
        title: const Text('Rebuild settings'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This video was made before its settings were saved. Check them; the same verses and '
                'background are used.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                value: tIndex,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Template (text style)'),
                items: [for (var i = 0; i < tpls.length; i++) DropdownMenuItem(value: i, child: Text(tpls[i].name))],
                onChanged: (v) => setD(() => tIndex = v ?? tIndex),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: lang,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Translation'),
                items: [
                  const DropdownMenuItem(value: '', child: Text('None')),
                  for (final e in ResourceManager.instance.translationEditions())
                    DropdownMenuItem(value: e.$1, child: Text('${e.$2} - ${e.$3}')),
                ],
                onChanged: (v) => setD(() => lang = v ?? lang),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Show surah and verse at the bottom'),
                value: footer,
                onChanged: (v) => setD(() => footer = v),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(c, _Settings(tpls[tIndex], lang, align, footer)),
            child: const Text('Rebuild'),
          ),
        ],
      ),
    ),
  );
}

Future<List<_Choice>> _loadChoices() async {
  final rm = ResourceManager.instance;
  await rm.load();
  final e = rm.byId('reciters');
  if (e == null || !rm.isReady('reciters')) return [];
  try {
    final j = jsonDecode(await File(await rm.pathOf(e)).readAsString()) as Map<String, dynamic>;
    return [
      for (final r in (j['reciters'] as List))
        if ((r as Map)['verified'] == true)
          _Choice('${r['id']}', '${r['name']}', '${r['folder']}', '${r['per_ayah_url']}',
              '${r['country'] ?? ''}', '${r['image'] ?? ''}')
    ];
  } catch (_) {
    return [];
  }
}

class _Picker extends StatelessWidget {
  const _Picker({required this.choices});
  final List<_Choice> choices;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Choose the new reciter', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'The recitation of every verse is replaced and the slides are re-timed to the new voice.',
                style: TextStyle(fontSize: 12, color: KColors.accent),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                children: [
                  for (final c in choices)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => Navigator.pop(context, c),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF6F4FB),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: [
                              ReciterAvatar(id: c.id, name: c.name, image: c.image, radius: 22),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(c.name,
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            color: Color(0xFF1B1633), fontWeight: FontWeight.w700, fontSize: 15)),
                                    if (c.country.isNotEmpty)
                                      Text(c.country, style: const TextStyle(color: Color(0xFF6B6785), fontSize: 12)),
                                  ],
                                ),
                              ),
                              ReciterPreviewButton(id: c.id, urlTemplate: c.urlTemplate),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<List<int>> _get(String url) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  try {
    final res = await (await client.getUrl(Uri.parse(url))).close();
    if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode} for $url');
    return await res.fold<List<int>>(<int>[], (a, b) => a..addAll(b));
  } finally {
    client.close(force: true);
  }
}

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

String _code(int surah, int ayah) {
  // ayah 0 is the Basmala scene, recorded as 001001.
  final s = ayah == 0 ? 1 : surah;
  final a = ayah == 0 ? 1 : ayah;
  return '${s.toString().padLeft(3, '0')}${a.toString().padLeft(3, '0')}';
}

Future<void> _apply(Lesson lesson, _Choice rec, ValueNotifier<String> status) async {
  // Group the scenes of each verse (a verse can span several scenes when a video background loops).
  final groups = <List<Scene>>[];
  for (final s in lesson.scenes) {
    if (groups.isNotEmpty && groups.last.first.qSurah == s.qSurah && groups.last.first.qAyah == s.qAyah) {
      groups.last.add(s);
    } else {
      groups.add([s]);
    }
  }

  final prep = await _prepare([for (final g in groups) (g.first.qSurah, g.first.qAyah)], rec, status);
  final paths = prep.paths;
  final sources = prep.sources;
  final trims = prep.trims;

  status.value = 'Re-timing the slides...';
  final clips = <AudioClip>[];
  var pos = 0;
  var videoPos = 0;
  for (var i = 0; i < groups.length; i++) {
    final g = groups[i];
    final newDur = trims[i].$2 - trims[i].$1;
    var oldTotal = 0;
    for (final s in g) {
      oldTotal += s.durationMs;
    }
    var assigned = 0;
    for (var j = 0; j < g.length; j++) {
      final s = g[j];
      final old = math.max(1, s.durationMs);
      final nd = j == g.length - 1
          ? math.max(200, newDur - assigned)
          : math.max(200, (old * newDur / math.max(1, oldTotal)).round());
      assigned += nd;
      final f = nd / old;
      for (final l in s.layers) {
        if (l.startMs > 0) l.startMs = (l.startMs * f).round();
        if (l.endMs > 0) l.endMs = (l.endMs * f).round();
      }
      s.durationMs = nd;
      if (s.videoPath.isNotEmpty && s.videoMs > 0) {
        var off = videoPos % s.videoMs;
        // Keep a part inside the clip; if it would run past the end, start the clip again.
        if (off + nd > s.videoMs) off = 0;
        s.videoStartMs = off;
        videoPos += nd;
      }
    }
    clips.add(AudioClip(
      id: newId(),
      path: paths[i],
      label: 'Verse',
      kind: 'voice',
      startMs: pos,
      trimMs: trims[i].$1,
      durationMs: newDur,
      sourceMs: sources[i],
    ));
    pos += newDur;
  }

  lesson.audioClips.removeWhere((c) => c.kind == 'voice' && c.label == 'Verse');
  lesson.audioClips.addAll(clips);
}

class _Prepared {
  _Prepared(this.paths, this.sources, this.trims);
  final List<String> paths;
  final List<int> sources;
  final List<(int, int)> trims;
}

/// Downloads (once), measures and trims the recording of every (surah, ayah) in order.
/// Nothing in the project is changed here, so a failure leaves the video as it was.
Future<_Prepared> _prepare(List<(int, int)> verses, _Choice rec, ValueNotifier<String> status) async {
  final base = await KainuwaEncoder.filesDir();
  final dir = Directory('$base/quran/audio');
  if (!await dir.exists()) await dir.create(recursive: true);
  final paths = <String>[];
  final sources = <int>[];
  final trims = <(int, int)>[];
  for (var i = 0; i < verses.length; i++) {
    status.value = 'Downloading ${i + 1}/${verses.length}';
    final code = _code(verses[i].$1, verses[i].$2);
    final file = File('${dir.path}/${rec.folder}_$code.mp3');
    if (!await file.exists() || await file.length() == 0) {
      final url = rec.urlTemplate.replaceAll('{SSS}', code.substring(0, 3)).replaceAll('{AAA}', code.substring(3));
      await file.writeAsBytes(await _get(url), flush: true);
    }
    final total = await KainuwaEncoder.audioDuration(file.path);
    if (total <= 0) throw StateError('The recording for $code could not be read.');
    paths.add(file.path);
    sources.add(total);
    trims.add(await _trim(file.path, total));
  }
  return _Prepared(paths, sources, trims);
}

/// Builds the whole timeline again, as New Project would, with the new reciter.
Future<void> _rebuild(Lesson lesson, _Choice rec, _Settings st, ValueNotifier<String> status) async {
  final order = <(int, int)>[];
  for (final s in lesson.scenes) {
    final k = (s.qSurah, s.qAyah);
    if (order.isEmpty || order.last != k) order.add(k);
  }

  final rm = ResourceManager.instance;
  await rm.load();
  await rm.loadFonts();
  final db = await QuranDb.open();
  if (db == null) throw StateError('The Qur\'an data is not downloaded. Open More, Resources.');
  List<String>? tr;
  if (st.lang.isNotEmpty) {
    final e = rm.byId(st.lang);
    if (e == null || !rm.isReady(st.lang)) throw StateError('The translation is not downloaded. Open More, Resources.');
    final j = jsonDecode(await File(await rm.pathOf(e)).readAsString()) as Map<String, dynamic>;
    tr = [for (final v in (j['verses'] as List)) '$v'];
    if (tr.length != 6236) throw StateError('The translation file is incomplete.');
  }
  final surahs = {for (final x in await db.surahs()) x.number: x};
  final offsets = <int, int>{};

  // Keep the backgrounds and the dark overlay of the old timeline.
  final choice = BgChoice.fromScenes(lesson.scenes);
  String? keepAsset;
  if (lesson.scenes.first.bgType == 'asset') keepAsset = lesson.scenes.first.bgValue;
  var overlay = 0.0;
  for (final s in lesson.scenes) {
    for (final l in s.layers) {
      if (l.id.startsWith('overlay_')) overlay = math.max(overlay, l.opacity);
    }
  }

  // Text first (nothing is changed until everything has worked).
  final arabic = <String>[];
  final trans = <String>[];
  final labels = <String>[];
  final basmala = await db.basmala();
  for (final (s, a) in order) {
    if (a == 0) {
      arabic.add(basmala);
      trans.add(tr == null ? '' : tr[0]);
      labels.add('');
    } else {
      final rows = await db.verses(s, a, a);
      if (rows.isEmpty) throw StateError('Verse $s:$a was not found.');
      arabic.add(rows.first.text);
      final off = offsets[s] ?? (offsets[s] = await db.offsetOf(s));
      trans.add(tr == null ? '' : tr[off + a - 1]);
      labels.add('${surahs[s]?.nameEn ?? 'Surah $s'} - $s:$a');
    }
  }

  final prep = await _prepare(order, rec, status);
  status.value = 'Building video...';

  final plan = await BackgroundPlan.create(choice);
  final problem = plan.problem;
  if (problem != null) throw StateError(problem);

  final fontOk = rm.isReady('AmiriQuran-Regular');
  final newScenes = <Scene>[];
  final clips = <AudioClip>[];
  Stage.use(lesson.aspectW, lesson.aspectH);
  try {
    final tall = lesson.aspectH > lesson.aspectW;
    var pos = 0;
    for (var i = 0; i < order.length; i++) {
      final dur = prep.trims[i].$2 - prep.trims[i].$1;
      final pauses = await versePauses(prep.paths[i], prep.sources[i], prep.trims[i].$1, dur);
      final layers = buildVerseLayers(
        pauses: pauses,
        arabic: arabic[i],
        translation: trans[i],
        tall: tall,
        durationMs: dur,
        look: st.look,
        fontFamily: rm.familyIfReady(st.look.arabicFont, fallback: fontOk ? 'Amiri Quran' : ''),
        translationFont: rm.familyIfReady(st.look.translationFont),
        translationAlign: st.align,
        footer: st.footer && labels[i].isNotEmpty ? labels[i] : null,
      );
      final made = plan.scenesFor(
        durationMs: dur,
        layers: layers,
        imageAsset: keepAsset ?? st.look.assetFor(lesson.aspectW, lesson.aspectH),
      );
      for (final sc in made) {
        sc.qSurah = order[i].$1;
        sc.qAyah = order[i].$2;
        if (overlay > 0.001) {
          sc.layers.insert(
            0,
            Layer(
              id: 'overlay_${sc.id}',
              type: 'shape',
              cx: 0.5,
              cy: 0.5,
              w: 1.0,
              h: 1.0,
              color: 0xFF000000,
              opacity: overlay,
            ),
          );
        }
      }
      newScenes.addAll(made);
      clips.add(AudioClip(
        id: newId(),
        path: prep.paths[i],
        label: 'Verse',
        kind: 'voice',
        startMs: pos,
        trimMs: prep.trims[i].$1,
        durationMs: dur,
        sourceMs: prep.sources[i],
      ));
      pos += dur;
    }
  } finally {
    Stage.reset();
  }

  lesson.scenes
    ..clear()
    ..addAll(newScenes);
  lesson.audioClips.removeWhere((c) => c.kind == 'voice' && c.label == 'Verse');
  lesson.audioClips.addAll(clips);
  lesson.qTemplate = st.look.id;
  lesson.qLang = st.lang;
  lesson.qAlign = st.align;
  lesson.qFooter = st.footer;
}

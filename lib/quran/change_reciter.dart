import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:kainuwa_encoder/kainuwa_encoder.dart';

import '../models.dart';
import '../theme.dart';
import 'reciter_media.dart';
import 'resource_manager.dart';

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
    await _apply(lesson, pick, status);
  } catch (e) {
    error = '$e';
  }
  if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  status.dispose();
  if (error != null && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not change the reciter: $error')));
    return false;
  }
  return true;
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

  final base = await KainuwaEncoder.filesDir();
  final dir = Directory('$base/quran/audio');
  if (!await dir.exists()) await dir.create(recursive: true);

  // Download and measure everything first, so a failure changes nothing.
  final paths = <String>[];
  final sources = <int>[];
  final trims = <(int, int)>[];
  for (var i = 0; i < groups.length; i++) {
    status.value = 'Preparing audio ${i + 1} of ${groups.length}...';
    final code = _code(groups[i].first.qSurah, groups[i].first.qAyah);
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

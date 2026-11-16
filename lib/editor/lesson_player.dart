import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:kainuwa_encoder/kainuwa_encoder.dart';

import '../models.dart';

/// Where a moment of the lesson falls: which scene, and how far into it.
class SceneSpot {
  const SceneSpot(this.index, this.localMs);

  final int index;
  final int localMs;
}

SceneSpot sceneAt(Lesson lesson, int ms) {
  if (lesson.scenes.isEmpty) return const SceneSpot(0, 0);
  var start = 0;
  for (var i = 0; i < lesson.scenes.length; i++) {
    final end = start + lesson.scenes[i].durationMs;
    if (ms < end || i == lesson.scenes.length - 1) {
      return SceneSpot(i, math.max(0, math.min(ms - start, lesson.scenes[i].durationMs)));
    }
    start = end;
  }
  return const SceneSpot(0, 0);
}

int sceneStartMs(Lesson lesson, int index) {
  var start = 0;
  for (var i = 0; i < index && i < lesson.scenes.length; i++) {
    start += lesson.scenes[i].durationMs;
  }
  return start;
}

/// Plays a whole lesson inside the editor: one playhead for the entire lesson.
class LessonPlayer extends ChangeNotifier {
  LessonPlayer({required TickerProvider vsync, required this.lesson}) {
    _ticker = vsync.createTicker(_onTick);
  }

  final Lesson lesson;
  late final Ticker _ticker;

  int positionMs = 0;
  bool playing = false;

  /// When true, narration is not played during preview.
  bool muted = false;

  int _baseMs = 0;
  int _audioSceneIndex = -1;
  final Set<String> _clipsOn = <String>{};
  final Map<String, double> _clipVol = <String, double>{};
  int _lastVolMs = -1000;
  bool _disposed = false;

  int get totalMs => lesson.durationMs;

  void _onTick(Duration elapsed) {
    final next = _baseMs + elapsed.inMilliseconds;
    final total = totalMs;
    if (next >= total) {
      positionMs = total;
      _finish();
      return;
    }
    positionMs = next;
    _syncAudio();
    _syncClips();
    notifyListeners();
  }

  void _syncAudio() {
    final spot = sceneAt(lesson, positionMs);
    if (spot.index == _audioSceneIndex) return;
    _audioSceneIndex = spot.index;
    KainuwaEncoder.stopAudio().then((_) {}, onError: (_) {});
    if (muted || spot.localMs > 400) return;
    final scene = lesson.scenes[spot.index];
    if (scene.narrationPath.isNotEmpty) {
      KainuwaEncoder.playAudio(scene.narrationPath, volume: scene.narrationVolume, speed: scene.narrationSpeed)
          .then((_) {}, onError: (_) {});
    }
  }

  /// Volume of a clip at [pos], with its fades.
  double clipGain(AudioClip clip, int pos) {
    var g = clip.volume;
    final local = pos - clip.startMs;
    if (clip.fadeInMs > 0 && local < clip.fadeInMs) {
      g *= math.max(0, local) / clip.fadeInMs;
    }
    final remaining = clip.endMs - pos;
    if (clip.fadeOutMs > 0 && remaining < clip.fadeOutMs) {
      g *= math.max(0, remaining) / clip.fadeOutMs;
    }
    return g.clamp(0.0, 1.0).toDouble();
  }

  /// Starts and stops the extra clips of the Audio track around the playhead.
  void _syncClips() {
    if (muted) {
      _stopClips();
      return;
    }
    final pos = positionMs;
    final ids = <String>{};
    for (final clip in lesson.audioClips) {
      ids.add(clip.id);
      final inside = clip.path.isNotEmpty && pos >= clip.startMs && pos < clip.endMs;
      final on = _clipsOn.contains(clip.id);
      if (inside && !on) {
        _clipsOn.add(clip.id);
        final g = clipGain(clip, pos);
        _clipVol[clip.id] = g;
        KainuwaEncoder.playClip(
          clip.id,
          clip.path,
          seekMs: clip.trimMs + ((pos - clip.startMs) * clip.speed).round(),
          volume: g,
          speed: clip.speed,
        ).then((_) {}, onError: (_) {});
      } else if (!inside && on) {
        _clipsOn.remove(clip.id);
        KainuwaEncoder.stopClip(clip.id).then((_) {}, onError: (_) {});
      } else if (inside && pos - _lastVolMs >= 100) {
        final g = clipGain(clip, pos);
        if ((g - (_clipVol[clip.id] ?? g)).abs() > 0.01) {
          _clipVol[clip.id] = g;
          KainuwaEncoder.setClipVolume(clip.id, g).then((_) {}, onError: (_) {});
        }
      }
    }
    // Background music of the whole video, with its volume and speed.
    ids.add('music');
    final hasMusic = lesson.musicPath.isNotEmpty;
    final musicOn = _clipsOn.contains('music');
    if (hasMusic && !musicOn) {
      _clipsOn.add('music');
      _clipVol['music'] = lesson.musicVolume;
      KainuwaEncoder.playClip(
        'music',
        lesson.musicPath,
        seekMs: (pos * lesson.musicSpeed).round(),
        volume: lesson.musicVolume.clamp(0.0, 1.0).toDouble(),
        speed: lesson.musicSpeed,
      ).then((_) {}, onError: (_) {});
    } else if (!hasMusic && musicOn) {
      _clipsOn.remove('music');
      KainuwaEncoder.stopClip('music').then((_) {}, onError: (_) {});
    } else if (hasMusic && pos - _lastVolMs >= 100) {
      final g = lesson.musicVolume.clamp(0.0, 1.0).toDouble();
      if ((g - (_clipVol['music'] ?? g)).abs() > 0.01) {
        _clipVol['music'] = g;
        KainuwaEncoder.setClipVolume('music', g).then((_) {}, onError: (_) {});
      }
    }
    var sceneStart = 0;
    for (final scene in lesson.scenes) {
      final sceneEnd = sceneStart + scene.durationMs;
      if (scene.hasVideo) {
        final id = 'video:${scene.id}';
        ids.add(id);
        final audible = !scene.videoMuted && scene.videoVolume > 0;
        final inside = audible && pos >= sceneStart && pos < sceneEnd;
        final on = _clipsOn.contains(id);
        if (inside && !on) {
          _clipsOn.add(id);
          KainuwaEncoder.playClip(
            id,
            scene.videoPath,
            seekMs: scene.videoStartMs + (pos - sceneStart),
            volume: scene.videoVolume.clamp(0.0, 1.0).toDouble(),
          ).then((_) {}, onError: (_) {});
        } else if (!inside && on) {
          _clipsOn.remove(id);
          KainuwaEncoder.stopClip(id).then((_) {}, onError: (_) {});
        }
      }
      sceneStart = sceneEnd;
    }
    for (final id in _clipsOn.toList()) {
      if (!ids.contains(id)) {
        _clipsOn.remove(id);
        KainuwaEncoder.stopClip(id).then((_) {}, onError: (_) {});
      }
    }
    if (pos - _lastVolMs >= 100 || pos < _lastVolMs) _lastVolMs = pos;
  }

  void _stopClips() {
    if (_clipsOn.isEmpty) return;
    _clipsOn.clear();
    _clipVol.clear();
    KainuwaEncoder.stopClips().then((_) {}, onError: (_) {});
  }

  void _finish() {
    _ticker.stop();
    playing = false;
    _audioSceneIndex = -1;
    _stopClips();
    KainuwaEncoder.stopAudio().then((_) {}, onError: (_) {});
    notifyListeners();
  }

  void play() {
    if (playing || lesson.scenes.isEmpty) return;
    if (positionMs >= totalMs) positionMs = 0;
    _baseMs = positionMs;
    _audioSceneIndex = -1;
    playing = true;
    _ticker.stop();
    _ticker.start();
    _syncAudio();
    _syncClips();
    notifyListeners();
  }

  void pause() {
    if (!playing) return;
    _ticker.stop();
    playing = false;
    _audioSceneIndex = -1;
    KainuwaEncoder.stopAudio().then((_) {}, onError: (_) {});
    _stopClips();
    notifyListeners();
  }

  void toggle() => playing ? pause() : play();

  /// Moves the playhead. Playback carries on from the new place when it was running.
  void seek(int ms) {
    positionMs = math.max(0, math.min(ms, totalMs));
    if (playing) {
      _ticker.stop();
      _baseMs = positionMs;
      _audioSceneIndex = -1;
      _stopClips();
      _ticker.start();
      _syncAudio();
      _syncClips();
    }
    notifyListeners();
  }

  /// Keeps the playhead inside the lesson after scenes were changed.
  void clampToLesson() {
    if (positionMs > totalMs) {
      positionMs = totalMs;
      if (playing) _finish();
    }
  }

  void previous() {
    final spot = sceneAt(lesson, positionMs);
    if (spot.localMs > 1500 || spot.index == 0) {
      seek(sceneStartMs(lesson, spot.index));
    } else {
      seek(sceneStartMs(lesson, spot.index - 1));
    }
  }

  void next() {
    final spot = sceneAt(lesson, positionMs);
    if (spot.index >= lesson.scenes.length - 1) {
      seek(totalMs);
    } else {
      seek(sceneStartMs(lesson, spot.index + 1));
    }
  }

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker.dispose();
    KainuwaEncoder.stopClips().then((_) {}, onError: (_) {});
    KainuwaEncoder.stopAudio().then((_) {}, onError: (_) {});
    super.dispose();
  }
}

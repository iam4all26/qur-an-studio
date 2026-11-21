import '../app_control.dart';
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' hide Layer;
import 'package:flutter/services.dart';
import 'package:kainuwa_encoder/kainuwa_encoder.dart';

import '../animation_math.dart';
import '../export_history.dart';
import '../app_state.dart';
import '../editor/track_visibility.dart';
import '../models.dart';
import '../transition_math.dart';
import '../watermark.dart';
import '../scene_canvas.dart';
import '../hands.dart';
import '../stage_shape.dart';
import '../text_reveal.dart';
import '../theme.dart';
import '../widgets.dart';
import 'export_success_view.dart';

const double _kPad = 12;

class _Cancelled implements Exception {}

/// Exports a whole lesson to one MP4 video.
///
/// Every slide is drawn here with Flutter (so it looks exactly like the editor).
/// Items without animation are baked into the slide picture. From the first
/// animated item upward, every item becomes its own transparent picture that the
/// video encoder animates with the same formulas as the editor preview.
class ExportScreen extends StatefulWidget {
  const ExportScreen({super.key, required this.courseId, required this.lessonId});

  final String courseId;
  final String lessonId;

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  final GlobalKey _stageKey = GlobalKey();
  Widget? _stageChild;
  double _stageW = 1280;
  double _stageH = 720;
  int _stageSerial = 0;

  // Choices made on this screen for this export.
  int _quality = 720; // output height: 480, 720, 1080 or 1440
  int _fps = 30;
  double _mbps = 8;
  final TextEditingController _nameCtl = TextEditingController();
  bool _nameReady = false;
  bool _defaultsReady = false;

  static const Map<int, (int, String, String, double)> _qualities = {
    480: (854, 'SD', 'Smaller file', 3),
    720: (1280, 'HD', 'Recommended', 8),
    1080: (1920, 'Full HD', 'Best for sharing', 12),
    1440: (2560, '2K', 'Sharpest, slow', 20),
  };

  Lesson? _lessonNow() => AppScope.read(context).lessonById(widget.courseId, widget.lessonId);

  // Working size of this video (short side 720) and the size of the exported file.
  double get _sw => _lessonNow()?.stageSize.$1 ?? 1280;
  double get _sh => _lessonNow()?.stageSize.$2 ?? 720;

  (int, int) _outFor(int shortSide) {
    final l = _lessonNow();
    return outputSizeFor(l?.aspectW ?? 16, l?.aspectH ?? 9, shortSide);
  }

  bool _busy = false;
  bool _cancelled = false;
  bool _failed = false;
  int _phase = 0; // 0 drawing, 1 narration, 2 video
  double _progress = 0;
  String _status = '';
  DateTime? _startedAt;
  Timer? _ticker;
  Widget? _thumbCache;
  String? _unsavedVideo;
  bool _canPlay = false;
  bool _runPage = false;
  String _unsavedName = '';
  // The finished export shown on the success page.
  ExportEntry? _result;
  List<ExportEntry> _history = [];
  String _pThumb = '';
  int _pW = 0;
  int _pH = 0;
  int _pDur = 0;
  int _pSize = 0;

  @override
  void dispose() {
    _ticker?.cancel();
    _nameCtl.dispose();
    if (_busy) {
      _cancelled = true;
      KainuwaEncoder.cancelExport();
    }
    super.dispose();
  }

  void _set(String message, {bool failed = false}) {
    if (!mounted) return;
    setState(() {
      _status = message;
      _failed = failed;
    });
  }

  void _setProgress(int phase, double fraction) {
    if (!mounted) return;
    const starts = [0.0, 0.25, 0.35];
    const spans = [0.25, 0.10, 0.65];
    final value = starts[phase] + spans[phase] * fraction.clamp(0.0, 1.0).toDouble();
    setState(() {
      _phase = phase;
      // The bar only ever moves forward.
      if (value > _progress) _progress = value;
    });
  }

  void _guard() {
    if (_cancelled) throw _Cancelled();
  }

  // ---- Drawing ----

  Future<ui.Image> _capture(Widget child, double w, double h, double pixelRatio) async {
    setState(() {
      _stageW = w;
      _stageH = h;
      _stageSerial++;
      _stageChild = child;
    });
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;
    final object = _stageKey.currentContext?.findRenderObject();
    if (object is! RenderRepaintBoundary) {
      throw StateError('The drawing area was not ready.');
    }
    return object.toImage(pixelRatio: pixelRatio);
  }

  Future<void> _savePng(ui.Image image, String path) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (data == null) throw StateError('Could not store a slide picture.');
    await File(path).writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
  }

  Future<void> _precache(Scene scene) async {
    final providers = <ImageProvider>[];
    if (scene.bgType == 'asset') {
      providers.add(AssetImage(scene.bgValue));
    } else if (scene.bgType == 'file') {
      providers.add(FileImage(File(scene.bgValue)));
    }
    for (final layer in scene.layers) {
      if (layer.type == 'asset') providers.add(AssetImage(layer.path));
      final hand = handById(layer.hand);
      if (hand != null) providers.add(AssetImage(hand.asset));
      if (layer.type == 'image') providers.add(FileImage(File(layer.path)));
    }
    for (final provider in providers) {
      if (!mounted) return;
      try {
        await precacheImage(provider, context);
      } catch (_) {
        // A missing picture is drawn as a grey box, like in the editor.
      }
    }
  }

  /// The box around a rotated item, with some room for shadows.
  (double, double, Widget) _layerPicture(Layer l, {int? revealMs, double? clip}) {
    final lw = l.w * _sw;
    final lh = l.h * _sh;
    final c = math.cos(l.rotation).abs();
    final s = math.sin(l.rotation).abs();
    // Room around the item for its shadow.
    var pad = _kPad;
    if (l.shadowOn) {
      final unit = math.min(lw, lh);
      final reach = (math.max(l.shadowX.abs(), l.shadowY.abs()) + l.shadowBlur * 3) * unit;
      pad = math.max(_kPad, reach + 4);
    }
    final bw = math.max(2.0, lw * c + lh * s + pad * 2);
    final bh = math.max(2.0, lw * s + lh * c + pad * 2);
    final widget = SizedBox(
      width: bw,
      height: bh,
      child: Center(
        child: Transform.rotate(
          angle: l.rotation,
          child: SizedBox(width: lw, height: lh, child: LayerContent(layer: l, revealMs: revealMs, clipFraction: clip)),
        ),
      ),
    );
    return (bw, bh, widget);
  }

  // ---- Export ----

  Future<void> _start() async {
    if (_busy) return;
    if (AppControl.instance.featureOff('export')) {
      _set(AppControl.instance.featureMessage, failed: true);
      return;
    }
    final state = AppScope.read(context);
    final lesson = state.lessonById(widget.courseId, widget.lessonId);
    if (lesson == null || lesson.scenes.isEmpty) {
      _set('This video has no slides to export.', failed: true);
      return;
    }
    final hidden = Set<String>.of(lesson.hiddenTracks);
    final audioOff = hidden.contains('audio');
    final scenes = lesson.scenes.map((s) {
      final v = viewScene(s, hidden);
      return identical(v, s) ? s.duplicate() : v;
    }).toList();
    final outSize = _outFor(_quality);
    final outW = outSize.$1;
    final outH = outSize.$2;
    final stageW = _sw;
    final stageH = _sh;
    final fps = _fps;
    final ratio = outW / stageW;
    final title = lesson.title;
    final musicPath = audioOff ? '' : lesson.musicPath;
    final clipMaps = <Map<String, Object?>>[];
    if (!audioOff) {
      for (final clip in lesson.audioClips) {
        if (clip.path.isEmpty || !await File(clip.path).exists()) continue;
        clipMaps.add({
          'path': clip.path,
          'startMs': clip.startMs,
          'trimMs': clip.trimMs,
          'durMs': clip.durationMs,
          'volume': clip.volume,
          'speed': clip.speed,
          'fadeInMs': clip.fadeInMs,
          'fadeOutMs': clip.fadeOutMs,
        });
      }
    }
    final musicVolume = lesson.musicVolume;
    final musicFade = lesson.musicFade;

    setState(() {
      _busy = true;
      _cancelled = false;
      _failed = false;
      _unsavedVideo = null;
      _result = null;
      _canPlay = false;
      _phase = 0;
      _progress = 0;
      _startedAt = DateTime.now();
      _status = 'Drawing slides. Keep this screen open.';
    });

    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });

    final subs = <StreamSubscription<dynamic>>[
      KainuwaEncoder.stage.listen((s) {
        if (s == 'audio') {
          _setProgress(1, 0);
          _set('Preparing the narration. Keep this screen open.');
        } else if (s == 'video') {
          _setProgress(2, 0);
          _set('Creating the video. This can take a while. Keep this screen open.');
        }
      }),
      KainuwaEncoder.audioProgress.listen((p) => _setProgress(1, p / 100)),
      KainuwaEncoder.progress.listen((p) {
        if (_phase == 2) _setProgress(2, p / 100);
      }),
    ];

    Directory? root;
    try {
      final base = await KainuwaEncoder.filesDir();
      root = Directory('$base/export_tmp');
      if (await root.exists()) await root.delete(recursive: true);
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final work = Directory('${root.path}/job_$stamp');
      await work.create(recursive: true);

      final specs = <Map<String, Object?>>[];
      final transitions = <Map<String, Object?>>[];
      var missingNarration = 0;
      var offsetMs = 0;
      for (var i = 0; i < scenes.length; i++) {
        _guard();
        _setProgress(0, i / scenes.length);
        final scene = scenes[i];
        final videoOk = scene.hasVideo && await File(scene.videoPath).exists();
        if (!videoOk && scene.hasVideo) {
          scene.videoPath = '';
        }
        if (scene.hasVideo && scene.videoMs > 0) {
          scene.durationMs = math.max(500, math.min(scene.durationMs, scene.videoMs - scene.videoStartMs));
        }
        await _precache(scene);

        final firstAnimated = scene.layers.indexWhere(layerNeedsOverlay);
        final staticLayers =
            firstAnimated < 0 ? scene.layers : scene.layers.sublist(0, firstAnimated);
        final baseScene = Scene(
          id: 'export_base',
          durationMs: scene.durationMs,
          bgType: scene.hasVideo ? 'color' : scene.bgType,
          bgValue: scene.hasVideo ? '0' : scene.bgValue,
          layers: List<Layer>.of(staticLayers),
        );
        final wm = AppScope.read(context).settings.wm;
        final phoneOn = scene.hasVideo && scene.phoneFrame;
        final geo = PhoneGeometry(stageW, stageH, scene.phoneScale);
        final baseImage = await _capture(
          SizedBox(
            width: stageW,
            height: stageH,
            child: phoneOn
                ? Stack(children: [
                    // Background and phone body with a see-through screen, so the video shows in it.
                    Positioned.fill(
                      child: ClipPath(
                        clipper: PhoneHoleClipper(geo),
                        child: Stack(children: [
                          Positioned.fill(child: SceneBackground(scene: scene, noVideo: true)),
                          PhoneBody(geo: geo, light: scene.phoneLight),
                        ]),
                      ),
                    ),
                    PhoneNotch(geo: geo),
                    Positioned.fill(child: SceneCanvas(scene: baseScene)),
                    watermarkOverlay(wm, stageW, stageH),
                  ])
                : Stack(children: [
                    Positioned.fill(child: SceneCanvas(scene: baseScene)),
                    watermarkOverlay(wm, stageW, stageH),
                  ]),
          ),
          stageW,
          stageH,
          ratio,
        );
        final basePath = '${work.path}/scene_$i.png';
        await _savePng(baseImage, basePath);

        final overlays = <Map<String, Object?>>[];
        if (scene.hasVideo) {
          // The slide's own items sit on top of the video as a transparent picture.
          overlays.add({
            'path': basePath,
            'cx': 0.5,
            'cy': 0.5,
            'anim': 'none',
            'startMs': 0,
            'durMs': 0,
            'showMs': 0,
            'hideMs': null,
            'outAnim': 'none',
            'outStartMs': 0,
            'outDurMs': 0,
          });
          if (!scene.videoMuted && scene.videoVolume > 0) {
            clipMaps.add({
              'path': scene.videoPath,
              'startMs': offsetMs,
              'trimMs': scene.videoStartMs,
              'durMs': scene.durationMs,
              'volume': scene.videoVolume,
              'fadeInMs': 0,
              'fadeOutMs': 0,
            });
          }
        }
        final handOverlays = <Map<String, Object?>>[];
        if (firstAnimated >= 0) {
          for (var k = firstAnimated; k < scene.layers.length; k++) {
            _guard();
            final layer = scene.layers[k];
            final picture = _layerPicture(layer);
            final handSpec = handById(layer.hand);
            final handAnimated = handSpec != null;
            final textAnimated = !handAnimated && layer.type == 'text' && layer.textAnim != 'none';
            final firstPicture = textAnimated
                ? _layerPicture(layer, revealMs: -1)
                : (handAnimated ? _layerPicture(layer, clip: 0.0) : picture);
            final image = await _capture(firstPicture.$3, firstPicture.$1, firstPicture.$2, ratio);
            final path = '${work.path}/scene_${i}_layer_$k.png';
            await _savePng(image, path);
            // Text animations are a series of pictures, each one showing a bit more text.
            List<Map<String, Object?>>? frames;
            if (textAnimated) {
              final total = textRevealTotalMs(layer);
              final step = math.max(50, (total / 180).ceil());
              final t0 = layer.startMs + layer.animStartMs;
              frames = [
                {'path': path, 'atMs': layer.startMs},
              ];
              var f = 0;
              for (var r = step; ; r += step) {
                _guard();
                final reveal = math.min(r, total);
                final pic = _layerPicture(layer, revealMs: reveal);
                final img = await _capture(pic.$3, pic.$1, pic.$2, ratio);
                final fp = '${work.path}/scene_${i}_layer_${k}_f${f++}.png';
                await _savePng(img, fp);
                frames.add({'path': fp, 'atMs': t0 + reveal});
                if (reveal >= total) break;
              }
            }
            if (handAnimated) {
              // The item is drawn from left to right: a series of pictures, each one
              // showing a bit more. The hand is its own picture that moves along.
              final t0 = layer.startMs + layer.animStartMs;
              final drawMs = math.max(1, layer.handMs);
              final step = math.max(60, (drawMs / 120).ceil());
              frames = [
                {'path': path, 'atMs': layer.startMs},
              ];
              var f = 0;
              for (var u = step; ; u += step) {
                _guard();
                final shown = math.min(u, drawMs);
                final pic = _layerPicture(layer, clip: shown >= drawMs ? null : shown / drawMs);
                final img = await _capture(pic.$3, pic.$1, pic.$2, ratio);
                final fp = '${work.path}/scene_${i}_layer_${k}_f${f++}.png';
                await _savePng(img, fp);
                frames.add({'path': fp, 'atMs': t0 + kHandEnterMs + shown});
                if (shown >= drawMs) break;
              }
              final handW = stageW * kHandWidthFrac;
              final handH = handW / handSpec.aspect;
              await precacheImage(AssetImage(handSpec.asset), context);
              final handImage = await _capture(
                SizedBox(
                  width: handW,
                  height: handH,
                  child: Image.asset(handSpec.asset, fit: BoxFit.fill),
                ),
                handW,
                handH,
                ratio,
              );
              final handPath = '${work.path}/scene_${i}_hand_$k.png';
              await _savePng(handImage, handPath);
              final keys = <Map<String, Object?>>[];
              final total = handTotalMs(layer);
              for (var t = 0; ; t += 40) {
                final tt = math.min(t, total);
                final st = handStateAt(layer, tt);
                keys.add({
                  't': t0 + tt,
                  'x': st.tipX + (0.5 - handSpec.tipX) * kHandWidthFrac,
                  'y': st.tipY + (0.5 - handSpec.tipY) * (handH / stageH),
                });
                if (tt >= total) break;
              }
              handOverlays.add({
                'path': handPath,
                'cx': 0.5,
                'cy': 0.5,
                'anim': 'none',
                'startMs': 0,
                'durMs': 0,
                'showMs': t0,
                'hideMs': t0 + total + 60,
                'outAnim': 'none',
                'outStartMs': 0,
                'outDurMs': 0,
                'keys': keys,
              });
            }
            final end = layerEndMs(layer, scene.durationMs);
            overlays.add({
              'frames': frames,
              'path': path,
              'cx': layer.cx,
              'cy': layer.cy,
              'anim': kindWithDir(layer.animIn, layer.animInDir),
              'startMs': layer.startMs + layer.animStartMs,
              'durMs': layer.animDurationMs,
              'showMs': layer.startMs,
              'hideMs': end,
              'outAnim': kindWithDir(layer.animOut, layer.animOutDir),
              'outStartMs': end - layer.animOutDurationMs,
              'outDurMs': layer.animOutDurationMs,
              'loop': layer.animLoop,
              'loopMs': loopPeriodMs(layer),
            });
          }
          overlays.addAll(handOverlays);
        }

        String? narration;
        if (!audioOff && scene.narrationPath.isNotEmpty) {
          if (await File(scene.narrationPath).exists()) {
            narration = scene.narrationPath;
          } else {
            missingNarration++;
          }
        }
        specs.add({
          'image': basePath,
          'durationMs': scene.durationMs,
          'narration': narration,
          'volume': scene.narrationVolume,
          'speed': scene.narrationSpeed,
          'clean': scene.narrationClean,
          'overlays': overlays,
          'video': scene.hasVideo ? scene.videoPath : null,
          'videoStartMs': scene.videoStartMs,
          'videoFill': scene.hasVideo && scene.videoFill && !scene.phoneFrame,
          'videoScale': scene.hasVideo && scene.phoneFrame
              ? PhoneGeometry(stageW, stageH, scene.phoneScale).screenH / stageH
              : 1.0,
        });
        offsetMs += scene.durationMs;
        final half = transitionHalfMs(lesson, i);
        if (half > 0) {
          transitions.add({
            'atMs': offsetMs,
            'kind': scene.transKind,
            'dir': scene.transDir,
            'halfMs': half,
            'bg': scene.transBg & 0xFFFFFFFF,
          });
        }
      }

      // A small picture of the first slide for the success page and the export list.
      var thumbPath = '';
      try {
        final s0 = scenes.first;
        final histDir0 = await ExportHistory.dir();
        var tBgType = s0.bgType;
        var tBgValue = s0.bgValue;
        if (s0.hasVideo) {
          // A video slide: use a real picture from the clip as the background.
          tBgType = 'color';
          tBgValue = '0';
          try {
            final bytes = await KainuwaEncoder.videoFrameBytes(s0.videoPath, s0.videoStartMs + 200);
            if (bytes != null && bytes.isNotEmpty) {
              final framePath = '${histDir0.path}/frame_$stamp.jpg';
              await File(framePath).writeAsBytes(bytes, flush: true);
              tBgType = 'file';
              tBgValue = framePath;
            }
          } catch (_) {}
        }
        final thumbScene = Scene(
          id: 'export_thumb',
          durationMs: s0.durationMs,
          bgType: tBgType,
          bgValue: tBgValue,
          layers: List<Layer>.of(s0.layers),
        );
        await _precache(thumbScene);
        final thumbImage = await _capture(
          SizedBox(width: stageW, height: stageH, child: SceneCanvas(scene: thumbScene)),
          stageW,
          stageH,
          0.3,
        );
        final histDir = await ExportHistory.dir();
        thumbPath = '${histDir.path}/thumb_$stamp.png';
        await _savePng(thumbImage, thumbPath);
        if (tBgType == 'file' && s0.hasVideo) {
          try {
            await File(tBgValue).delete();
          } catch (_) {}
        }
      } catch (_) {
        thumbPath = '';
      }

      if (mounted) setState(() => _stageChild = null);
      _guard();

      String? music;
      if (musicPath.isNotEmpty && await File(musicPath).exists()) music = musicPath;

      _setProgress(1, 0);
      final output = '${root.path}/video_$stamp.mp4';
      await KainuwaEncoder.exportLesson(
        scenes: specs,
        workDir: work.path,
        outputPath: output,
        musicPath: music,
        musicVolume: musicVolume,
        musicSpeed: lesson.musicSpeed,
        musicFadeMs: musicFade ? 2000 : 0,
        width: outW,
        height: outH,
        fps: fps,
        bitrate: (_mbps * 1000000).round(),
        clips: clipMaps,
        transitions: transitions,
      );
      try {
        await work.delete(recursive: true);
      } catch (_) {}
      _setProgress(2, 1);
      _pThumb = thumbPath;
      _pW = outW;
      _pH = outH;
      _pDur = lesson.durationMs;
      await _save(output, title, missingNarration);
    } on _Cancelled {
      _set('Export cancelled.');
    } on PlatformException catch (e) {
      if (e.code == 'cancelled') {
        _set('Export cancelled.');
      } else {
        _set('Export stopped: ${e.message}', failed: true);
      }
    } catch (e) {
      _set('Export stopped: $e', failed: true);
    } finally {
      _ticker?.cancel();
      _ticker = null;
      for (final s in subs) {
        await s.cancel();
      }
      if (mounted) {
        setState(() {
          _busy = false;
          _stageChild = null;
        });
      }
    }
  }

  /// "_v1-7" from the verse numbers on the slides ("" for a project without verse slides).
  String _verseRange(Lesson lesson) {
    var lo = 0;
    var hi = 0;
    for (final sc in lesson.scenes) {
      if (sc.qSurah <= 0 || sc.qAyah <= 0) continue;
      if (lo == 0 || sc.qAyah < lo) lo = sc.qAyah;
      if (sc.qAyah > hi) hi = sc.qAyah;
    }
    return lo == 0 ? '' : '_v$lo-$hi';
  }

  String _safeName(String title) {
    final cleaned = title.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
    return cleaned.isEmpty ? 'Video' : cleaned;
  }

  Future<void> _save(String output, String title, int missingNarration) async {
    final typed = _safeName(_nameCtl.text.trim().isEmpty ? title : _nameCtl.text.trim());
    final name = '$typed.mp4';
    final note = missingNarration > 0
        ? ' $missingNarration slide(s) had a narration file that could not be found and are silent.'
        : '';
    try {
      try {
        _pSize = await File(output).length();
      } catch (_) {}
      final saved = await KainuwaEncoder.saveToMovies(path: output, name: name);
      if (mounted) setState(() { _unsavedVideo = null; _canPlay = true; });
      _set('Done. The video was saved to $saved.$note');
      await _complete(saved);
      try {
        await File(output).delete();
      } catch (_) {}
    } on PlatformException catch (e) {
      if (mounted) {
        setState(() {
          _unsavedVideo = output;
          _unsavedName = name;
        });
      }
      _set('The video was made but not saved yet (${e.message}). Tap Save video to try again.$note',
          failed: true);
    }
  }

  /// Remembers the finished video and opens the success page.
  Future<void> _complete(String saved) async {
    try {
      var uri = '';
      for (var i = 0; i < 6; i++) {
        try {
          uri = await KainuwaEncoder.lastVideoUri() ?? '';
        } catch (_) {}
        if (uri.isNotEmpty) break;
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
      var name = saved.split('/').last;
      if (name.toLowerCase().endsWith('.mp4')) name = name.substring(0, name.length - 4);
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final entry = ExportEntry(
        id: 'exp_$stamp',
        lessonId: widget.lessonId,
        name: name,
        uri: uri,
        width: _pW,
        height: _pH,
        sizeBytes: _pSize,
        durationMs: _pDur,
        thumbPath: _pThumb,
        atMs: stamp,
      );
      await ExportHistory.add(entry);
      final all = await ExportHistory.load(widget.lessonId);
      if (!mounted) return;
      setState(() {
        _result = entry;
        _history = all;
      });
    } catch (_) {
      // The video is saved anyway; the old page still shows the result.
    }
  }

  Future<void> _viewEntry(ExportEntry e, String mode) async {
    try {
      await KainuwaEncoder.viewVideo(uri: e.uri.isEmpty ? null : e.uri, mode: mode);
    } on PlatformException catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(err.message ?? 'The video could not be opened. It may have been moved or deleted.'),
      ));
    }
  }

  Future<void> _removeEntry(ExportEntry e) async {
    await ExportHistory.remove(e.id);
    final all = await ExportHistory.load(widget.lessonId);
    if (!mounted) return;
    setState(() => _history = all);
  }

  void _exportAgain() {
    setState(() {
      _result = null;
      _canPlay = false;
      _status = '';
      _failed = false;
      _runPage = false;
    });
  }

  void _moreSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: KColors.editorCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.movie_creation_outlined, color: KColors.gold),
              title: const Text('Export again'),
              onTap: () {
                Navigator.pop(ctx);
                _exportAgain();
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined, color: KColors.accent),
              title: const Text('Back to the editor'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).maybePop();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _playVideo() async {
    try {
      await KainuwaEncoder.playLastVideo();
    } on PlatformException catch (e) {
      _set(e.message ?? 'The video could not be opened.', failed: true);
    }
  }

  Future<void> _retrySave() async {
    final path = _unsavedVideo;
    if (path == null || _busy) return;
    setState(() => _busy = true);
    try {
      final saved = await KainuwaEncoder.saveToMovies(path: path, name: _unsavedName);
      if (mounted) setState(() { _unsavedVideo = null; _canPlay = true; });
      _set('Done. The video was saved to $saved.');
      await _complete(saved);
      try {
        await File(path).delete();
      } catch (_) {}
    } on PlatformException catch (e) {
      _set('Could not save yet (${e.message}). Tap Save video to try again.', failed: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    _cancelled = true;
    _set('Cancelling...');
    try {
      await KainuwaEncoder.cancelExport();
    } catch (_) {}
  }

  // ---- Screen ----

  /// Small pictures of the slides, so the person sees what is being exported.
  Widget _thumbnails(List<Scene> scenes) {
    const h = 54.0;
    final w = (h * (_sw / _sh)).clamp(30.0, 96.0).toDouble();
    final shown = scenes.take(12).toList();
    final more = scenes.length - shown.length;
    final media = MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling);
    return SizedBox(
      height: h,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: shown.length + (more > 0 ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          if (i >= shown.length) {
            return Container(
              width: w,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: KColors.lavender,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('+$more more', style: const TextStyle(fontSize: 12)),
            );
          }
          final scene = shown[i];
          return ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: w,
              height: h,
              child: IgnorePointer(
                child: MediaQuery(
                  data: media,
                  child: FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: _sw,
                      height: _sh,
                      child: SceneCanvas(scene: scene),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  String _elapsed() {
    final t = _startedAt;
    if (t == null) return '';
    final sec = DateTime.now().difference(t).inSeconds;
    final m = (sec ~/ 60).toString().padLeft(2, '0');
    final r = (sec % 60).toString().padLeft(2, '0');
    return '$m:$r';
  }

  /// The page shown while exporting: ring with the percentage, the steps and Cancel.
  Widget _exportingView() {
    final pct = (_progress * 100).clamp(0, 100).round();
    final videoPct = (((_progress - 0.35) / 0.65) * 100).clamp(0, 100).round();
    final finalizing = _phase == 2 && _progress >= 0.995;
    // 0 waiting, 1 working, 2 done
    final steps = <(String, int)>[
      ('Preparing project', _phase > 0 ? 2 : 1),
      ('Mixing audio', _phase > 1 ? 2 : (_phase == 1 ? 1 : 0)),
      (_phase == 2 && !finalizing ? 'Processing video ($videoPct%)' : 'Processing video',
          finalizing ? 2 : (_phase == 2 ? 1 : 0)),
      ('Finalizing', finalizing ? 1 : 0),
    ];

    Widget stepIcon(int st) {
      if (st == 2) {
        return Container(
          width: 26,
          height: 26,
          decoration: const BoxDecoration(color: KColors.purple, shape: BoxShape.circle),
          child: const Icon(Icons.check, size: 17, color: Colors.white),
        );
      }
      if (st == 1) {
        return const SizedBox(
          width: 26,
          height: 26,
          child: Padding(
            padding: EdgeInsets.all(2),
            child: CircularProgressIndicator(strokeWidth: 3, color: KColors.gold),
          ),
        );
      }
      return Container(
        width: 26,
        height: 26,
        decoration: const BoxDecoration(color: Color(0x33FFFFFF), shape: BoxShape.circle),
        child: const Icon(Icons.check, size: 17, color: Color(0x55FFFFFF)),
      );
    }

    final list = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0x14FFFFFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x1FFFFFFF)),
      ),
      child: Column(
        children: [
          for (var i = 0; i < steps.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: Color(0x1FFFFFFF)),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 11),
              child: Row(
                children: [
                  stepIcon(steps[i].$2),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      steps[i].$1,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: steps[i].$2 == 1 ? FontWeight.w700 : FontWeight.w500,
                        color: steps[i].$2 == 0 ? Colors.white54 : Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );

    final cancel = SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 50),
          foregroundColor: Colors.white,
          side: const BorderSide(color: KColors.gold, width: 1.4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        onPressed: _cancel,
        child: const Text('Cancel', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      ),
    );

    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth > box.maxHeight * 1.15;
      final raw = wide ? box.maxHeight * 0.58 : (box.maxWidth * 0.62 < box.maxHeight * 0.34 ? box.maxWidth * 0.62 : box.maxHeight * 0.34);
      final ringSize = raw.clamp(120.0, 260.0).toDouble();
      final ring = SizedBox(
        width: ringSize,
        height: ringSize,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: _progress.clamp(0.0, 1.0)),
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
          builder: (context, v, _) => CustomPaint(
            painter: _RingPainter(v),
            child: Center(
              child: Text(
                '$pct%',
                style: TextStyle(fontSize: ringSize * 0.25, fontWeight: FontWeight.w800, color: KColors.gold),
              ),
            ),
          ),
        ),
      );
      const title = Text('Exporting...', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white));
      final sub = Column(
        children: [
          const Text('Rendering your video...', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.white)),
          const SizedBox(height: 4),
          Text('Elapsed ${_elapsed()}', style: const TextStyle(fontSize: 12.5, color: Colors.white54)),
        ],
      );
      if (wide) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [title, const SizedBox(height: 12), ring, const SizedBox(height: 12), sub],
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [list, const SizedBox(height: 14), cancel],
                  ),
                ),
              ),
            ],
          ),
        );
      }
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          children: [
            title,
            const SizedBox(height: 22),
            ring,
            const SizedBox(height: 16),
            sub,
            const SizedBox(height: 22),
            list,
            const SizedBox(height: 16),
            cancel,
          ],
        ),
      );
    });
  }

  Widget _progressCard() {
    final pct = (_progress * 100).clamp(0, 100).round();
    const steps = ['Slides', 'Sound', 'Video'];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: KColors.lavender,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('$pct%', style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, height: 1)),
              const Spacer(),
              Text('Elapsed ${_elapsed()}', style: const TextStyle(fontSize: 13, color: Colors.white60)),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              height: 12,
              child: Stack(
                children: [
                  const Positioned.fill(child: ColoredBox(color: Color(0x33FFFFFF))),
                  Positioned.fill(
                    child: TweenAnimationBuilder<double>(
                      tween: Tween<double>(begin: 0, end: _progress.clamp(0.0, 1.0)),
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeOut,
                      builder: (context, v, _) => FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: v <= 0 ? 0.0 : v,
                        child: const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: [KColors.purple, KColors.gold]),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              for (var i = 0; i < steps.length; i++) ...[
                if (i > 0) const SizedBox(width: 14),
                Icon(
                  i < _phase
                      ? Icons.circle
                      : (i == _phase ? Icons.timelapse : Icons.radio_button_unchecked),
                  size: 16,
                  color: i <= _phase ? KColors.gold : Colors.white38,
                ),
                const SizedBox(width: 4),
                Text(
                  steps[i],
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: i == _phase ? FontWeight.w700 : FontWeight.w500,
                    color: i <= _phase ? Colors.white : Colors.white54,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final lesson = state.lessonById(widget.courseId, widget.lessonId);
    final media = MediaQuery.of(context);

    final stage = MediaQuery(
      data: media.copyWith(textScaler: TextScaler.noScaling),
      child: Material(
        type: MaterialType.transparency,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: RepaintBoundary(
            key: _stageKey,
            child: SizedBox(
              width: _stageW,
              height: _stageH,
              child: KeyedSubtree(
                key: ValueKey<int>(_stageSerial),
                child: _stageChild ?? const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ),
    );

    if (!_defaultsReady) {
      _quality = _qualities.containsKey(state.settings.videoHeight) ? state.settings.videoHeight : 720;
      _fps = state.settings.frameRate;
      _mbps = _qualities[_quality]!.$4;
      _defaultsReady = true;
    }
    if (lesson != null && !_nameReady) {
      _nameCtl.text = 'Quran_${_safeName(lesson.title)}${_verseRange(lesson)}';
      _nameReady = true;
    }
    final seconds = lesson == null ? 0 : (lesson.durationMs / 1000);
    final estMb = seconds * _mbps / 8 + seconds * 0.016;

    Widget card(Widget child) => Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: KColors.surface,
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [BoxShadow(color: Color(0x143B0F8C), blurRadius: 10, offset: Offset(0, 2))],
          ),
          child: child,
        );
    Widget label(String t) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(t, style: const TextStyle(fontWeight: FontWeight.w700, color: KColors.accent)),
        );

    final tiles = <Widget>[];
    for (final entry in _qualities.entries) {
      final q = entry.key;
      final info = entry.value;
      final on = q == _quality;
      tiles.add(
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(left: tiles.isEmpty ? 0 : 6),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: _busy
                  ? null
                  : () => setState(() {
                        _quality = q;
                        _mbps = info.$4;
                      }),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                decoration: BoxDecoration(
                  color: on ? KColors.selected : KColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: on ? KColors.purple : const Color(0xFF3D3266), width: on ? 2 : 1),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('${q}p', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(info.$2, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('${_outFor(q).$1}x${_outFor(q).$2}', style: const TextStyle(fontSize: 10, color: Colors.white60)),
                    ),
                    const SizedBox(height: 4),
                    Icon(on ? Icons.circle : Icons.circle_outlined,
                        size: 16, color: on ? Colors.white : Colors.white24),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    final content = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        card(Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.movie_creation_outlined, color: KColors.purple, size: 30),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(lesson?.title ?? 'Video',
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      if (lesson != null)
                        Text('${sceneCountText(lesson.scenes.length)}  -  ${formatClock(lesson.durationMs)}  -  about ${estMb.toStringAsFixed(estMb < 10 ? 1 : 0)} MB'),
                    ],
                  ),
                ),
              ],
            ),
            if (lesson != null && lesson.scenes.isNotEmpty) ...[
              const SizedBox(height: 12),
              // Drawn once and reused, so the progress updates do not redraw the slides.
              _thumbCache ??= RepaintBoundary(child: _thumbnails(lesson.scenes)),
            ],
          ],
        )),
        card(Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            label('File name'),
            TextField(
              controller: _nameCtl,
              enabled: !_busy,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                suffixText: '.mp4',
              ),
            ),
          ],
        )),
        card(Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            label('Quality'),
            IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: tiles),
            ),
            const SizedBox(height: 8),
            Text(
              '${_qualities[_quality]!.$3}${_quality == 720 ? '' : '  (720p is recommended)'}',
              style: const TextStyle(fontSize: 12, color: Colors.white60),
            ),
          ],
        )),
        card(Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            label('Format'),
            const Text('MP4 (H.264 video, AAC sound)'),
            const SizedBox(height: 14),
            label('Frame rate'),
            DropdownButton<int>(
              value: _fps,
              isExpanded: true,
              items: const [
                DropdownMenuItem(value: 24, child: Text('24 FPS (Cinematic)')),
                DropdownMenuItem(value: 30, child: Text('30 FPS (Smooth)')),
              ],
              onChanged: _busy ? null : (v) => setState(() => _fps = v ?? 30),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Expanded(
                  child: Text('Video bitrate', style: TextStyle(fontWeight: FontWeight.w700, color: KColors.accent)),
                ),
                const HelpIcon('Higher bitrate looks sharper and makes a bigger file.', title: 'Video bitrate'),
                Text('${_mbps.round()} Mbps', style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
            Slider(
              value: _mbps,
              min: 1,
              max: 30,
              divisions: 29,
              onChanged: _busy ? null : (v) => setState(() => _mbps = v),
            ),
          ],
        )),
        card(Row(
          children: [
            const Icon(Icons.save_alt, color: KColors.accent, size: 20),
            const SizedBox(width: 10),
            const Expanded(child: Text('Estimated size')),
            Text(
              '${estMb.toStringAsFixed(estMb < 10 ? 1 : 0)} MB',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        )),
        SizedBox(
          height: 54,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: KColors.selected,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            onPressed: lesson == null ? null : () => setState(() => _runPage = true),
            icon: const Icon(Icons.play_arrow_rounded, size: 26),
            label: const Text('Export Video'),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: () => Navigator.of(context).maybePop(), child: const Text('Cancel')),
      ],
    );

    // The final page: watermark switch, then the progress and the finished video.
    final Widget runContent = _busy ? _exportingView() : ListView(
      padding: const EdgeInsets.all(16),
      children: [
        card(Row(
          children: [
            const Icon(Icons.movie_creation_outlined, color: KColors.purple, size: 30),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(lesson?.title ?? 'Video',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text('${_quality}p  -  ${_fps} FPS  -  ${_mbps.round()} Mbps  -  about ${estMb.toStringAsFixed(estMb < 10 ? 1 : 0)} MB'),
                ],
              ),
            ),
          ],
        )),
        card(WatermarkCard(
          wm: state.settings.wm,
          enabled: !_busy,
          onChanged: (w) => state.updateSettings(state.settings.copyWith(wm: w)),
        )),
        if (_busy) ...[
          _progressCard(),
          const SizedBox(height: 12),
        ],
        if (_status.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              _status,
              style: TextStyle(
                color: _failed ? Theme.of(context).colorScheme.error : KColors.ink,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        if (_canPlay && !_busy) ...[
          FilledButton.icon(
            onPressed: _playVideo,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Play video'),
          ),
          const SizedBox(height: 8),
        ],
        if (!_busy && !_canPlay && _unsavedVideo == null)
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: KColors.gold,
              foregroundColor: KColors.onGold,
            ),
            onPressed: lesson == null ? null : _start,
            icon: const Icon(Icons.movie_creation_outlined),
            label: Text(_failed ? 'Try again' : 'Start export'),
          ),
        if (_busy && _phase != 99) OutlinedButton(onPressed: _cancel, child: const Text('Cancel')),
        if (_unsavedVideo != null && !_busy) ...[
          FilledButton(onPressed: _retrySave, child: const Text('Save video')),
          const SizedBox(height: 8),
        ],
        if (!_busy) ...[
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => setState(() => _runPage = false),
            child: const Text('Back to settings'),
          ),
        ],
      ],
    );

    final showSuccess = _runPage && _result != null && !_busy;
    return PopScope(
      canPop: !_busy && (!_runPage || _result != null),
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !_busy && _runPage) setState(() => _runPage = false);
      },
      child: Scaffold(
        appBar: showSuccess
            ? AppBar(
                backgroundColor: KColors.background,
                centerTitle: true,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                title: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.asset(
                        'assets/icon/app_icon.png',
                        width: 30,
                        height: 30,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(Icons.play_arrow_rounded, color: KColors.gold, size: 28),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text('Qur\'an Studio', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  ],
                ),
                actions: [
                  IconButton(icon: const Icon(Icons.more_vert), onPressed: _moreSheet),
                ],
              )
            : AppBar(centerTitle: true, title: Text(_runPage ? (_busy ? '' : 'Exporting') : 'Export Video')),
        body: Stack(
          clipBehavior: Clip.none,
          children: [
            // The drawing area sits behind the screen content.
            Positioned(
              left: 0,
              top: 0,
              width: _stageW,
              height: _stageH,
              child: IgnorePointer(child: stage),
            ),
            Positioned.fill(
              child: ColoredBox(
                color: Theme.of(context).scaffoldBackgroundColor,
                child: SafeArea(
                  child: showSuccess
                      ? ExportSuccessView(
                          latest: _result!,
                          history: _history,
                          onPlay: (e) => _viewEntry(e, 'play'),
                          onShare: (e) => _viewEntry(e, 'share'),
                          onOpenWith: (e) => _viewEntry(e, 'open'),
                          onMore: _moreSheet,
                          onRemove: _removeEntry,
                        )
                      : (_runPage ? runContent : content),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


class _RingPainter extends CustomPainter {
  _RingPainter(this.value);

  final double value;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.085;
    final rect = Rect.fromLTWH(stroke / 2, stroke / 2, size.width - stroke, size.height - stroke);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = const Color(0x337351FF);
    canvas.drawArc(rect, 0, 6.2831853, false, track);
    if (value <= 0) return;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: 6.2831853 * value.clamp(0.02, 1.0),
        colors: const [Color(0xFF7351FF), Color(0xFFA78BFA), Color(0xFFF6C101)],
        stops: const [0.0, 0.55, 1.0],
        transform: const GradientRotation(-1.5707963),
      ).createShader(rect);
    canvas.drawArc(rect, -1.5707963, 6.2831853 * value.clamp(0.0, 1.0), false, arc);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.value != value;
}

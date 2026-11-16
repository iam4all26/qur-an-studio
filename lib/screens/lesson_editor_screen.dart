import '../editor/side_sheet.dart';
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:kainuwa_encoder/kainuwa_encoder.dart';

import '../animation_math.dart';
import '../app_state.dart';
import '../demo_plan.dart';
import '../editor/drawing_screen.dart';
import '../srt_import.dart';
import '../transition_math.dart';
import '../store/store_tab.dart';
import '../editor/add_timeline_sheet.dart';
import '../editor/edit_panel.dart';
import '../editor/editor_history.dart';
import '../editor/editor_tools.dart';
import '../editor/fullscreen_player.dart';
import '../editor/lesson_player.dart';
import '../editor/timeline_panel.dart';
import '../editor/track_visibility.dart';
import '../media/media_library.dart';
import '../models.dart';
import '../store/store_graphics_sheet.dart';
import '../svg/svg_raster.dart';
import '../scene_canvas.dart';
import '../shape_fit.dart';
import '../stage_shape.dart';
import '../theme.dart';
import '../widgets.dart';
import 'audio_sheet.dart';
import 'editor_sheets.dart';
import 'export_screen.dart';
import 'video_setup_dialog.dart';

/// Width and height (as fractions of the slide) for an item with the given
/// picture shape, kept inside the given limits.
(double, double) fitBox(double aspect, {required double maxW, required double maxH}) {
  var w = maxW;
  var h = w * Stage.aspect / aspect;
  if (h > maxH) {
    h = maxH;
    w = h * aspect / Stage.aspect;
  }
  return (w, h);
}

/// Size taken from the mockup (941 px wide), scaled to this phone.
double _s(double u, double px, [double min = 0]) => math.max(min, px * u);

class LessonEditorScreen extends StatefulWidget {
  const LessonEditorScreen({
    super.key,
    required this.courseId,
    required this.lessonId,
  });

  final String courseId;
  final String lessonId;

  @override
  State<LessonEditorScreen> createState() => _LessonEditorScreenState();
}

class _LessonEditorScreenState extends State<LessonEditorScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  LessonPlayer? _player;
  EditorHistory? _history;

  String? _selectedId;
  String? _selectedAudioId;
  bool _sceneSelected = false;
  String? _soundSel; // 'music' or 'narration:<scene index>'
  int _tab = -1;
  final List<String> _order = List<String>.of(kDefaultTrackOrder);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppState.editorLandscape = AppScope.read(context).settings.landscape;
    AppState.setOrientation(landscape: AppState.editorLandscape);
    final lesson = AppScope.read(context).lessonById(widget.courseId, widget.lessonId);
    if (lesson != null) {
      Stage.use(lesson.aspectW, lesson.aspectH);
      if (lesson.scenes.isEmpty) {
        lesson.scenes.add(Scene(id: newId()));
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) AppScope.read(context).persist();
        });
      }
      _history = EditorHistory(lesson);
      final player = LessonPlayer(vsync: this, lesson: lesson);
      player.addListener(_onPlayer);
      _player = player;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AppState.editorLandscape = false;
    AppState.setOrientation(landscape: false);
    Stage.reset();
    _demoPending?.cancel();
    _demoTimer?.cancel();
    _demoMs.dispose();
    _player?.removeListener(_onPlayer);
    _player?.dispose();
    super.dispose();
  }

  void _onPlayer() {
    if (mounted) setState(() {});
  }

  // ---- small helpers ----

  Lesson? _lesson() => AppScope.read(context).lessonById(widget.courseId, widget.lessonId);

  Scene? _currentScene() {
    final lesson = _lesson();
    final player = _player;
    if (lesson == null || player == null || lesson.scenes.isEmpty) return null;
    return lesson.scenes[sceneAt(lesson, player.positionMs).index];
  }

  /// The last item copied with Copy. Pasting places a new item at exactly the same spot.
  static Map<String, dynamic>? _clipLayer;

  /// The last position copied with Copy position, as fractions of the slide.
  static (double, double)? _clipPos;

  /// The last size copied with Copy size, as fractions of the slide (width, height).
  static (double, double)? _clipSize;

  Layer? _selectedLayer(Scene? scene) {
    if (scene == null || _selectedId == null) return null;
    for (final layer in scene.layers) {
      if (layer.id == _selectedId) return layer;
    }
    return null;
  }

  void _pause() => _player?.pause();

  // ---- live demo of an item's animations on the canvas (while the Animate panel is open) ----

  final ValueNotifier<int?> _demoMs = ValueNotifier<int?>(null);
  String? _demoId;
  Timer? _demoTimer;
  Timer? _demoPending;
  final Stopwatch _demoClock = Stopwatch();

  void _onDemo(Layer? layer) {
    _demoPending?.cancel();
    if (layer == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _stopDemo());
      return;
    }
    // Wait a moment so dragging a slider does not restart the demo on every step.
    _demoPending = Timer(const Duration(milliseconds: 150), () => _startDemo(layer));
  }

  void _startDemo(Layer layer) {
    _demoTimer?.cancel();
    _demoId = layer.id;
    _demoClock
      ..reset()
      ..start();
    _demoTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      final total = math.max(1, demoPlan(layer).total);
      _demoMs.value = _demoClock.elapsedMilliseconds % total;
    });
  }

  void _stopDemo() {
    _demoPending?.cancel();
    _demoTimer?.cancel();
    _demoTimer = null;
    _demoClock.stop();
    _demoId = null;
    _demoMs.value = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _pause();
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _needItem() => _snack('Select an item on the slide or on the timeline first.');

  Future<void> _commit() async {
    final lesson = _lesson();
    if (lesson != null) {
      _history?.record(lesson);
      _player?.clampToLesson();
    }
    if (mounted) setState(() {});
    if (!mounted) return;
    await AppScope.read(context).persist();
  }

  void _selectLayer(String? id) {
    setState(() {
      _selectedId = id;
      _selectedAudioId = null;
      _soundSel = null;
      _sceneSelected = false;
    });
  }

  void _seekToScene(Lesson lesson, int index) {
    final player = _player;
    if (player == null) return;
    final spot = sceneAt(lesson, player.positionMs);
    if (spot.index != index) player.seek(sceneStartMs(lesson, index));
  }

  void _selectScene(int index) {
    final lesson = _lesson();
    if (lesson == null || index >= lesson.scenes.length) return;
    _seekToScene(lesson, index);
    setState(() {
      _selectedId = null;
      _selectedAudioId = null;
      _soundSel = null;
      _sceneSelected = true;
    });
  }

  void _selectSound(String kind, int index) {
    final lesson = _lesson();
    if (lesson == null || index >= lesson.scenes.length) return;
    _seekToScene(lesson, index);
    setState(() {
      _selectedId = null;
      _selectedAudioId = null;
      _sceneSelected = false;
      _soundSel = kind == 'music' ? 'music' : 'narration:$index';
    });
  }

  int? _soundScene() {
    final key = _soundSel;
    if (key == null || !key.startsWith('narration:')) return null;
    return int.tryParse(key.substring(10));
  }

  void _deleteSound() {
    final lesson = _lesson();
    if (lesson == null || _soundSel == null) return;
    _pause();
    if (_soundSel == 'music') {
      lesson.musicPath = '';
    } else {
      final i = _soundScene();
      if (i != null && i < lesson.scenes.length) {
        lesson.scenes[i].narrationPath = '';
        lesson.scenes[i].narrationMs = 0;
      }
    }
    _soundSel = null;
    _commit();
  }

  void _selectLayerFromTimeline(int sceneIndex, String id) {
    final lesson = _lesson();
    if (lesson == null || sceneIndex >= lesson.scenes.length) return;
    _seekToScene(lesson, sceneIndex);
    setState(() {
      _selectedId = id;
      _selectedAudioId = null;
      _soundSel = null;
      _sceneSelected = false;
    });
  }

  // ---- undo, redo, save, export ----

  Future<void> _undo() async {
    final lesson = _lesson();
    final history = _history;
    if (lesson == null || history == null) return;
    _pause();
    if (history.undo(lesson)) {
      Stage.use(lesson.aspectW, lesson.aspectH);
      _player?.clampToLesson();
      setState(() {
        _selectedId = null;
        _soundSel = null;
        _sceneSelected = false;
      });
      await AppScope.read(context).persist();
    }
  }

  Future<void> _redo() async {
    final lesson = _lesson();
    final history = _history;
    if (lesson == null || history == null) return;
    _pause();
    if (history.redo(lesson)) {
      Stage.use(lesson.aspectW, lesson.aspectH);
      _player?.clampToLesson();
      setState(() {
        _selectedId = null;
        _soundSel = null;
        _sceneSelected = false;
      });
      await AppScope.read(context).persist();
    }
  }

  Future<void> _save() async {
    await AppScope.read(context).persist();
    if (mounted) _snack('Saved on this phone.');
  }

  void _export() {
    _pause();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ExportScreen(courseId: widget.courseId, lessonId: widget.lessonId),
      ),
    );
  }

  void _fullscreen(Lesson lesson) {
    final player = _player;
    if (player == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FullscreenPlayer(lesson: lesson, player: player),
      ),
    );
  }

  // ---- adding things ----

  void _addLayer(Scene scene, Layer layer) {
    scene.layers.add(layer);
    _selectedId = layer.id;
    _sceneSelected = false;
    _commit();
  }

  Future<void> _openAdd() async {
    final choice = await showAddSheet(context);
    if (choice == null || !mounted) return;
    switch (choice) {
      case 'text':
        await _addText();
        break;
      case 'icon':
        await _addIcon();
        break;
      case 'image':
        await _addImage();
        break;
      case 'shape':
        await _addShape();
        break;
    }
  }

  Future<void> _setBackground() async {
    final scene = _currentScene();
    if (scene == null) return;
    final choice = await showBackgroundSheet(context);
    if (choice == null) return;
    scene.bgType = choice.type;
    scene.bgValue = choice.value;
    _commit();
  }

  Future<void> _addText() async {
    final scene = _currentScene();
    if (scene == null) return;
    final text = await promptText(
      context,
      title: 'Add text',
      label: 'Text',
      confirm: 'Add',
      maxLength: 200,
      multiline: true,
    );
    if (text == null || !mounted) return;
    final layer = Layer(
      id: newId(),
      type: 'text',
      text: text,
      color: scene.isDarkBackground ? 0xFFFFFFFF : 0xFF1E1433,
    );
    setLayerTextSizePx(layer, 72);
    if (layer.w > 0.9) {
      final f = 0.9 / layer.w;
      layer.w = 0.9;
      layer.h = layer.h * f;
    }
    _addLayer(scene, layer);
  }

  Future<void> _addSubtitles() async {
    final how = await showEditorSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.subtitles_outlined),
              title: const Text('Type one caption'),
              subtitle: const Text('Adds a caption on the current slide'),
              onTap: () => Navigator.of(sheetContext).pop('one'),
            ),
            ListTile(
              leading: const Icon(Icons.upload_file),
              title: const Text('Import an SRT file'),
              subtitle: const Text('Adds every caption at its own time'),
              onTap: () => Navigator.of(sheetContext).pop('srt'),
            ),
          ],
        ),
      ),
    );
    if (how == null || !mounted) return;
    if (how == 'srt') {
      await _importSrt();
      return;
    }
    final scene = _currentScene();
    if (scene == null) return;
    final text = await promptText(
      context,
      title: 'Add subtitles',
      label: 'Caption',
      confirm: 'Add',
      maxLength: 200,
      multiline: true,
    );
    if (text == null || !mounted) return;
    final layer = Layer(
      id: newId(),
      type: 'text',
      text: text,
      cy: 0.86,
      color: 0xFFFFFFFF,
      bold: false,
      bgBox: true,
      bgColor: 0xCC000000,
    );
    setLayerTextSizePx(layer, 40);
    if (layer.w > 0.92) {
      final f = 0.92 / layer.w;
      layer.w = 0.92;
      layer.h = layer.h * f;
    }
    _addLayer(scene, layer);
  }

  Future<void> _importSrt() async {
    final lesson = _lesson();
    if (lesson == null) return;
    String? picked;
    try {
      picked = await KainuwaEncoder.pickAnyFile();
    } catch (_) {
      picked = null;
    }
    if (picked == null || !mounted) return;
    List<SrtCue> cues;
    try {
      cues = parseSrt(await File(picked).readAsString());
    } catch (_) {
      cues = [];
    }
    try {
      await File(picked).delete();
    } catch (_) {}
    if (cues.isEmpty) {
      _snack('No captions were found in that file.');
      return;
    }
    var added = 0;
    var start = 0;
    for (final scene in lesson.scenes) {
      final end = start + scene.durationMs;
      for (final cue in cues) {
        final from = math.max(cue.startMs, start);
        final to = math.min(cue.endMs, end);
        if (to - from < 100) continue;
        final layer = Layer(
          id: newId(),
          type: 'text',
          text: cue.text,
          cy: 0.86,
          color: 0xFFFFFFFF,
          bold: false,
          bgBox: true,
          bgColor: 0xCC000000,
          startMs: from - start,
          endMs: to - start,
        );
        setLayerTextSizePx(layer, 40);
        if (layer.w > 0.92) {
          final f = 0.92 / layer.w;
          layer.w = 0.92;
          layer.h = layer.h * f;
        }
        scene.layers.add(layer);
        added++;
      }
      start = end;
    }
    if (added == 0) {
      _snack('The captions are all after the end of this video.');
      return;
    }
    _selectedId = null;
    _commit();
    _snack('Added $added captions.');
  }

  Future<void> _addDrawing() async {
    final scene = _currentScene();
    if (scene == null) return;
    _pause();
    final result = await showDrawingScreen(context);
    if (result == null || !mounted) return;
    final box = fitBox(result.aspect, maxW: 0.6, maxH: 0.8);
    _addLayer(scene, Layer(id: newId(), type: 'image', w: box.$1, h: box.$2, path: result.path));
  }

  Future<void> _addIcon() async {
    final scene = _currentScene();
    if (scene == null) return;
    final item = await showAssetSheet(context);
    if (item == null) return;
    if (item.isFile) {
      await _addSvg(scene, item.path, tint: item.tint);
      return;
    }
    if (item.path.startsWith('assets/') && item.path.endsWith('.svg')) {
      final raster = await rasterizeSvgAsset(item.path);
      if (!mounted) return;
      if (raster == null) {
        _snack('That icon could not be read.');
        return;
      }
      final b = fitBox(raster.aspect, maxW: 0.28, maxH: 0.5);
      _addLayer(scene, Layer(id: newId(), type: 'image', w: b.$1, h: b.$2, path: raster.path));
      return;
    }
    // Built-in icons also exist as SVG: use those, so they stay sharp at any size.
    if (item.path.startsWith('assets/icons/') && item.path.endsWith('.png')) {
      final svgAsset = item.path
          .replaceFirst('assets/icons/', 'assets/icons_svg/')
          .replaceFirst(RegExp(r'\.png$'), '.svg');
      final raster = await rasterizeSvgAsset(svgAsset);
      if (!mounted) return;
      if (raster != null) {
        final b = fitBox(raster.aspect, maxW: 0.28, maxH: 0.5);
        _addLayer(
          scene,
          Layer(id: newId(), type: 'image', w: b.$1, h: b.$2, path: raster.path),
        );
        return;
      }
    }
    final box = fitBox(1.0, maxW: 0.28, maxH: 0.5);
    _addLayer(scene, Layer(id: newId(), type: 'asset', w: box.$1, h: box.$2, path: item.path));
  }

  Future<double> _imageAspect(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 128);
      final frame = await codec.getNextFrame();
      final aspect = frame.image.width / frame.image.height;
      frame.image.dispose();
      codec.dispose();
      return aspect;
    } catch (_) {
      return 1.0;
    }
  }

  Future<void> _addImage() async {
    final scene = _currentScene();
    if (scene == null) return;
    List<String> paths;
    try {
      paths = await pickMediaMany(context, MediaKind.image);
    } catch (_) {
      paths = [];
    }
    if (paths.isEmpty || !mounted) return;
    if (paths.length == 1 && paths.first.toLowerCase().endsWith('.svg')) {
      await _addSvg(scene, paths.first, tint: false);
      return;
    }
    var n = 0;
    for (final path in paths) {
      if (path.toLowerCase().endsWith('.svg')) continue;
      final aspect = await _imageAspect(path);
      if (!mounted) return;
      final box = fitBox(aspect, maxW: 0.6, maxH: 0.8);
      final layer = Layer(id: newId(), type: 'image', w: box.$1, h: box.$2, path: path);
      layer.cx = (0.5 + n * 0.04).clamp(0.2, 0.8).toDouble();
      layer.cy = (0.5 + n * 0.04).clamp(0.2, 0.8).toDouble();
      scene.layers.add(layer);
      _selectedId = layer.id;
      n++;
    }
    if (n == 0) return;
    _sceneSelected = false;
    _commit();
  }

  Future<void> _addSvg(Scene scene, String svgPath, {required bool tint}) async {
    final raster = await rasterizeSvg(svgPath);
    if (!mounted) return;
    if (raster == null) {
      _snack('That SVG could not be read.');
      return;
    }
    final box = fitBox(raster.aspect, maxW: 0.4, maxH: 0.5);
    _addLayer(
      scene,
      Layer(
        id: newId(),
        type: 'image',
        shape: tint ? 'tint' : 'rect',
        color: 0xFFF6C101,
        w: box.$1,
        h: box.$2,
        path: raster.path,
      ),
    );
  }

  Future<void> _addShape() async {
    final scene = _currentScene();
    if (scene == null) return;
    final kind = await showShapeSheet(context);
    if (kind == null) return;
    if (kind.startsWith('file:')) {
      await _addSvg(scene, kind.substring(5), tint: false);
      return;
    }
    if (kind == 'store') {
      if (!mounted) return;
      final item = await showStoreGraphicsSheet(context);
      if (item == null || !mounted) return;
      if (item.path.toLowerCase().endsWith('.svg')) {
        await _addSvg(scene, item.path, tint: item.type == 'icon');
      } else {
        final aspect = await _imageAspect(item.path);
        if (!mounted) return;
        final pic = fitBox(aspect, maxW: 0.6, maxH: 0.8);
        _addLayer(scene, Layer(id: newId(), type: 'image', w: pic.$1, h: pic.$2, path: item.path));
      }
      return;
    }
    final box = kind == 'circle'
        ? fitBox(1.0, maxW: 0.25, maxH: 0.45)
        : fitBox(1.6, maxW: 0.4, maxH: 0.4);
    _addLayer(
      scene,
      Layer(
        id: newId(),
        type: 'shape',
        shape: kind,
        w: box.$1,
        h: box.$2,
        color: 0xFFF6C101,
      ),
    );
  }

  Future<void> _openAudio() async {
    final lesson = _lesson();
    final scene = _currentScene();
    if (lesson == null || scene == null) return;
    await showAudioSheet(context, lesson: lesson, scene: scene, onChanged: _commit);
    _commit();
  }

  Future<void> _openEdit(String tab) async {
    final scene = _currentScene();
    if (scene == null) return;
    _pause();
    final layer = _selectedLayer(scene);
    if (layer == null) {
      _needItem();
      return;
    }
    await showEditPanel(
      context,
      layer: layer,
      scene: scene,
      initialTab: tab,
      onLive: () {
        if (mounted) setState(() {});
      },
      onDemo: _onDemo,
      onApplyAll: _applyAnimToAll,
    );
    _stopDemo();
    _commit();
  }

  Future<void> _openAnimate() => _openEdit('animation');

  /// Copies one part of an item's animation to every other item of the same kind
  /// (texts with texts, pictures and shapes together) on this slide or in the whole video.
  int _applyAnimToAll(Layer source, String part, bool wholeVideo) {
    final lesson = _lesson();
    if (lesson == null) return 0;
    final scenes = wholeVideo ? lesson.scenes : <Scene>[if (_currentScene() != null) _currentScene()!];
    final sourceIsText = source.type == 'text';
    var count = 0;
    for (final scene in scenes) {
      for (final other in scene.layers) {
        if (identical(other, source)) continue;
        if ((other.type == 'text') != sourceIsText) continue;
        switch (part) {
          case 'in':
            other.animIn = source.animIn;
            other.animInDir = source.animInDir;
            other.animDurationMs = source.animDurationMs;
            other.animStartMs = source.animStartMs;
            break;
          case 'out':
            other.animOut = source.animOut;
            other.animOutDir = source.animOutDir;
            other.animOutDurationMs = source.animOutDurationMs;
            break;
          case 'overall':
            other.animLoop = source.animLoop;
            other.animLoopMs = source.animLoopMs;
            break;
          case 'text':
            other.textAnim = source.textAnim;
            other.textAnimMs = source.textAnimMs;
            break;
          default:
            continue;
        }
        count++;
      }
    }
    if (count > 0) _commit();
    return count;
  }

  Future<void> _setDuration() async {
    final scene = _currentScene();
    if (scene == null) return;
    final ms = await showDurationSheet(context, scene.durationMs, minMs: scene.narrationLenMs);
    if (ms == null) return;
    scene.durationMs = ms;
    _commit();
  }

  // ---- toolbar: Split, Duplicate, Delete, Layer, Adjust, Volume, Speed ----

  void _split() {
    if (_selectedAudioId != null) {
      _splitAudio();
      return;
    }
    final selScene = _currentScene();
    final selLayer = _sceneSelected ? null : _selectedLayer(selScene);
    if (selScene != null && selLayer != null) {
      _splitLayer(selScene, selLayer);
      return;
    }
    final lesson = _lesson();
    final player = _player;
    if (lesson == null || player == null) return;
    _pause();
    final spot = sceneAt(lesson, player.positionMs);
    final scene = lesson.scenes[spot.index];
    final local = spot.localMs;
    if (local < 500 || scene.durationMs - local < 500) {
      _snack('Move the playhead inside a slide, at least half a second from its edges, to split it.');
      return;
    }
    if (scene.narrationPath.isNotEmpty && local < scene.narrationLenMs) {
      _snack('The narration of this slide runs past this point. Move the playhead after it ends, or remove the narration first.');
      return;
    }
    final second = scene.duplicate();
    second.narrationPath = '';
    second.narrationMs = 0;
    if (second.hasVideo) second.videoStartMs = scene.videoStartMs + local;
    for (final layer in second.layers) {
      layer.animIn = 'none';
    }
    final original = scene.durationMs;
    scene.durationMs = local;
    second.durationMs = original - local;
    lesson.scenes.insert(spot.index + 1, second);
    player.seek(sceneStartMs(lesson, spot.index + 1));
    _selectedId = null;
    _sceneSelected = true;
    _commit();
  }

  /// Cuts an item (text, picture, icon, shape) in two at the playhead.
  void _splitLayer(Scene scene, Layer layer) {
    final lesson = _lesson();
    final player = _player;
    if (lesson == null || player == null) return;
    _pause();
    final spot = sceneAt(lesson, player.positionMs);
    if (lesson.scenes[spot.index] != scene) {
      _snack('Move the playhead inside this slide to split the item.');
      return;
    }
    final local = spot.localMs;
    final end = layerEndMs(layer, scene.durationMs);
    if (local - layer.startMs < 300 || end - local < 300) {
      _snack('Move the playhead inside the item, at least 0.3 seconds from its edges, to split it.');
      return;
    }
    final second = layer.copy();
    second.startMs = local;
    second.endMs = layer.endMs;
    second.animIn = 'none';
    second.animStartMs = 0;
    second.textAnim = 'none';
    second.hand = '';
    layer.endMs = local;
    layer.animOut = 'none';
    final at = scene.layers.indexOf(layer);
    scene.layers.insert(at + 1, second);
    _selectedId = second.id;
    _sceneSelected = false;
    _commit();
  }

  void _copyLayer() {
    final layer = _selectedLayer(_currentScene());
    if (layer == null) return;
    _clipLayer = layer.toJson();
    _clipPos = (layer.cx, layer.cy);
    setState(() {});
    _snack('Copied. Paste puts a new copy in exactly the same place, on any slide.');
  }

  void _pasteLayer() {
    final scene = _currentScene();
    final clip = _clipLayer;
    if (scene == null || clip == null) return;
    final copy = Layer.fromJson({...clip, 'id': newId()});
    if (copy.startMs >= scene.durationMs - 300) copy.startMs = 0;
    if (copy.endMs >= 0 && copy.endMs > scene.durationMs) copy.endMs = -1;
    _addLayer(scene, copy);
  }

  /// Exact X and Y of the selected item's centre, in percent of the slide, with copy and paste of the position.
  Future<void> _positionSheet() async {
    final scene = _currentScene();
    final layer = _selectedLayer(scene);
    if (layer == null) return;
    _pause();
    String fmt(double v) => (v * 100).toStringAsFixed(1);
    final xc = TextEditingController(text: fmt(layer.cx));
    final yc = TextEditingController(text: fmt(layer.cy));
    final wc = TextEditingController(text: fmt(layer.w));
    final hc = TextEditingController(text: fmt(layer.h));
    void applySize() {
      final w = double.tryParse(wc.text.trim().replaceAll(',', '.'));
      final h = double.tryParse(hc.text.trim().replaceAll(',', '.'));
      if (w != null) layer.w = (w / 100).clamp(0.02, 3.0).toDouble();
      if (h != null) layer.h = (h / 100).clamp(0.02, 3.0).toDouble();
      _commit();
    }

    void apply() {
      final x = double.tryParse(xc.text.trim().replaceAll(',', '.'));
      final y = double.tryParse(yc.text.trim().replaceAll(',', '.'));
      if (x != null) layer.cx = (x / 100).clamp(0.0, 1.0).toDouble();
      if (y != null) layer.cy = (y / 100).clamp(0.0, 1.0).toDouble();
      _commit();
    }

    await showEditorSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheet) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(sheetContext).viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Position and size', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                const Text('Centre of the item, in percent of the slide. 0 is left or top, 100 is right or bottom.',
                    style: TextStyle(color: Color(0xFFB5ABD6))),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: xc,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'X %', border: OutlineInputBorder()),
                      onChanged: (_) => apply(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: yc,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Y %', border: OutlineInputBorder()),
                      onChanged: (_) => apply(),
                    ),
                  ),
                ]),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: wc,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Width %', border: OutlineInputBorder()),
                      onChanged: (_) => applySize(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: hc,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Height %', border: OutlineInputBorder()),
                      onChanged: (_) => applySize(),
                    ),
                  ),
                ]),
                const SizedBox(height: 14),
                Wrap(spacing: 10, runSpacing: 10, children: [
                  FilledButton(
                    onPressed: () {
                      applySize();
                      _clipSize = (layer.w, layer.h);
                      setSheet(() {});
                      _snack('Size copied: ${fmt(layer.w)}% by ${fmt(layer.h)}%');
                    },
                    child: const Text('Copy size'),
                  ),
                  FilledButton(
                    onPressed: _clipSize == null
                        ? null
                        : () {
                            layer.w = _clipSize!.$1;
                            layer.h = _clipSize!.$2;
                            wc.text = fmt(layer.w);
                            hc.text = fmt(layer.h);
                            _commit();
                            setSheet(() {});
                          },
                    child: Text(_clipSize == null
                        ? 'Paste size'
                        : 'Paste size (${fmt(_clipSize!.$1)} x ${fmt(_clipSize!.$2)})'),
                  ),
                  FilledButton(
                    onPressed: () {
                      apply();
                      _clipPos = (layer.cx, layer.cy);
                      setSheet(() {});
                      _snack('Position copied: X ${fmt(layer.cx)}%  Y ${fmt(layer.cy)}%');
                    },
                    child: const Text('Copy position'),
                  ),
                  FilledButton(
                    onPressed: _clipPos == null
                        ? null
                        : () {
                            layer.cx = _clipPos!.$1;
                            layer.cy = _clipPos!.$2;
                            xc.text = fmt(layer.cx);
                            yc.text = fmt(layer.cy);
                            _commit();
                            setSheet(() {});
                          },
                    child: Text(_clipPos == null
                        ? 'Paste position'
                        : 'Paste position (${fmt(_clipPos!.$1)}, ${fmt(_clipPos!.$2)})'),
                  ),
                  OutlinedButton(
                    onPressed: () {
                      layer.cx = 0.5;
                      layer.cy = 0.5;
                      xc.text = '50.0';
                      yc.text = '50.0';
                      _commit();
                      setSheet(() {});
                    },
                    child: const Text('Centre'),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
    xc.dispose();
    yc.dispose();
    wc.dispose();
    hc.dispose();
  }

  void _duplicateSelection() {
    if (_selectedAudioId != null) {
      _duplicateAudio();
      return;
    }
    final lesson = _lesson();
    final scene = _currentScene();
    if (lesson == null || scene == null) return;
    _pause();
    final layer = _selectedLayer(scene);
    if (layer != null) {
      _duplicateLayer(scene, layer);
      return;
    }
    _duplicateScene();
  }

  void _duplicateScene() {
    final lesson = _lesson();
    final scene = _currentScene();
    if (lesson == null || scene == null) return;
    _pause();
    final index = lesson.scenes.indexOf(scene);
    lesson.scenes.insert(index + 1, scene.duplicate());
    _player?.seek(sceneStartMs(lesson, index + 1));
    _selectedId = null;
    _sceneSelected = true;
    _commit();
  }

  void _deleteSelection() {
    if (_soundSel != null) {
      _deleteSound();
      return;
    }
    if (_selectedAudioId != null) {
      _deleteAudio();
      return;
    }
    final lesson = _lesson();
    final scene = _currentScene();
    if (lesson == null || scene == null) return;
    _pause();
    final layer = _selectedLayer(scene);
    if (layer != null) {
      _deleteLayer(scene, layer);
      return;
    }
    if (lesson.scenes.length <= 1) {
      _snack('A video needs at least one slide.');
      return;
    }
    final index = lesson.scenes.indexOf(scene);
    lesson.scenes.removeAt(index);
    _player?.seek(sceneStartMs(lesson, math.min(index, lesson.scenes.length - 1)));
    _selectedId = null;
    _sceneSelected = false;
    _commit();
  }

  void _duplicateLayer(Scene scene, Layer layer) {
    final copy = layer.copy();
    copy.cx = (copy.cx + 0.04).clamp(0.0, 1.0).toDouble();
    copy.cy = (copy.cy + 0.04).clamp(0.0, 1.0).toDouble();
    _addLayer(scene, copy);
  }

  void _deleteLayer(Scene scene, Layer layer) {
    scene.layers.remove(layer);
    _selectedId = null;
    _commit();
  }

  Future<void> _openLayers() async {
    final scene = _currentScene();
    if (scene == null) return;
    _pause();
    await showLayersSheet(
      context,
      scene: scene,
      selectedId: _selectedId,
      onSelect: _selectLayer,
      onChanged: () {
        _commit();
      },
    );
  }

  Future<void> _adjust() async {
    final scene = _currentScene();
    final layer = _selectedLayer(scene);
    await _openEdit(layer != null && layer.type == 'text' ? 'content' : 'style');
  }

  Future<void> _volume() async {
    if (_selectedAudioId != null) {
      await _audioSettings();
      return;
    }
    final lesson = _lesson();
    final scene = _currentScene();
    if (lesson == null || scene == null) return;
    _pause();
    await showVolumeSheet(
      context,
      lesson: lesson,
      scene: scene,
      onLive: () {
        if (mounted) setState(() {});
      },
    );
    _commit();
  }

  Future<void> _speed() async {
    final scene = _currentScene();
    if (scene == null) return;
    _pause();
    final layer = _selectedLayer(scene);
    if (layer == null) {
      _needItem();
      return;
    }
    await showSpeedSheet(
      context,
      layer,
      onLive: () {
        if (mounted) setState(() {});
      },
    );
    _commit();
  }

  // ---- video clips ----

  Future<void> _addVideo() async {
    final lesson = _lesson();
    final player = _player;
    if (lesson == null || player == null) return;
    _pause();
    List<String> paths;
    try {
      paths = await pickMediaMany(context, MediaKind.video);
    } catch (_) {
      paths = [];
    }
    if (paths.isEmpty || !mounted) return;
    final spot = sceneAt(lesson, player.positionMs);
    var insertAt = spot.index + 1;
    var firstAt = -1;
    var unreadable = 0;
    for (final path in paths) {
      var ms = 0;
      try {
        ms = await KainuwaEncoder.audioDuration(path);
      } catch (_) {
        ms = 0;
      }
      if (!mounted) return;
      if (ms <= 0) {
        unreadable++;
        continue;
      }
      lesson.scenes.insert(
        insertAt,
        Scene(
          id: newId(),
          durationMs: ms,
          bgType: 'color',
          bgValue: '4278190080',
          videoPath: path,
          videoMs: ms,
          videoFill: true,
        ),
      );
      if (firstAt < 0) firstAt = insertAt;
      insertAt++;
    }
    if (firstAt < 0) {
      _snack('This video could not be read.');
      return;
    }
    if (unreadable > 0) _snack('$unreadable video(s) could not be read and were skipped.');
    player.seek(sceneStartMs(lesson, firstAt));
    _selectedId = null;
    _selectedAudioId = null;
    _soundSel = null;
    _sceneSelected = true;
    _commit();
  }

  /// Opens the Store on top of the editor, so nothing here has to be closed to download items.
  Future<void> _openStore() async {
    _pause();
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Store')),
          body: const StoreTab(active: true, showTitle: false),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  // ---- replace the file of the selected item, keeping everything else ----

  Future<void> _replaceMedia() async {
    final lesson = _lesson();
    final scene = _currentScene();
    if (lesson == null) return;
    _pause();
    if (_selectedAudioId != null) {
      AudioClip? clip;
      for (final c in lesson.audioClips) {
        if (c.id == _selectedAudioId) clip = c;
      }
      if (clip == null) return;
      String? path;
      try {
        path = await pickMedia(context, MediaKind.audio);
      } catch (_) {
        path = null;
      }
      if (path == null || !mounted) return;
      var ms = 0;
      try {
        ms = await KainuwaEncoder.audioDuration(path);
      } catch (_) {
        ms = 0;
      }
      if (!mounted) return;
      if (ms <= 0) {
        _snack('That audio file could not be read.');
        return;
      }
      clip.path = path;
      clip.label = _clipName(path);
      clip.sourceMs = ms;
      if (clip.trimMs >= ms - 500) clip.trimMs = 0;
      clip.durationMs = math.max(500, math.min(clip.durationMs, ms - clip.trimMs));
      _commit();
      return;
    }
    final layer = _selectedLayer(scene);
    if (layer != null) {
      if (layer.type == 'shape' && scene != null) {
        await _replaceShape(scene, layer);
        return;
      }
      if (layer.type != 'image') {
        _snack('Replace works for pictures and shapes. Delete and add a new one for this item.');
        return;
      }
      String? path;
      try {
        path = await pickMedia(context, MediaKind.image);
      } catch (_) {
        path = null;
      }
      if (path == null || !mounted) return;
      var use = path;
      if (path.toLowerCase().endsWith('.svg')) {
        final raster = await rasterizeSvg(path);
        if (!mounted) return;
        if (raster == null) {
          _snack('That SVG could not be read.');
          return;
        }
        use = raster.path;
      }
      layer.path = use;
      _commit();
      return;
    }
    if (_sceneSelected && scene != null && scene.hasVideo) {
      String? path;
      try {
        path = await pickMedia(context, MediaKind.video);
      } catch (_) {
        path = null;
      }
      if (path == null || !mounted) return;
      var ms = 0;
      try {
        ms = await KainuwaEncoder.audioDuration(path);
      } catch (_) {
        ms = 0;
      }
      if (!mounted) return;
      if (ms <= 0) {
        _snack('This video could not be read.');
        return;
      }
      scene.videoPath = path;
      scene.videoMs = ms;
      _commit();
    }
  }

  /// Swaps a shape for another shape (basic or from the store), keeping its place, size and timing.
  Future<void> _replaceShape(Scene scene, Layer layer) async {
    final kind = await showShapeSheet(context);
    if (kind == null || !mounted) return;
    final at = scene.layers.indexOf(layer);
    if (at < 0) return;
    Layer next;
    if (kind == 'circle' || kind == 'round' || kind == 'rect') {
      next = Layer.fromJson({...layer.toJson(), 'type': 'shape', 'shape': kind, 'path': ''});
    } else {
      String? svg;
      var tint = false;
      if (kind.startsWith('file:')) {
        svg = kind.substring(5);
      } else if (kind == 'store') {
        final item = await showStoreGraphicsSheet(context);
        if (item == null || !mounted) return;
        svg = item.path;
        tint = item.type == 'icon';
      }
      if (svg == null) return;
      String use = svg;
      double aspect = 1.0;
      if (svg.toLowerCase().endsWith('.svg')) {
        final raster = await rasterizeSvg(svg);
        if (!mounted) return;
        if (raster == null) {
          _snack('That SVG could not be read.');
          return;
        }
        use = raster.path;
        aspect = raster.aspect;
      } else {
        aspect = await _imageAspect(svg);
        if (!mounted) return;
      }
      final box = fitBox(aspect, maxW: math.max(0.1, layer.w), maxH: math.max(0.1, layer.h));
      next = Layer.fromJson({
        ...layer.toJson(),
        'type': 'image',
        'shape': tint ? 'tint' : 'rect',
        'path': use,
        'w': box.$1,
        'h': box.$2,
      });
    }
    scene.layers[at] = next;
    _selectedId = next.id;
    _commit();
  }

  Future<void> _videoSettings() async {
    final scene = _currentScene();
    if (scene == null || !scene.hasVideo) return;
    _pause();
    await showEditorSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheet) {
          final maxStart = math.max(0, scene.videoMs - 1000);
          return SingleChildScrollView(child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Video clip', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Play the original sound'),
                  value: !scene.videoMuted,
                  onChanged: (v) {
                    setSheet(() => scene.videoMuted = !v);
                    if (mounted) setState(() {});
                  },
                ),
                Text('Original sound volume: ${(scene.videoVolume * 100).round()} percent'),
                Slider(
                  value: scene.videoVolume.clamp(0.0, 2.0).toDouble(),
                  min: 0,
                  max: 2,
                  divisions: 20,
                  onChanged: scene.videoMuted
                      ? null
                      : (v) => setSheet(() => scene.videoVolume = v),
                ),
                if (!scene.phoneFrame)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Fill the frame'),
                    subtitle: const Text('Crops the edges so there are no black bars'),
                    value: scene.videoFill,
                    onChanged: (v) {
                      setSheet(() => scene.videoFill = v);
                      if (mounted) setState(() {});
                    },
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Phone frame'),
                  subtitle: const Text('Shows the video inside a phone, on your background'),
                  value: scene.phoneFrame,
                  onChanged: (v) {
                    setSheet(() => scene.phoneFrame = v);
                    if (mounted) setState(() {});
                  },
                ),
                if (scene.phoneFrame) ...[
                  Text('Phone size: ${(scene.phoneScale * 100).round()} percent'),
                  Slider(
                    value: scene.phoneScale.clamp(0.4, 1.0).toDouble(),
                    min: 0.4,
                    max: 1.0,
                    divisions: 12,
                    onChanged: (v) {
                      setSheet(() => scene.phoneScale = v);
                      if (mounted) setState(() {});
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Light phone body'),
                    value: scene.phoneLight,
                    onChanged: (v) {
                      setSheet(() => scene.phoneLight = v);
                      if (mounted) setState(() {});
                    },
                  ),
                ],
                Text('Start the clip at: ${(scene.videoStartMs / 1000).toStringAsFixed(1)} seconds'),
                Slider(
                  value: scene.videoStartMs.clamp(0, maxStart).toDouble(),
                  min: 0,
                  max: math.max(1, maxStart).toDouble(),
                  onChanged: maxStart <= 0
                      ? null
                      : (v) => setSheet(() {
                            scene.videoStartMs = v.round();
                            final room = scene.videoMs - scene.videoStartMs;
                            if (scene.durationMs > room) scene.durationMs = math.max(1000, room);
                          }),
                ),
                const Text(
                  'Drag the end of the clip on the timeline to shorten it.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ));
        },
      ),
    );
    _commit();
  }

  // ---- extra audio clips ----

  AudioClip? _selectedAudio() {
    final lesson = _lesson();
    final id = _selectedAudioId;
    if (lesson == null || id == null) return null;
    for (final clip in lesson.audioClips) {
      if (clip.id == id) return clip;
    }
    return null;
  }

  void _selectAudio(String id) {
    setState(() {
      _selectedAudioId = id;
      _soundSel = null;
      _selectedId = null;
      _sceneSelected = false;
    });
  }

  Future<void> _openSound() async {
    final choice = await showSoundChooser(context);
    if (choice == null || !mounted) return;
    if (choice == 'narration') {
      await _openAudio();
    } else {
      await _addAudioClip(choice == 'sfx' ? 'sfx' : 'music');
    }
  }

  String _clipName(String path) {
    var name = path.split('/').last;
    final dot = name.lastIndexOf('.');
    if (dot > 0) name = name.substring(0, dot);
    return name.length > 28 ? name.substring(0, 28) : name;
  }

  Future<void> _addAudioClip(String kind) async {
    final lesson = _lesson();
    final player = _player;
    if (lesson == null || player == null) return;
    _pause();
    String? path;
    try {
      path = await pickMedia(context, MediaKind.audio);
    } catch (_) {
      path = null;
    }
    if (path == null || !mounted) return;
    var sourceMs = 0;
    try {
      sourceMs = await KainuwaEncoder.audioDuration(path);
    } catch (_) {
      sourceMs = 0;
    }
    if (!mounted) return;
    if (sourceMs <= 0) {
      _snack('That audio file could not be read.');
      return;
    }
    final total = lesson.durationMs;
    final start = math.min(player.positionMs, math.max(0, total - 1000));
    final clip = AudioClip(
      id: newId(),
      path: path,
      label: _clipName(path),
      kind: kind,
      startMs: start,
      durationMs: math.min(sourceMs, math.max(1000, total - start)),
      sourceMs: sourceMs,
      volume: kind == 'music' ? 0.5 : 1.0,
    );
    lesson.audioClips.add(clip);
    _selectAudio(clip.id);
    _commit();
  }

  void _splitAudio() {
    final lesson = _lesson();
    final clip = _selectedAudio();
    final player = _player;
    if (lesson == null || clip == null || player == null) return;
    _pause();
    final local = player.positionMs - clip.startMs;
    if (local < 300 || clip.durationMs - local < 300) {
      _snack('Move the playhead inside the clip, at least 0.3 seconds from its edges, to split it.');
      return;
    }
    final second = clip.copy();
    second.startMs = clip.startMs + local;
    second.trimMs = clip.trimMs + (local * clip.speed).round();
    second.durationMs = clip.durationMs - local;
    second.fadeInMs = 0;
    clip.durationMs = local;
    clip.fadeOutMs = 0;
    lesson.audioClips.add(second);
    _selectAudio(second.id);
    _commit();
  }

  void _duplicateAudio() {
    final lesson = _lesson();
    final clip = _selectedAudio();
    if (lesson == null || clip == null) return;
    _pause();
    final copy = clip.copy();
    copy.startMs = math.min(clip.endMs, math.max(0, lesson.durationMs - 300));
    lesson.audioClips.add(copy);
    _selectAudio(copy.id);
    _commit();
  }

  void _deleteAudio() {
    final lesson = _lesson();
    final clip = _selectedAudio();
    if (lesson == null || clip == null) return;
    _pause();
    lesson.audioClips.remove(clip);
    setState(() => _selectedAudioId = null);
    _commit();
  }

  Future<void> _audioSettings() async {
    final clip = _selectedAudio();
    if (clip == null) return;
    _pause();
    final action = await showAudioClipSheet(
      context,
      clip: clip,
      onLive: () {
        if (mounted) setState(() {});
      },
    );
    if (!mounted) return;
    if (action == 'duplicate') {
      _duplicateAudio();
    } else if (action == 'delete') {
      _deleteAudio();
    } else {
      _commit();
    }
  }

  // ---- scenes and tracks ----

  void _addScene() {
    final lesson = _lesson();
    final current = _currentScene();
    if (lesson == null || current == null) return;
    _pause();
    final index = lesson.scenes.indexOf(current);
    lesson.scenes.insert(
      index + 1,
      Scene(
        id: newId(),
        durationMs: current.durationMs,
        bgType: current.bgType,
        bgValue: current.bgValue,
      ),
    );
    _player?.seek(sceneStartMs(lesson, index + 1));
    _selectedId = null;
    _sceneSelected = true;
    _commit();
  }

  void _setSceneDuration(int index, int ms) {
    final lesson = _lesson();
    if (lesson == null || index < 0 || index >= lesson.scenes.length) return;
    lesson.scenes[index].durationMs = math.max(500, ms);
    if (mounted) setState(() {});
  }

  Future<void> _sceneMenu(int index) async {
    final lesson = _lesson();
    if (lesson == null || index >= lesson.scenes.length) return;
    _pause();
    final action = await showEditorSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.content_copy),
              title: const Text('Duplicate slide'),
              onTap: () => Navigator.of(sheetContext).pop('duplicate'),
            ),
            if (index > 0)
              ListTile(
                leading: const Icon(Icons.arrow_back),
                title: const Text('Move earlier'),
                onTap: () => Navigator.of(sheetContext).pop('earlier'),
              ),
            if (index < lesson.scenes.length - 1)
              ListTile(
                leading: const Icon(Icons.arrow_forward),
                title: const Text('Move later'),
                onTap: () => Navigator.of(sheetContext).pop('later'),
              ),
            if (lesson.scenes.length > 1)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Delete slide'),
                onTap: () => Navigator.of(sheetContext).pop('delete'),
              ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    var target = index;
    switch (action) {
      case 'duplicate':
        lesson.scenes.insert(index + 1, lesson.scenes[index].duplicate());
        target = index + 1;
        break;
      case 'earlier':
        {
          final moved = lesson.scenes.removeAt(index);
          lesson.scenes.insert(index - 1, moved);
          target = index - 1;
        }
        break;
      case 'later':
        {
          final moved = lesson.scenes.removeAt(index);
          lesson.scenes.insert(index + 1, moved);
          target = index + 1;
        }
        break;
      case 'delete':
        lesson.scenes.removeAt(index);
        target = math.min(index, lesson.scenes.length - 1);
        break;
    }
    _player?.seek(sceneStartMs(lesson, target));
    _selectedId = null;
    _sceneSelected = action != 'delete';
    _commit();
  }

  Future<void> _addTrack() async {
    _pause();
    final choice = await showAddTimelineSheet(context);
    if (choice == null || !mounted) return;
    switch (choice) {
      case 'slide':
        _addScene();
        break;
      case 'duplicate':
        _duplicateScene();
        break;
      case 'text':
        await _addText();
        break;
      case 'subtitles':
        await _addSubtitles();
        break;
      case 'illustration':
        await _addIcon();
        break;
      case 'image':
        await _addImage();
        break;
      case 'shape':
        await _addShape();
        break;
      case 'audio':
        await _openSound();
        break;
      case 'voice':
        await _openAudio();
        break;
      case 'sfx':
        await _addAudioClip('sfx');
        break;
      case 'video':
        await _addVideo();
        break;
      case 'screen':
        _snack('Screen recording: record your screen with the phone recorder, then add the file with Add Video.');
        break;
      case 'drawing':
        await _addDrawing();
        break;
      case 'library':
        _snack('This option is planned for a later update.');
        break;
    }
  }

  void _toggleHidden(String id) {
    final lesson = _lesson();
    if (lesson == null) return;
    if (!lesson.hiddenTracks.remove(id)) lesson.hiddenTracks.add(id);
    _player?.muted = lesson.hiddenTracks.contains('audio');
    _commit();
  }

  Future<void> _trackMenu(String id) async {
    final index = _order.indexOf(id);
    if (index < 0) return;
    final hidden = _lesson()?.hiddenTracks.contains(id) ?? false;
    final isAudio = id == 'audio';
    final action = await showEditorSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Text(
                '${trackName(id)} track',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: KColors.ink),
              ),
            ),
            if (index > 0)
              ListTile(
                leading: const Icon(Icons.arrow_upward),
                title: const Text('Move up'),
                onTap: () => Navigator.of(sheetContext).pop('up'),
              ),
            if (index < _order.length - 1)
              ListTile(
                leading: const Icon(Icons.arrow_downward),
                title: const Text('Move down'),
                onTap: () => Navigator.of(sheetContext).pop('down'),
              ),
            if (id != 'video')
              ListTile(
                leading: Icon(hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                title: Text(
                  isAudio
                      ? (hidden ? 'Unmute the track' : 'Mute the track')
                      : (hidden ? 'Show the track' : 'Hide the track'),
                ),
                subtitle: const Text('A hidden or muted track is left out of the preview and of the exported video.'),
                onTap: () => Navigator.of(sheetContext).pop('hide'),
              ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    setState(() {
      if (action == 'up') {
        _order.removeAt(index);
        _order.insert(index - 1, id);
      } else if (action == 'down') {
        _order.removeAt(index);
        _order.insert(index + 1, id);
      }
    });
    if (action == 'hide') _toggleHidden(id);
  }

  // ---- screen parts ----

  String _clock(int ms) {
    final total = ms ~/ 1000;
    return '${(total ~/ 60).toString().padLeft(2, '0')}:${(total % 60).toString().padLeft(2, '0')}';
  }

  /// Turns the editor between portrait and landscape (same setting as in Settings).
  void _toggleOrientation() {
    final state = AppScope.read(context);
    final toLandscape = !state.settings.landscape;
    state.updateSettings(state.settings.copyWith(orientation: toLandscape ? 'landscape' : 'portrait'));
    AppState.editorLandscape = toLandscape;
    AppState.setOrientation(landscape: toLandscape);
  }

  Widget _headerIcon(double u, IconData icon, VoidCallback? onTap, {String? tooltip}) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints(minWidth: _s(u, 84, 34), minHeight: 40),
      icon: Icon(
        icon,
        size: _s(u, 46, 22),
        color: onTap == null ? const Color(0x80FFFFFF) : Colors.white,
      ),
    );
  }

  Widget _header(Lesson lesson, double u) {
    final top = MediaQuery.of(context).padding.top;
    final history = _history;
    return Container(
      color: KColors.deepPurple,
      padding: EdgeInsets.only(
        top: top,
        left: MediaQuery.of(context).padding.left,
        right: MediaQuery.of(context).padding.right,
      ),
      child: SizedBox(
        height: math.max(52.0, _s(u, 113)),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Back',
              onPressed: () => Navigator.of(context).maybePop(),
              icon: Icon(Icons.arrow_back, size: _s(u, 50, 24), color: Colors.white),
            ),
            Expanded(
              child: Text(
                lesson.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: _s(u, 46, 16),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            _headerIcon(u, Icons.undo, (history?.canUndo ?? false) ? _undo : null, tooltip: 'Undo'),
            _headerIcon(u, Icons.redo, (history?.canRedo ?? false) ? _redo : null, tooltip: 'Redo'),
            _headerIcon(u, Icons.storefront_outlined, _openStore, tooltip: 'Store'),
            _headerIcon(u, Icons.save_outlined, _save, tooltip: 'Save'),
            SizedBox(width: _s(u, 12, 4)),
            Material(
              color: KColors.editorExport,
              borderRadius: BorderRadius.circular(_s(u, 18, 10)),
              child: InkWell(
                borderRadius: BorderRadius.circular(_s(u, 18, 10)),
                onTap: _export,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: _s(u, 20, 10), vertical: _s(u, 14, 8)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.send_outlined, size: _s(u, 40, 18), color: Colors.white),
                      SizedBox(width: _s(u, 10, 4)),
                      Text(
                        'Export',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: _s(u, 32, 13),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(width: _s(u, 20, 8)),
          ],
        ),
      ),
    );
  }

  Widget _preview(Lesson lesson, Scene scene, SceneSpot spot, double u) {
    final player = _player!;
    final playing = player.playing;
    return Padding(
      padding: EdgeInsets.fromLTRB(_s(u, 28), _s(u, 25), _s(u, 28), 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_s(u, 28, 12)),
        child: AspectRatio(
          aspectRatio: lesson.aspect,
          child: _withTransition(lesson, spot, playing, ValueListenableBuilder<int?>(
            valueListenable: _demoMs,
            builder: (context, demoMs, _) => SceneCanvas(
            scene: viewScene(scene, lesson.hiddenTracks),
            selectedId: playing ? null : _selectedId,
            interactive: !playing,
            tapSelect: playing,
            previewMs: playing ? spot.localMs : null,
            ghostAtMs: playing ? null : spot.localMs,
            demoId: playing ? null : _demoId,
            demoMs: playing ? null : demoMs,
            onSelect: (id) {
              if (playing && id != null) _pause();
              _selectLayer(id);
            },
            onCommit: _commit,
            onDuplicate: (id) {
              final layer = _selectedLayer(scene);
              if (layer != null && layer.id == id) _duplicateLayer(scene, layer);
            },
            onDelete: (id) {
              final layer = _selectedLayer(scene);
              if (layer != null && layer.id == id) _deleteLayer(scene, layer);
            },
            ),
          )),
        ),
      ),
    );
  }

  /// Keeps the slide (and its native video player) alive when the transition wrapper comes and goes.
  final GlobalKey _stageKey = GlobalKey();

  /// While playing, the slide moves, zooms or fades as its transition says.
  /// The widget tree has the same shape at every moment, so the slide is never rebuilt and
  /// the video never restarts when a transition begins or ends.
  Widget _withTransition(Lesson lesson, SceneSpot spot, bool playing, Widget child) {
    final f = playing ? sceneTransitionFrame(lesson, spot.index, spot.localMs) : null;
    final stage = KeyedSubtree(key: _stageKey, child: child);
    return ClipRect(
      child: ColoredBox(
        color: f == null ? Colors.transparent : Color(transitionBgAt(lesson, spot.index, spot.localMs)),
        child: LayoutBuilder(builder: (context, c) {
          return Opacity(
            opacity: f == null ? 1.0 : f.alpha.clamp(0.0, 1.0).toDouble(),
            child: Transform(
              alignment: Alignment.center,
              transform: f == null
                  ? Matrix4.identity()
                  : (Matrix4.identity()
                    ..translate(f.dx * c.maxWidth, -f.dy * c.maxHeight)
                    ..scale(f.scale, f.scale, 1.0)),
              child: stage,
            ),
          );
        }),
      ),
    );
  }

  Future<void> _transitionSheet() => _transitionSheetAt(null);

  /// Opens the transition settings. [at] is the slide the transition leaves from; null uses the current slide.
  Future<void> _transitionSheetAt(int? at) async {
    final lesson = _lesson();
    if (lesson == null) return;
    final scene = (at != null && at >= 0 && at < lesson.scenes.length) ? lesson.scenes[at] : _currentScene();
    if (scene == null) return;
    final index = lesson.scenes.indexOf(scene);
    if (index < 0 || index >= lesson.scenes.length - 1) {
      _snack('A transition goes between two slides. Select a slide that has another one after it.');
      return;
    }
    _pause();
    await showEditorSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(builder: (context, setSheet) {
        void change(VoidCallback f) {
          setSheet(f);
          if (mounted) setState(() {});
        }

        const icons = {
          'left': Icons.arrow_back,
          'right': Icons.arrow_forward,
          'up': Icons.arrow_upward,
          'down': Icons.arrow_downward,
        };
        const names = {
          'left': 'Right to left',
          'right': 'Left to right',
          'up': 'Up',
          'down': 'Down',
        };
        return SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Transition into slide ${index + 2}',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final k in kTransitionKinds)
                        ChoiceChip(
                          label: Text(transitionLabel(k)),
                          selected: scene.transKind == k,
                          onSelected: (_) => change(() => scene.transKind = k),
                        ),
                    ],
                  ),
                  if (transitionUsesDirection(scene.transKind)) ...[
                    const SizedBox(height: 14),
                    const Text('Direction', style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final d in kTransitionDirs)
                          ChoiceChip(
                            avatar: Icon(icons[d], size: 16),
                            label: Text(names[d]!),
                            selected: scene.transDir == d,
                            onSelected: (_) => change(() => scene.transDir = d),
                          ),
                      ],
                    ),
                  ],
                  if (scene.transKind != 'none') ...[
                    const SizedBox(height: 14),
                    Text('Length: ${(scene.transMs / 1000).toStringAsFixed(1)} seconds',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    Slider(
                      value: scene.transMs.clamp(300, 2000).toDouble(),
                      min: 300,
                      max: 2000,
                      divisions: 17,
                      onChanged: (v) => change(() => scene.transMs = v.round()),
                    ),
                    const SizedBox(height: 6),
                    const Text('Background behind the slides', style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final c in const [0xFF000000, 0xFFFFFFFF, 0xFF41038B, 0xFF1A1431, 0xFFF6C101, 0xFF2563EB])
                          InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () => change(() => scene.transBg = c),
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Color(c),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: scene.transBg == c ? const Color(0xFF7351FF) : const Color(0x55FFFFFF),
                                  width: scene.transBg == c ? 4 : 1,
                                ),
                              ),
                            ),
                          ),
                        InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () async {
                            final picked = await pickColor(context, initial: scene.transBg, title: 'Transition background');
                            if (picked != null) change(() => scene.transBg = picked);
                          },
                          child: Container(
                            height: 40,
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: const Color(0xFF7351FF),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text('Other colour', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () {
                            Navigator.of(sheetContext).pop();
                            _previewTransition(lesson, index);
                          },
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Preview'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            for (var i = 0; i < lesson.scenes.length - 1; i++) {
                              final s = lesson.scenes[i];
                              s.transKind = scene.transKind;
                              s.transDir = scene.transDir;
                              s.transMs = scene.transMs;
                              s.transBg = scene.transBg;
                            }
                            if (mounted) setState(() {});
                            _snack('Applied to every slide.');
                          },
                          icon: const Icon(Icons.select_all),
                          label: const Text('Use for all'),
                        ),
                      ),
                    ]),
                  ],
                ],
              ),
            ),
          ),
        );
      }),
    );
    _commit();
  }

  void _previewTransition(Lesson lesson, int index) {
    final player = _player;
    if (player == null) return;
    final half = transitionHalfMs(lesson, index);
    final boundary = sceneStartMs(lesson, index + 1);
    player.seek(math.max(0, boundary - half - 600));
    player.play();
  }

  Widget _roundIcon(double size, IconData icon, VoidCallback onTap, {Color? color, Color? iconColor}) {
    return Material(
      color: color ?? Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, size: size * 0.62, color: iconColor ?? KColors.ink),
        ),
      ),
    );
  }

  Widget _transport(Lesson lesson, double u) {
    final player = _player!;
    final side = math.max(44.0, _s(u, 70));
    final playSize = math.max(48.0, _s(u, 84));
    return Padding(
      padding: EdgeInsets.fromLTRB(_s(u, 38), _s(u, 22), _s(u, 32), _s(u, 14)),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Material(
                color: KColors.editorLabel,
                borderRadius: BorderRadius.circular(_s(u, 18, 10)),
                child: InkWell(
                  borderRadius: BorderRadius.circular(_s(u, 18, 10)),
                  onTap: () => _fullscreen(lesson),
                  child: SizedBox(
                    width: side,
                    height: side,
                    child: Icon(Icons.crop_free, size: side * 0.62, color: KColors.ink),
                  ),
                ),
              ),
            ),
          ),
          _roundIcon(side, Icons.skip_previous, player.previous),
          SizedBox(width: _s(u, 20, 6)),
          Material(
            color: KColors.editorPlay,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: player.toggle,
              child: SizedBox(
                width: playSize,
                height: playSize,
                child: Icon(
                  player.playing ? Icons.pause : Icons.play_arrow_rounded,
                  size: playSize * 0.62,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          SizedBox(width: _s(u, 20, 6)),
          _roundIcon(side, Icons.skip_next, player.next),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '${_clock(player.positionMs)} / ${_clock(player.totalMs)}',
                  style: TextStyle(
                    fontSize: _s(u, 31, 12),
                    fontWeight: FontWeight.w600,
                    color: KColors.ink,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _toolItem(double u, IconData icon, String label, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(_s(u, 18, 8)),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: _s(u, 12, 6)),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: EdgeInsets.symmetric(horizontal: _s(u, 20, 9), vertical: _s(u, 10, 4)),
                decoration: BoxDecoration(
                  color: const Color(0x1AFFFFFF),
                  borderRadius: BorderRadius.circular(_s(u, 24, 12)),
                ),
                child: Icon(icon, size: _s(u, 40, 20), color: KColors.editorToolIcon),
              ),
              SizedBox(height: _s(u, 8, 3)),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    fontSize: _s(u, 25, 10),
                    color: KColors.ink,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bodyLayout({
    required double u,
    required Widget preview,
    required Widget transport,
    required Widget timeline,
  }) {
    final landscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final gap = SizedBox(height: _s(u, 16, 8));
    final scrollingTimeline = SingleChildScrollView(child: Column(children: [timeline, gap]));
    // Tapping empty space anywhere here lets go of the selected item or track.
    Widget clearOnTap(Widget child) => GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => _selectLayer(null),
          child: child,
        );
    if (landscape) {
      // Canvas with its controls on top, a compact timeline below. The canvas keeps a fixed share.
      return clearOnTap(LayoutBuilder(builder: (context, box) {
        var h1 = (box.maxHeight * 0.60).clamp(110.0, 280.0).toDouble();
        final padH = _s(u, 28);
        final aspect = Stage.aspect;
        var previewW = (h1 - _s(u, 25) - 2) * aspect + 2 * padH;
        final maxPW = math.max(120.0, box.maxWidth - 170);
        if (previewW > maxPW) {
          // Narrow middle (a side panel is open): shrink the canvas and give the room to the timeline.
          previewW = maxPW;
          h1 = math.min(box.maxHeight * 0.75, (previewW - 2 * padH) / aspect + _s(u, 25) + 2);
        }
        return Column(
          children: [
            SizedBox(
              height: h1,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(width: previewW, child: preview),
                  const SizedBox(width: 10),
                  SizedBox(width: 150, child: transport),
                ],
              ),
            ),
            Expanded(child: scrollingTimeline),
          ],
        );
      }));
    }
    // Preview and transport stay in place; only the timeline scrolls.
    // A tall video (TikTok) is kept to under half of the height so the timeline still fits.
    return clearOnTap(LayoutBuilder(builder: (context, box) {
      final wide = Stage.aspect >= 1.2;
      return Column(children: [
        wide
            ? preview
            : ConstrainedBox(constraints: BoxConstraints(maxHeight: box.maxHeight * 0.5), child: preview),
        transport,
        Expanded(child: scrollingTimeline),
      ]);
    }));
  }

  Widget _toolRail(double u, List<(IconData, String, VoidCallback)> tools) {
    final right = MediaQuery.of(context).padding.right;
    return Container(
      width: 74 + right,
      padding: EdgeInsets.only(right: right),
      decoration: const BoxDecoration(
        color: KColors.editorCard,
        border: Border(left: BorderSide(color: Color(0x1FFFFFFF))),
      ),
      child: tools.isEmpty
          ? null
          : SingleChildScrollView(
              child: Column(
                children: [
                  for (final t in tools)
                    InkWell(
                      onTap: t.$3,
                      child: SizedBox(
                        width: 74,
                        height: 58,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0x1AFFFFFF),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(t.$1, size: 20, color: KColors.editorToolIcon),
                            ),
                            const SizedBox(height: 2),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                t.$2,
                                maxLines: 1,
                                softWrap: false,
                                style: const TextStyle(fontSize: 10, color: KColors.ink, fontWeight: FontWeight.w500),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _transportSide(Lesson lesson, double u) {
    final player = _player!;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          '${_clock(player.positionMs)} / ${_clock(player.totalMs)}',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: KColors.ink),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _roundIcon(40, Icons.skip_previous, player.previous),
            const SizedBox(width: 6),
            Material(
              color: KColors.editorPlay,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: player.toggle,
                child: SizedBox(
                  width: 52,
                  height: 52,
                  child: Icon(player.playing ? Icons.pause : Icons.play_arrow_rounded, size: 32, color: Colors.white),
                ),
              ),
            ),
            const SizedBox(width: 6),
            _roundIcon(40, Icons.skip_next, player.next),
          ],
        ),
        const SizedBox(height: 8),
        Material(
          color: KColors.editorLabel,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => _fullscreen(lesson),
            child: const SizedBox(width: 40, height: 36, child: Icon(Icons.crop_free, size: 22, color: KColors.ink)),
          ),
        ),
      ],
    );
  }

  Widget _toolDivider(double u) {
    return Container(width: 1, height: _s(u, 70, 30), color: const Color(0xFF3D3266));
  }

  Widget _toolCard(double u) {
    final landscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final tools = <(IconData, String, VoidCallback)>[];
    final scene = _currentScene();
    final layer = _selectedLayer(scene);
    if (_selectedAudioId != null) {
      tools.addAll([
        (Icons.content_cut, 'Split', _split),
        (Icons.copy_all_outlined, 'Duplicate', _duplicateSelection),
        (Icons.volume_up_outlined, 'Volume', _volume),
        (Icons.speed, 'Speed', _audioSettings),
        (Icons.swap_horiz, 'Replace', _replaceMedia),
        (Icons.delete_outline, 'Delete', _deleteSelection),
      ]);
    } else if (_soundSel != null) {
      tools.addAll([
        (Icons.volume_up_outlined, 'Volume', _volume),
        (Icons.speed, 'Speed', _volume),
        (Icons.delete_outline, 'Delete', _deleteSelection),
      ]);
    } else if (layer != null) {
      tools.addAll([
        (Icons.content_cut, 'Split', _split),
        (Icons.copy_all_outlined, 'Duplicate', _duplicateSelection),
        (Icons.content_copy, 'Copy', _copyLayer),
        if (_clipLayer != null) (Icons.content_paste, 'Paste', _pasteLayer),
        (Icons.open_with, 'Pos & size', _positionSheet),
        (Icons.layers_outlined, 'Layer', _openLayers),
        (Icons.tune, 'Adjust', _adjust),
        (Icons.auto_awesome_outlined, 'Animate', _openAnimate),
        (Icons.speed, 'Speed', _speed),
        if (layer.type == 'image' || layer.type == 'shape') (Icons.swap_horiz, 'Replace', _replaceMedia),
        (Icons.delete_outline, 'Delete', _deleteSelection),
      ]);
    } else if (_sceneSelected && scene != null && scene.hasVideo) {
      tools.addAll([
        (Icons.content_cut, 'Split', _split),
        (Icons.copy_all_outlined, 'Duplicate', _duplicateSelection),
        (Icons.videocam_outlined, 'Video', _videoSettings),
        (Icons.swap_horiz, 'Replace', _replaceMedia),
        (Icons.compare_arrows, 'Transition', _transitionSheet),
        (Icons.delete_outline, 'Delete', _deleteSelection),
      ]);
    } else if (_sceneSelected) {
      tools.addAll([
        (Icons.content_cut, 'Split', _split),
        (Icons.copy_all_outlined, 'Duplicate', _duplicateSelection),
        (Icons.volume_up_outlined, 'Volume', _volume),
        (Icons.compare_arrows, 'Transition', _transitionSheet),
        (Icons.delete_outline, 'Delete', _deleteSelection),
      ]);
    } else if (_clipLayer != null && scene != null) {
      tools.add((Icons.content_paste, 'Paste', _pasteLayer));
    } else if (!landscape) {
      return const SizedBox(height: 8);
    }
    if (landscape) return _toolRail(u, tools);
    final children = <Widget>[];
    // With many tools the bar scrolls sideways so each button stays easy to hit.
    final scrolls = tools.length > 6;
    final itemW = (MediaQuery.of(context).size.width - 12) / 5.5;
    for (var i = 0; i < tools.length; i++) {
      if (i > 0) children.add(_toolDivider(u));
      final item = _toolItem(u, tools[i].$1, tools[i].$2, tools[i].$3);
      children.add(scrolls ? SizedBox(width: itemW, child: Row(children: [item])) : item);
    }
    return Container(
      margin: EdgeInsets.fromLTRB(_s(u, 14, 6), _s(u, 12, 4), _s(u, 14, 6), _s(u, 10, 4)),
      height: math.max(62.0, _s(u, 126)),
      decoration: BoxDecoration(
        color: KColors.editorCard,
        borderRadius: BorderRadius.circular(_s(u, 28, 14)),
        boxShadow: const [BoxShadow(color: Color(0x1A3B0F8C), blurRadius: 10, offset: Offset(0, 2))],
      ),
      child: scrolls
          ? SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: children))
          : Row(children: children),
    );
  }

  /// Opens the shape picker; every item is resized to fit the new shape.
  Future<void> _changeShape() async {
    final lesson = _lesson();
    if (lesson == null) return;
    final pick = await showShapePicker(context, lesson.aspectW, lesson.aspectH);
    if (pick == null || !mounted) return;
    if (pick.$1 == lesson.aspectW && pick.$2 == lesson.aspectH) return;
    applyVideoShape(lesson, pick.$1, pick.$2);
    Stage.use(lesson.aspectW, lesson.aspectH);
    _selectedId = null;
    _soundSel = null;
    _sceneSelected = false;
    await _commit();
  }

  Future<void> _navTap(int index) async {
    _pause();
    setState(() => _tab = index);
    switch (index) {
      case 0:
        await _setBackground();
        break;
      case 1:
        await _openAdd();
        break;
      case 2:
        await _openSound();
        break;
      case 3:
        await _setDuration();
        break;
      case 4:
        await _changeShape();
        break;
      case 5:
        _toggleOrientation();
        break;
    }
    if (mounted) setState(() => _tab = -1);
  }

  Widget _bottomNav(double u) {
    final bottom = MediaQuery.of(context).padding.bottom;
    final items = <(IconData, String)>[
      (Icons.wallpaper, 'Background'),
      (Icons.add_box_outlined, 'Add'),
      (Icons.mic_none, 'Sound'),
      (Icons.timer_outlined, 'Time'),
      (Icons.aspect_ratio, 'Shape'),
      (
        MediaQuery.of(context).orientation == Orientation.landscape
            ? Icons.stay_current_portrait
            : Icons.stay_current_landscape,
        'Rotate',
      ),
    ];
    return Container(
      padding: EdgeInsets.fromLTRB(_s(u, 12, 4), _s(u, 14, 4), _s(u, 12, 4), _s(u, 12, 4) + bottom),
      decoration: const BoxDecoration(
        color: KColors.editorCard,
        border: Border(top: BorderSide(color: Color(0x1FFFFFFF))),
      ),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _navTap(i),
                child: Container(
                  height: math.max(52.0, _s(u, 116)),
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: EdgeInsets.symmetric(horizontal: _s(u, 28, 14), vertical: _s(u, 8, 3)),
                        decoration: BoxDecoration(
                          color: _tab == i ? KColors.selected : Colors.transparent,
                          borderRadius: BorderRadius.circular(_s(u, 30, 14)),
                        ),
                        child: Icon(
                          items[i].$1,
                          size: _s(u, 46, 22),
                          color: _tab == i ? Colors.white : KColors.editorNavIcon,
                        ),
                      ),
                      SizedBox(height: _s(u, 6, 2)),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          items[i].$2,
                          maxLines: 1,
                          softWrap: false,
                          style: TextStyle(
                            fontSize: _s(u, 26, 10.5),
                            fontWeight: FontWeight.w600,
                            color: _tab == i ? Colors.white : KColors.editorNavIcon,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Landscape: the five bottom tabs become a vertical icon-only rail on the left.
  Widget _landscapeRail(double u, EdgeInsets pad) {
    final items = <(IconData, String)>[
      (Icons.wallpaper, 'Background'),
      (Icons.add_box_outlined, 'Add'),
      (Icons.mic_none, 'Sound'),
      (Icons.timer_outlined, 'Time'),
      (Icons.aspect_ratio, 'Shape'),
      (
        MediaQuery.of(context).orientation == Orientation.landscape
            ? Icons.stay_current_portrait
            : Icons.stay_current_landscape,
        'Rotate',
      ),
    ];
    return Container(
      width: 64 + pad.left,
      padding: EdgeInsets.only(left: pad.left, top: 6, bottom: 6),
      decoration: const BoxDecoration(
        color: KColors.editorCard,
        border: Border(right: BorderSide(color: Color(0x1FFFFFFF))),
      ),
      child: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < items.length; i++)
                Tooltip(
                  message: items[i].$2,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _navTap(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 48,
                      height: 48,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        color: _tab == i ? KColors.selected : Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        items[i].$1,
                        size: 24,
                        color: _tab == i ? Colors.white : KColors.editorNavIcon,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _frame(bool landscape, double u, List<Widget> kids) {
    if (!landscape) return Column(children: kids);
    final pad = MediaQuery.of(context).padding;
    EditorSide.top = pad.top + math.max(52.0, _s(u, 113));
    // Header across the whole top; below it: icon bar | canvas + timeline | tool bar.
    return Column(
      children: [
        kids[0],
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: pad.bottom),
            child: Row(children: [
              _landscapeRail(u, pad),
              kids[1],
              ValueListenableBuilder<double>(
                valueListenable: EditorSide.inset,
                builder: (context, v, _) => v > 0 ? SizedBox(width: v) : kids[2],
              ),
            ]),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final landscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final state = AppScope.of(context);
    final lesson = state.lessonById(widget.courseId, widget.lessonId);
    final player = _player;

    if (lesson == null || player == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('This video no longer exists.')),
      );
    }
    if (lesson.scenes.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(lesson.title)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    player.muted = lesson.hiddenTracks.contains('audio');
    final spot = sceneAt(lesson, player.positionMs);
    final scene = lesson.scenes[spot.index];
    final width = math.min(MediaQuery.of(context).size.width, 640.0);
    final u = math.min(width / 941.0, MediaQuery.of(context).size.height / 1700.0);

    return Scaffold(
      backgroundColor: KColors.editorPanel,
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).orientation == Orientation.landscape ? double.infinity : 640,
          ),
          child: _frame(landscape, u, [
              _header(lesson, u),
              Expanded(
                child: _bodyLayout(
                  u: u,
                  preview: _preview(lesson, scene, spot, u),
                  transport: landscape ? _transportSide(lesson, u) : _transport(lesson, u),
                  timeline: TimelinePanel(
                        maxUnit: landscape ? 0.36 : double.infinity,
                        lesson: lesson,
                        player: player,
                        order: _order,
                        hidden: lesson.hiddenTracks,
                        selectedLayerId: _selectedId,
                        selectedAudioId: _selectedAudioId,
                        sceneSelected: _sceneSelected,
                        selectedSound: _soundSel,
                        onSelectSound: _selectSound,
                        onSelectScene: _selectScene,
                        onSelectLayer: _selectLayerFromTimeline,
                        onSelectAudio: _selectAudio,
                        onSceneMenu: _sceneMenu,
                        onSceneDuration: _setSceneDuration,
                        onEditEnd: _commit,
                        onLayerTiming: () {
                          if (mounted) setState(() {});
                        },
                        onAudioChanged: () {
                          if (mounted) setState(() {});
                        },
                        onTrackMenu: _trackMenu,
                        onToggleHidden: _toggleHidden,
                        onAddTrack: _addTrack,
                        onAddScene: _addScene,
                        onTransition: (i) => _transitionSheetAt(i),
                      ),
                ),
              ),
              _toolCard(u),
              if (!landscape) _bottomNav(u),
            ]),
        ),
      ),
    );
  }
}

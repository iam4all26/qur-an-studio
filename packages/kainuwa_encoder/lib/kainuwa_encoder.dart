import 'dart:async';

import 'package:flutter/services.dart';

/// Dart side of the local Android plugin.
class KainuwaEncoder {
  KainuwaEncoder._();

  static const MethodChannel _channel = MethodChannel('kainuwa_encoder');
  static final StreamController<int> _progress =
      StreamController<int>.broadcast();
  static final StreamController<void> _playbackDone =
      StreamController<void>.broadcast();
  static final StreamController<String> _stage =
      StreamController<String>.broadcast();
  static final StreamController<int> _audioProgress =
      StreamController<int>.broadcast();
  static bool _ready = false;

  static void _init() {
    if (_ready) return;
    _ready = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'playbackDone') {
        _playbackDone.add(null);
      }
      if (call.method == 'stage') {
        final value = call.arguments;
        if (value is String) _stage.add(value);
      }
      if (call.method == 'audioProgress') {
        final value = call.arguments;
        if (value is int) _audioProgress.add(value);
      }
      if (call.method == 'progress') {
        final value = call.arguments;
        if (value is int) _progress.add(value);
      }
      return null;
    });
  }

  /// Private folder of the app where data is kept permanently (not cleared like the cache).
  static Future<String> filesDir() async {
    _init();
    final result = await _channel.invokeMethod<String>('filesDir');
    return result ?? '';
  }

  /// Fires when audio started with [playAudio] reaches its end.
  static Stream<void> get playbackDone {
    _init();
    return _playbackDone.stream;
  }

  /// Starts recording the microphone to [path] (an .m4a file). The first call asks
  /// for the microphone permission. [reduceNoise] switches on the phone's own
  /// noise suppression where the phone has it.
  static Future<void> startRecording({required String path, bool reduceNoise = true}) async {
    _init();
    await _channel.invokeMethod<bool>('startRecording', {'path': path, 'reduceNoise': reduceNoise});
  }

  /// Stops recording and returns the length of the recording in milliseconds.
  static Future<int> stopRecording() async {
    _init();
    return (await _channel.invokeMethod<int>('stopRecording')) ?? 0;
  }

  /// Loudness while recording, from 0 to 32767.
  static Future<int> recordingLevel() async {
    _init();
    return (await _channel.invokeMethod<int>('recordingLevel')) ?? 0;
  }

  /// Length of an audio file in milliseconds, or 0 if it cannot be read.
  static Future<int> audioDuration(String path) async {
    _init();
    return (await _channel.invokeMethod<int>('audioDuration', {'path': path})) ?? 0;
  }

  static Future<void> playAudio(String path, {double volume = 1.0, double speed = 1.0}) async {
    _init();
    await _channel.invokeMethod<bool>('playAudio', {'path': path, 'volume': volume, 'speed': speed});
  }

  static Future<void> stopAudio() async {
    _init();
    await _channel.invokeMethod<void>('stopAudio');
  }

  /// Plays an extra clip next to other sounds, starting [seekMs] into the file.
  static Future<void> playClip(String id, String path,
      {int seekMs = 0, double volume = 1.0, double speed = 1.0}) async {
    _init();
    await _channel.invokeMethod<bool>('playClip', {
      'id': id,
      'path': path,
      'seekMs': seekMs,
      'volume': volume,
      'speed': speed,
    });
  }

  static Future<void> setClipVolume(String id, double volume) async {
    _init();
    await _channel.invokeMethod<void>('setClipVolume', {'id': id, 'volume': volume});
  }

  static Future<void> stopClip(String id) async {
    _init();
    await _channel.invokeMethod<void>('stopClip', {'id': id});
  }

  static Future<void> stopClips() async {
    _init();
    await _channel.invokeMethod<void>('stopClips');
  }

  /// Loudness along an audio file: [bins] values from 0 to 1 (first 5 minutes).
  static Future<List<double>> audioPeaks(String path, {int bins = 160}) async {
    _init();
    final result = await _channel.invokeMethod<List<dynamic>>('audioPeaks', {'path': path, 'bins': bins});
    if (result == null) return const <double>[];
    return result.map((v) => (v as num).toDouble()).toList();
  }

  /// Whole-lesson export stage: 'audio' (preparing narration), then 'video'.
  static Stream<String> get stage {
    _init();
    return _stage.stream;
  }

  /// Progress of the narration preparation, 0 to 100.
  static Stream<int> get audioProgress {
    _init();
    return _audioProgress.stream;
  }

  /// Exports a whole lesson. Each entry of [scenes] has: image (path), durationMs,
  /// narration (path or null), volume, clean (bool) and overlays (a list of maps
  /// with path, cx, cy, anim, startMs, durMs).
  static Future<String> exportLesson({
    required List<Map<String, Object?>> scenes,
    required String workDir,
    required String outputPath,
    String? musicPath,
    double musicVolume = 0.3,
    double musicSpeed = 1.0,
    int musicFadeMs = 0,
    int width = 1280,
    int height = 720,
    int fps = 30,
    int bitrate = 0,
    List<Map<String, Object?>> clips = const [],
    List<Map<String, Object?>> transitions = const [],
  }) async {
    _init();
    final result = await _channel.invokeMethod<String>('exportLesson', {
      'clips': clips,
      'transitions': transitions,
      'scenes': scenes,
      'workDir': workDir,
      'output': outputPath,
      'music': musicPath,
      'musicVolume': musicVolume,
      'musicSpeed': musicSpeed,
      'musicFadeMs': musicFadeMs,
      'width': width,
      'height': height,
      'fps': fps,
      'bitrate': bitrate,
    });
    return result ?? outputPath;
  }

  /// Export progress from 0 to 100.
  static Stream<int> get progress {
    _init();
    return _progress.stream;
  }

  /// Opens the app page in the Play Store app. Returns play, market, web or failed.
  static Future<String> openStore(String package, String url) async {
    _init();
    return await _channel.invokeMethod<String>('openStore', {'package': package, 'url': url}) ?? 'failed';
  }

  /// Opens the system file picker for images. Returns a local copy path, or null if cancelled.
  static Future<String?> pickImage() {
    _init();
    return _channel.invokeMethod<String>('pick', {'mime': 'image/*'});
  }

  /// Opens the system file picker for video. Returns a local copy path, or null if cancelled.
  static Future<String?> pickVideo() {
    _init();
    return _channel.invokeMethod<String>('pick', {'mime': 'video/*'});
  }

  /// Opens a playing video on a native texture. Returns textureId, width, height.
  static Future<Map<String, int>?> videoOpen(String path, int ms) async {
    _init();
    final r = await _channel.invokeMapMethod<String, dynamic>('videoOpen', {'path': path, 'ms': ms});
    if (r == null) return null;
    return {
      'textureId': (r['textureId'] as num).toInt(),
      'width': (r['width'] as num).toInt(),
      'height': (r['height'] as num).toInt(),
    };
  }

  /// Current position of the open video in ms, or -1.
  static Future<int> videoPosition() async {
    _init();
    final r = await _channel.invokeMethod<int>('videoPosition');
    return r ?? -1;
  }

  /// Seeks to [ms] and starts playing (used once the picture is ready).
  static Future<void> videoPlay(int ms) {
    _init();
    return _channel.invokeMethod<void>('videoPlay', {'ms': ms});
  }

  /// Playback speed of the open video (1.0 normal), used to catch up with the sound.
  static Future<void> videoSpeed(double speed) {
    _init();
    return _channel.invokeMethod<void>('videoSpeed', {'speed': speed});
  }

  static Future<void> videoSeek(int ms) {
    _init();
    return _channel.invokeMethod<void>('videoSeek', {'ms': ms});
  }

  static Future<void> videoClose() {
    _init();
    return _channel.invokeMethod<void>('videoClose');
  }

  /// A small JPEG of the exact video frame at [ms], as bytes, or null.
  static Future<Uint8List?> videoFrameBytes(String path, int ms) {
    _init();
    return _channel.invokeMethod<Uint8List>('videoFrame', {
      'path': path,
      'ms': ms,
      'exact': true,
      'bytes': true,
    });
  }

  /// A small picture (JPEG path) of the video at the given time, or null.
  static Future<String?> videoFrame(String path, int ms) {
    _init();
    return _channel.invokeMethod<String>('videoFrame', {'path': path, 'ms': ms});
  }

  /// Opens the system file picker for audio. Returns a local copy path, or null if cancelled.
  static Future<String?> pickAudio() {
    _init();
    return _channel.invokeMethod<String>('pick', {'mime': 'audio/*'});
  }

  /// One scene: an image shown for the length of the narration, optional
  /// background music with volume and fades, and an optional animated text label.
  ///
  /// overlayAnimation is one of: fade, slide, pop, zoom.
  static Future<String> exportScene({
    required String imagePath,
    required String narrationPath,
    required String outputPath,
    String? musicPath,
    double narrationVolume = 1.0,
    double musicVolume = 0.3,
    int musicFadeInMs = 0,
    int musicFadeOutMs = 0,
    String? overlayText,
    int overlayStartMs = 1000,
    int overlayDurationMs = 800,
    String overlayAnimation = 'fade',
    int width = 1280,
    int height = 720,
  }) async {
    _init();
    final result = await _channel.invokeMethod<String>('exportScene', {
      'image': imagePath,
      'narration': narrationPath,
      'music': musicPath,
      'output': outputPath,
      'narrationVolume': narrationVolume,
      'musicVolume': musicVolume,
      'musicFadeInMs': musicFadeInMs,
      'musicFadeOutMs': musicFadeOutMs,
      'overlayText': overlayText,
      'overlayStartMs': overlayStartMs,
      'overlayDurationMs': overlayDurationMs,
      'overlayAnimation': overlayAnimation,
      'width': width,
      'height': height,
    });
    return result ?? outputPath;
  }

  static Future<void> cancelExport() async {
    _init();
    await _channel.invokeMethod<void>('cancel');
  }

  /// Opens the system file picker for any file. Returns a local copy path, or null if cancelled.
  static Future<String?> pickAnyFile() {
    _init();
    return _channel.invokeMethod<String>('pick', {'mime': '*/*'});
  }

  /// Lets the user choose where to save any file (for example a .kainuwa project).
  static Future<String> saveFile({required String path, required String name}) async {
    _init();
    final result = await _channel.invokeMethod<String>('saveFile', {'path': path, 'name': name});
    return result ?? name;
  }

  /// Saves a finished video. On Android 10 and newer it goes to Movies/Kainuwa Studio;
  /// on older versions a save dialog opens.
  /// Opens the last video saved to Movies in the phone's own video player.
  static Future<void> playLastVideo() async {
    _init();
    await _channel.invokeMethod<bool>('playLastVideo');
  }

  /// Address of the video saved last, or null.
  static Future<String?> lastVideoUri() async {
    _init();
    return _channel.invokeMethod<String>('lastVideoUri');
  }

  /// mode: 'play' (phone's player), 'open' (choose an app) or 'share'.
  /// Without a uri the last saved video is used.
  static Future<void> viewVideo({String? uri, String mode = 'play'}) async {
    _init();
    await _channel.invokeMethod<bool>('viewVideo', {'uri': uri, 'mode': mode});
  }

  static Future<String> saveToMovies({
    required String path,
    required String name,
  }) async {
    _init();
    final result = await _channel.invokeMethod<String>('saveToMovies', {
      'path': path,
      'name': name,
    });
    return result ?? name;
  }
}

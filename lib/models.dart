import 'dart:ui' show Color;

import 'data/asset_catalog.dart';
import 'stage_shape.dart';

int _idCounter = 0;

/// A new unique id.
String newId() {
  _idCounter++;
  return '${DateTime.now().microsecondsSinceEpoch}$_idCounter';
}

double _num(dynamic v, double fallback) => v is num ? v.toDouble() : fallback;
int _int(dynamic v, int fallback) => v is num ? v.toInt() : fallback;
String _str(dynamic v, String fallback) => v is String ? v : fallback;

/// One item placed on a scene: text, an icon or illustration, a photo, or a shape.
/// Position and size are fractions of the slide (0 to 1).
class Layer {
  Layer({
    required this.id,
    required this.type,
    this.cx = 0.5,
    this.cy = 0.5,
    this.w = 0.3,
    this.h = 0.3,
    this.rotation = 0,
    this.text = '',
    this.path = '',
    this.shape = 'rect',
    this.color = 0xFFFFFFFF,
    this.bold = true,
    this.animIn = 'none',
    this.animStartMs = 0,
    this.animDurationMs = 800,
    this.opacity = 1.0,
    this.startMs = 0,
    this.endMs = -1,
    this.animOut = 'none',
    this.animOutDurationMs = 500,
    this.italic = false,
    this.underline = false,
    this.strike = false,
    this.fontFamily = '',
    this.letterSpacing = 0,
    this.lineHeight = 1.15,
    this.align = 'center',
    this.bgBox = false,
    this.bgColor = 0xCC000000,
    this.textAnim = 'none',
    this.textAnimMs = 0,
    this.hand = '',
    this.handMs = 2500,
    this.animLoop = 'none',
    this.animLoopMs = 0,
    this.gradOn = false,
    this.gradC1 = 0xFFFFD54F,
    this.gradC2 = 0xFFFF6F00,
    this.gradAngle = 90,
    this.colorSpans = const [],
    this.animInDir = 'right',
    this.animOutDir = 'right',
    this.shadowOn = false,
    this.shadowColor = 0xB3000000,
    this.shadowBlur = 0.08,
    this.shadowX = 0.0,
    this.shadowY = 0.08,
    this.cropL = 0,
    this.cropT = 0,
    this.cropR = 0,
    this.cropB = 0,
    this.mask = 'none',
    this.srcAspect = 0,
  });

  final String id;

  /// text, asset, image or shape
  final String type;
  double cx;
  double cy;
  double w;
  double h;
  double rotation;
  String text;
  String path;

  /// rect, round or circle
  String shape;
  int color;
  bool bold;

  /// Entrance animation. animStartMs is a delay after the item appears.
  String animIn;
  int animStartMs;
  int animDurationMs;

  /// 0 (invisible) to 1 (solid).
  double opacity;

  /// The item is on screen from startMs until endMs (milliseconds into the
  /// slide). endMs -1 means until the end of the slide.
  int startMs;
  int endMs;

  /// Exit animation, played just before the item leaves.
  String animOut;
  int animOutDurationMs;

  // Text style
  bool italic;
  bool underline;
  bool strike;

  /// Empty means the default font.
  String fontFamily;

  /// In pixels of a 72 px text.
  double letterSpacing;
  double lineHeight;

  /// left, center, right or justify
  String align;
  bool bgBox;
  int bgColor;

  /// Text-only animation: none, letter, word, line, wordpop or wordslide.
  /// Starts at startMs + animStartMs. textAnimMs is the time between pieces (0 = default).
  String textAnim;
  int textAnimMs;

  /// A hand that draws this item (an id from hands.dart, empty for none) and the
  /// time it takes. Starts at startMs + animStartMs.
  String hand;
  int handMs;

  /// Overall animation that keeps going while the item is on screen (spin, shake, pulse...).
  /// animLoopMs is the time of one round, 0 for the default of that kind.
  String animLoop;
  int animLoopMs;

  /// Parts of the text in their own colour: [start, end, argb] over the text characters.
  List<List<int>> colorSpans;

  /// Direction a Slide entrance or exit moves: left, right, up or down.
  String animInDir;
  String animOutDir;

  /// Drop shadow. Blur and distances are fractions of the item's smaller side.
  bool shadowOn;
  int shadowColor;
  double shadowBlur;
  double shadowX;
  double shadowY;

  /// Gradient fill for text (two colours and an angle in degrees: 0 left to right, 90 top to bottom).
  bool gradOn;
  int gradC1;
  int gradC2;
  double gradAngle;

  /// Picture crop: the fraction cut from each side (0 to 0.8).
  double cropL;
  double cropT;
  double cropR;
  double cropB;

  /// Shape the picture is cut to: none, circle, round, diamond, star or heart.
  String mask;

  /// Width divided by height of the source picture. 0 until it is known.
  double srcAspect;

  Layer copy() => Layer.fromJson({...toJson(), 'id': newId()});

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'cx': cx,
        'cy': cy,
        'w': w,
        'h': h,
        'rotation': rotation,
        'text': text,
        'path': path,
        'shape': shape,
        'color': color,
        'bold': bold,
        'animIn': animIn,
        'animStartMs': animStartMs,
        'animDurationMs': animDurationMs,
        'opacity': opacity,
        'startMs': startMs,
        'endMs': endMs,
        'animOut': animOut,
        'animOutDurationMs': animOutDurationMs,
        'italic': italic,
        'underline': underline,
        'strike': strike,
        'fontFamily': fontFamily,
        'letterSpacing': letterSpacing,
        'lineHeight': lineHeight,
        'align': align,
        'bgBox': bgBox,
        'bgColor': bgColor,
        'textAnim': textAnim,
        'textAnimMs': textAnimMs,
        'hand': hand,
        'handMs': handMs,
        'animLoop': animLoop,
        'animLoopMs': animLoopMs,
        'gradOn': gradOn,
        'gradC1': gradC1,
        'gradC2': gradC2,
        'gradAngle': gradAngle,
        'colorSpans': colorSpans,
        'animInDir': animInDir,
        'animOutDir': animOutDir,
        'shadowOn': shadowOn,
        'shadowColor': shadowColor,
        'shadowBlur': shadowBlur,
        'shadowX': shadowX,
        'shadowY': shadowY,
        'cropL': cropL,
        'cropT': cropT,
        'cropR': cropR,
        'cropB': cropB,
        'mask': mask,
        'srcAspect': srcAspect,
      };

  factory Layer.fromJson(Map<String, dynamic> json) => Layer(
        id: _str(json['id'], newId()),
        type: _str(json['type'], 'shape'),
        cx: _num(json['cx'], 0.5),
        cy: _num(json['cy'], 0.5),
        w: _num(json['w'], 0.3),
        h: _num(json['h'], 0.3),
        rotation: _num(json['rotation'], 0),
        text: _str(json['text'], ''),
        path: _str(json['path'], ''),
        shape: _str(json['shape'], 'rect'),
        color: _int(json['color'], 0xFFFFFFFF),
        bold: json['bold'] is bool ? json['bold'] as bool : true,
        animIn: _str(json['animIn'], 'none'),
        animStartMs: _int(json['animStartMs'], 0),
        animDurationMs: _int(json['animDurationMs'], 800),
        opacity: _num(json['opacity'], 1.0).clamp(0.0, 1.0).toDouble(),
        startMs: _int(json['startMs'], 0),
        endMs: _int(json['endMs'], -1),
        animOut: _str(json['animOut'], 'none'),
        animOutDurationMs: _int(json['animOutDurationMs'], 500),
        italic: json['italic'] is bool ? json['italic'] as bool : false,
        underline: json['underline'] is bool ? json['underline'] as bool : false,
        strike: json['strike'] is bool ? json['strike'] as bool : false,
        fontFamily: _str(json['fontFamily'], ''),
        letterSpacing: _num(json['letterSpacing'], 0),
        lineHeight: _num(json['lineHeight'], 1.15),
        align: _str(json['align'], 'center'),
        bgBox: json['bgBox'] is bool ? json['bgBox'] as bool : false,
        bgColor: _int(json['bgColor'], 0xCC000000),
        textAnim: _str(json['textAnim'], 'none'),
        textAnimMs: _int(json['textAnimMs'], 0),
        hand: _str(json['hand'], ''),
        handMs: _int(json['handMs'], 2500),
        animLoop: _str(json['animLoop'], 'none'),
        animLoopMs: _int(json['animLoopMs'], 0),
        gradOn: json['gradOn'] is bool ? json['gradOn'] as bool : false,
        gradC1: _int(json['gradC1'], 0xFFFFD54F),
        gradC2: _int(json['gradC2'], 0xFFFF6F00),
        gradAngle: _num(json['gradAngle'], 90),
        colorSpans: json['colorSpans'] is List
            ? [
                for (final e in json['colorSpans'] as List)
                  if (e is List && e.length >= 3) [for (final x in e) x is num ? x.toInt() : 0]
              ]
            : const [],
        animInDir: _str(json['animInDir'], 'right'),
        animOutDir: _str(json['animOutDir'], 'right'),
        shadowOn: json['shadowOn'] is bool ? json['shadowOn'] as bool : false,
        shadowColor: _int(json['shadowColor'], 0xB3000000),
        shadowBlur: _num(json['shadowBlur'], 0.08),
        shadowX: _num(json['shadowX'], 0.0),
        shadowY: _num(json['shadowY'], 0.08),
        cropL: _num(json['cropL'], 0),
        cropT: _num(json['cropT'], 0),
        cropR: _num(json['cropR'], 0),
        cropB: _num(json['cropB'], 0),
        mask: _str(json['mask'], 'none'),
        srcAspect: _num(json['srcAspect'], 0),
      );
}

/// One slide of a lesson.
class Scene {
  Scene({
    required this.id,
    this.durationMs = 5000,
    this.bgType = 'color',
    this.bgValue = '4294967295',
    this.narrationPath = '',
    this.narrationMs = 0,
    this.narrationVolume = 1.0,
    this.narrationSpeed = 1.0,
    this.narrationClean = true,
    this.videoPath = '',
    this.videoStartMs = 0,
    this.videoMs = 0,
    this.videoVolume = 1.0,
    this.videoMuted = false,
    this.phoneFrame = false,
    this.videoFill = false,
    this.qSurah = 0,
    this.qAyah = 0,
    this.phoneScale = 0.9,
    this.phoneLight = false,
    this.transKind = 'none',
    this.transDir = 'left',
    this.transMs = 1000,
    this.transBg = 0xFF000000,
    List<Layer>? layers,
  }) : layers = layers ?? <Layer>[];

  final String id;
  int durationMs;

  /// color (bgValue is the ARGB number), asset (an asset path) or file (a photo path)
  String bgType;
  String bgValue;

  /// Voice recording or imported audio for this scene. Empty means none.
  String narrationPath;
  int narrationMs;
  double narrationVolume;

  /// Playback speed of the narration, 0.5 to 2. The narration is not pitched up or down.
  double narrationSpeed;

  /// How long the narration plays on the timeline, after the speed is applied.
  int get narrationLenMs => narrationMs <= 0 ? 0 : (narrationMs / narrationSpeed).round();

  /// Clean the voice (cut rumble, quiet the gaps) when the lesson is exported.
  bool narrationClean;
  final List<Layer> layers;

  /// A video clip that plays as this slide's background. Empty means none.
  String videoPath;
  int videoStartMs;
  int videoMs;
  double videoVolume;
  bool videoMuted;

  /// Shows a portrait video inside a phone shape on top of the slide background.
  bool phoneFrame;

  /// A video clip fills the whole frame (edges are cropped) instead of fitting inside it with bars.
  bool videoFill;

  /// The verse this slide shows (set by New Project; qAyah 0 is the Basmala slide). 0 = not a Qur'an slide.
  int qSurah;
  int qAyah;
  double phoneScale;
  bool phoneLight;

  /// Transition from this slide into the next one.
  String transKind;
  String transDir;
  int transMs;

  /// Colour shown behind the slides while the transition runs (ARGB).
  int transBg;

  bool get hasVideo => videoPath.isNotEmpty;

  bool get isDarkBackground {
    switch (bgType) {
      case 'color':
        return Color(int.tryParse(bgValue) ?? 0xFFFFFFFF).computeLuminance() < 0.45;
      case 'asset':
        return kDarkBackgrounds.contains(bgValue);
      default:
        return true;
    }
  }

  Scene duplicate() => Scene(
        id: newId(),
        durationMs: durationMs,
        bgType: bgType,
        bgValue: bgValue,
        narrationPath: narrationPath,
        narrationMs: narrationMs,
        narrationVolume: narrationVolume,
        narrationSpeed: narrationSpeed,
        narrationClean: narrationClean,
        videoPath: videoPath,
        videoStartMs: videoStartMs,
        videoMs: videoMs,
        videoVolume: videoVolume,
        videoMuted: videoMuted,
        phoneFrame: phoneFrame,
        videoFill: videoFill,
        qSurah: qSurah,
        qAyah: qAyah,
        phoneScale: phoneScale,
        phoneLight: phoneLight,
        transKind: transKind,
        transDir: transDir,
        transMs: transMs,
        transBg: transBg,
        layers: layers.map((l) => l.copy()).toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'durationMs': durationMs,
        'bgType': bgType,
        'bgValue': bgValue,
        'narrationPath': narrationPath,
        'narrationMs': narrationMs,
        'narrationVolume': narrationVolume,
        'narrationSpeed': narrationSpeed,
        'narrationClean': narrationClean,
        'videoPath': videoPath,
        'videoStartMs': videoStartMs,
        'videoMs': videoMs,
        'videoVolume': videoVolume,
        'videoMuted': videoMuted,
        'phoneFrame': phoneFrame,
        'videoFill': videoFill,
        'qSurah': qSurah,
        'qAyah': qAyah,
        'phoneScale': phoneScale,
        'phoneLight': phoneLight,
        'transKind': transKind,
        'transDir': transDir,
        'transMs': transMs,
        'transBg': transBg,
        'layers': layers.map((l) => l.toJson()).toList(),
      };

  factory Scene.fromJson(Map<String, dynamic> json) {
    final layers = <Layer>[];
    final raw = json['layers'];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map<String, dynamic>) layers.add(Layer.fromJson(item));
      }
    }
    return Scene(
      id: _str(json['id'], newId()),
      durationMs: _int(json['durationMs'], 5000),
      bgType: _str(json['bgType'], 'color'),
      bgValue: _str(json['bgValue'], '4294967295'),
      narrationPath: _str(json['narrationPath'], ''),
      narrationMs: _int(json['narrationMs'], 0),
      narrationVolume: _num(json['narrationVolume'], 1.0),
      narrationSpeed: _num(json['narrationSpeed'], 1.0).clamp(0.5, 2.0).toDouble(),
      narrationClean: json['narrationClean'] is bool ? json['narrationClean'] as bool : true,
      videoPath: _str(json['videoPath'], ''),
      videoStartMs: _int(json['videoStartMs'], 0),
      videoMs: _int(json['videoMs'], 0),
      videoVolume: _num(json['videoVolume'], 1.0),
      videoMuted: json['videoMuted'] is bool ? json['videoMuted'] as bool : false,
      phoneFrame: json['phoneFrame'] is bool ? json['phoneFrame'] as bool : false,
      videoFill: json['videoFill'] is bool ? json['videoFill'] as bool : false,
      qSurah: json['qSurah'] is num ? (json['qSurah'] as num).toInt() : 0,
      qAyah: json['qAyah'] is num ? (json['qAyah'] as num).toInt() : 0,
      phoneScale: _num(json['phoneScale'], 0.9),
      phoneLight: json['phoneLight'] is bool ? json['phoneLight'] as bool : false,
      transKind: _str(json['transKind'], 'none'),
      transDir: _str(json['transDir'], 'left'),
      transMs: _int(json['transMs'], 1000),
      transBg: _int(json['transBg'], 0xFF000000),
      layers: layers,
    );
  }
}

/// A sound placed on the lesson timeline: music, a sound effect or a voice clip.
class AudioClip {
  AudioClip({
    required this.id,
    required this.path,
    this.label = '',
    this.kind = 'music',
    this.startMs = 0,
    this.trimMs = 0,
    this.durationMs = 1000,
    this.sourceMs = 1000,
    this.volume = 1.0,
    this.speed = 1.0,
    this.fadeInMs = 0,
    this.fadeOutMs = 0,
  });

  final String id;
  String path;
  String label;

  /// music, sfx or voice
  String kind;

  /// Where the clip starts on the lesson timeline.
  int startMs;

  /// How far into the file the clip starts playing (trimmed from the start).
  int trimMs;

  /// How long the clip plays.
  int durationMs;

  /// Length of the whole file.
  int sourceMs;
  double volume;

  /// Playback speed, 0.5 to 2. [durationMs] is the time it takes on the timeline.
  double speed;
  int fadeInMs;
  int fadeOutMs;

  int get endMs => startMs + durationMs;

  AudioClip copy() => AudioClip.fromJson({...toJson(), 'id': newId()});

  Map<String, dynamic> toJson() => {
        'id': id,
        'path': path,
        'label': label,
        'kind': kind,
        'startMs': startMs,
        'trimMs': trimMs,
        'durationMs': durationMs,
        'sourceMs': sourceMs,
        'volume': volume,
        'speed': speed,
        'fadeInMs': fadeInMs,
        'fadeOutMs': fadeOutMs,
      };

  factory AudioClip.fromJson(Map<String, dynamic> json) => AudioClip(
        id: _str(json['id'], newId()),
        path: _str(json['path'], ''),
        label: _str(json['label'], ''),
        kind: _str(json['kind'], 'music'),
        startMs: _int(json['startMs'], 0),
        trimMs: _int(json['trimMs'], 0),
        durationMs: _int(json['durationMs'], 1000),
        sourceMs: _int(json['sourceMs'], 1000),
        volume: _num(json['volume'], 1.0).clamp(0.0, 1.0).toDouble(),
        speed: _num(json['speed'], 1.0).clamp(0.5, 2.0).toDouble(),
        fadeInMs: _int(json['fadeInMs'], 0),
        fadeOutMs: _int(json['fadeOutMs'], 0),
      );
}

class Lesson {
  Lesson({
    required this.id,
    required this.title,
    List<Scene>? scenes,
    this.musicPath = '',
    this.musicVolume = 0.3,
    this.musicSpeed = 1.0,
    this.musicFade = true,
    Set<String>? hiddenTracks,
    List<AudioClip>? audioClips,
    this.aspectW = 16,
    this.aspectH = 9,
    this.qTemplate = '',
    this.qLang = '',
    this.qReciter = '',
    this.qAlign = 'center',
    this.qFooter = true,
  })  : scenes = scenes ?? <Scene>[],
        hiddenTracks = hiddenTracks ?? <String>{},
        audioClips = audioClips ?? <AudioClip>[];

  final String id;
  String title;
  final List<Scene> scenes;

  /// The shape of the video, for example 16 and 9, or 9 and 16 for TikTok.
  int aspectW;
  int aspectH;

  /// How a New Project video was made, so the timeline can be rebuilt (change reciter).
  /// qTemplate is empty for videos made before this was stored.
  String qTemplate;

  /// Translation edition id (en_sahih, ha_gumi) or empty for none.
  String qLang;

  /// Reciter id used for the recitation (empty for older videos).
  String qReciter;
  String qAlign;
  bool qFooter;

  double get aspect => aspectW / aspectH;
  (double, double) get stageSize => stageSizeFor(aspectW, aspectH);

  /// Background music for the whole lesson. Empty means none.
  String musicPath;
  double musicVolume;
  double musicSpeed;
  bool musicFade;

  /// Tracks switched off with the eye icon (image, text, audio). They are left
  /// out of the preview and of the exported video.
  final Set<String> hiddenTracks;

  /// Extra sounds on the Audio track, besides the narration of each slide and
  /// the lesson music.
  final List<AudioClip> audioClips;

  int get durationMs => scenes.fold<int>(0, (sum, s) => sum + s.durationMs);

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'musicPath': musicPath,
        'musicVolume': musicVolume,
        'musicSpeed': musicSpeed,
        'musicFade': musicFade,
        'aspectW': aspectW,
        'aspectH': aspectH,
        'qTemplate': qTemplate,
        'qLang': qLang,
        'qReciter': qReciter,
        'qAlign': qAlign,
        'qFooter': qFooter,
        'hiddenTracks': hiddenTracks.toList(),
        'audioClips': audioClips.map((c) => c.toJson()).toList(),
        'scenes': scenes.map((s) => s.toJson()).toList(),
      };

  factory Lesson.fromJson(Map<String, dynamic> json) {
    final scenes = <Scene>[];
    final raw = json['scenes'];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map<String, dynamic>) scenes.add(Scene.fromJson(item));
      }
    }
    return Lesson(
      id: _str(json['id'], newId()),
      title: _str(json['title'], 'Untitled lesson'),
      musicPath: _str(json['musicPath'], ''),
      musicVolume: _num(json['musicVolume'], 0.3),
      musicSpeed: _num(json['musicSpeed'], 1.0).clamp(0.5, 2.0).toDouble(),
      musicFade: json['musicFade'] is bool ? json['musicFade'] as bool : true,
      aspectW: _int(json['aspectW'], 16).clamp(1, 99).toInt(),
      aspectH: _int(json['aspectH'], 9).clamp(1, 99).toInt(),
      qTemplate: _str(json['qTemplate'], ''),
      qLang: _str(json['qLang'], ''),
      qReciter: _str(json['qReciter'], ''),
      qAlign: _str(json['qAlign'], 'center'),
      qFooter: json['qFooter'] is bool ? json['qFooter'] as bool : true,
      hiddenTracks: json['hiddenTracks'] is List
          ? (json['hiddenTracks'] as List).whereType<String>().toSet()
          : <String>{},
      audioClips: [
        if (json['audioClips'] is List)
          for (final item in json['audioClips'] as List)
            if (item is Map<String, dynamic>) AudioClip.fromJson(item),
      ],
      scenes: scenes,
    );
  }
}

class Course {
  Course({
    required this.id,
    required this.title,
    this.description = '',
    required this.createdAt,
    this.isVideo = false,
    List<Lesson>? lessons,
  }) : lessons = lessons ?? <Lesson>[];

  final String id;
  String title;
  String description;
  final int createdAt;
  final List<Lesson> lessons;

  /// True for a single video made without a course: it opens straight in the editor.
  final bool isVideo;

  int get totalMs => lessons.fold<int>(0, (sum, lesson) => sum + lesson.durationMs);

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'createdAt': createdAt,
        'video': isVideo,
        'lessons': lessons.map((l) => l.toJson()).toList(),
      };

  factory Course.fromJson(Map<String, dynamic> json) {
    final lessons = <Lesson>[];
    final raw = json['lessons'];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map<String, dynamic>) lessons.add(Lesson.fromJson(item));
      }
    }
    return Course(
      id: _str(json['id'], newId()),
      title: _str(json['title'], 'Untitled course'),
      description: _str(json['description'], ''),
      createdAt: _int(json['createdAt'], 0),
      isVideo: json['video'] == true,
      lessons: lessons,
    );
  }
}

/// A mark laid over every exported video: text or a picture, in one corner.
class Watermark {
  const Watermark({
    this.on = false,
    this.kind = 'text',
    this.text = 'Quran Studio',
    this.image = '',
    this.corner = 'br',
    this.size = 0.2,
    this.opacity = 0.7,
  });

  final bool on;
  final String kind;
  final String text;
  final String image;
  final String corner;
  final double size;
  final double opacity;

  Watermark copyWith({
    bool? on,
    String? kind,
    String? text,
    String? image,
    String? corner,
    double? size,
    double? opacity,
  }) =>
      Watermark(
        on: on ?? this.on,
        kind: kind ?? this.kind,
        text: text ?? this.text,
        image: image ?? this.image,
        corner: corner ?? this.corner,
        size: size ?? this.size,
        opacity: opacity ?? this.opacity,
      );

  Map<String, dynamic> toJson() => {
        'on': on,
        'kind': kind,
        'text': text,
        'image': image,
        'corner': corner,
        'size': size,
        'opacity': opacity,
      };

  factory Watermark.fromJson(Map<String, dynamic> json) => Watermark(
        on: json['on'] is bool ? json['on'] as bool : false,
        kind: _str(json['kind'], 'text'),
        text: _str(json['text'], 'Quran Studio'),
        image: _str(json['image'], ''),
        corner: _str(json['corner'], 'br'),
        size: _num(json['size'], 0.2),
        opacity: _num(json['opacity'], 0.7),
      );
}

class AppSettings {
  const AppSettings({
    this.videoHeight = 720,
    this.frameRate = 30,
    this.orientation = 'portrait',
    this.wm = const Watermark(),
  });

  final Watermark wm;
  final int videoHeight;
  final int frameRate;

  /// portrait or landscape
  final String orientation;

  bool get landscape => orientation == 'landscape';

  int get videoWidth => videoHeight == 1080 ? 1920 : 1280;

  AppSettings copyWith({int? videoHeight, int? frameRate, String? orientation, Watermark? wm}) => AppSettings(
        wm: wm ?? this.wm,
        videoHeight: videoHeight ?? this.videoHeight,
        frameRate: frameRate ?? this.frameRate,
        orientation: orientation ?? this.orientation,
      );

  Map<String, dynamic> toJson() => {
        'videoHeight': videoHeight,
        'frameRate': frameRate,
        'orientation': orientation,
        'wm': wm.toJson(),
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        videoHeight: _int(json['videoHeight'], 720) == 1080 ? 1080 : 720,
        frameRate: _int(json['frameRate'], 30) == 24 ? 24 : 30,
        orientation: _str(json['orientation'], 'portrait') == 'landscape' ? 'landscape' : 'portrait',
        wm: json['wm'] is Map ? Watermark.fromJson(Map<String, dynamic>.from(json['wm'] as Map)) : const Watermark(),
      );
}

String formatClock(int ms) {
  final totalSeconds = (ms / 1000).round();
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}

String lessonCountText(int count) => '$count ${count == 1 ? 'Lesson' : 'Lessons'}';

String sceneCountText(int count) => '$count ${count == 1 ? 'scene' : 'scenes'}';

String minutesText(int ms) => '${(ms / 60000).round()} min';

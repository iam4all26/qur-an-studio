/// The shape (aspect ratio) of a video and the working size used inside the app.
///
/// The short side of the working stage is always 720, so text and shapes have the
/// same size in every format. A 16:9 video is 1280 x 720, a 9:16 video is 720 x 1280.
(double, double) stageSizeFor(int aw, int ah) {
  if (aw <= 0 || ah <= 0) return (1280, 720);
  if (aw >= ah) return ((720 * aw / ah).roundToDouble(), 720);
  return (720, (720 * ah / aw).roundToDouble());
}

/// Size in pixels of the exported video for a quality that names the short side.
(int, int) outputSizeFor(int aw, int ah, int shortSide) {
  int even(double v) => (v / 2).round() * 2;
  if (aw <= 0 || ah <= 0) return (even(shortSide * 16 / 9), shortSide);
  if (aw >= ah) return (even(shortSide * aw / ah), shortSide);
  return (shortSide, even(shortSide * ah / aw));
}

/// The working size of the video that is open in the editor. Set when the editor opens.
class Stage {
  Stage._();

  static double w = 1280;
  static double h = 720;

  static double get aspect => w / h;

  static void use(int aw, int ah) {
    final s = stageSizeFor(aw, ah);
    w = s.$1;
    h = s.$2;
  }

  static void reset() => use(16, 9);
}

class StagePreset {
  const StagePreset(this.title, this.hint, this.w, this.h);

  final String title;
  final String hint;
  final int w;
  final int h;

  String get ratio => '$w:$h';
}

const List<StagePreset> kStagePresets = [
  StagePreset('YouTube', 'Landscape, courses', 16, 9),
  StagePreset('TikTok', 'Reels, Shorts, Status', 9, 16),
  StagePreset('Instagram Post', 'Square, Facebook feed', 1, 1),
  StagePreset('Instagram Portrait', 'Facebook portrait feed', 4, 5),
];

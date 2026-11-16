
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Brand colors taken from the Qur'an Studio mockup.
class KColors {
  KColors._();

  static const Color deepPurple = Color(0xFF41038B);
  static const Color purple = Color(0xFF6D28D9);
  static const Color lavender = Color(0xFF2B2152);
  static const Color background = Color(0xFF0F0B1E);
  static const Color surface = Color(0xFF1A1431);
  static const Color accent = Color(0xFFB9A0FF);
  static const Color onGold = Color(0xFF1E1433);
  static const Color gold = Color(0xFFF6C101);
  static const Color ink = Color(0xFFEFEAFF);

  /// Background of anything that is selected (tabs, chips, options). Text on it is white.
  static const Color selected = Color(0xFF7351FF);

  // Lesson editor (multitrack timeline) colors, sampled from the mockup.
  static const Color editorPanel = Color(0xFF13102A);
  static const Color editorStrip = Color(0xFF241C48);
  static const Color editorLabel = Color(0xFF1C1638);
  static const Color editorCard = Color(0xFF1C1638);
  static const Color editorNav = Color(0xFF6B10D1);
  static const Color editorNavIcon = Colors.white;
  static const Color editorPlay = Color(0xFF7514DF);
  static const Color editorPlayhead = Color(0xFF8E1BDC);
  static const Color editorToolIcon = Colors.white;
  static const Color editorExport = Color(0xFFFCBE12);
  static const Color clipText = Color(0xFFFDC018);
  static const Color clipAudio = Color(0xFF03A845);
  static const Color clipMusic = Color(0xFF0B8F6A);
  static const Color clipVideo = Color(0xFF382BC8);
  static const Color clipPicture = Color(0xFF7C4DDB);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: KColors.purple,
    brightness: Brightness.dark,
  ).copyWith(
    primary: const Color(0xFF8B5CF6),
    onPrimary: Colors.white,
    secondary: KColors.gold,
    onSecondary: KColors.onGold,
    surface: KColors.surface,
    onSurface: KColors.ink,
    primaryContainer: KColors.lavender,
    onPrimaryContainer: KColors.accent,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: 'Inter',
    colorScheme: scheme,
    scaffoldBackgroundColor: KColors.background,
    canvasColor: KColors.surface,

    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: KColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),

    appBarTheme: const AppBarTheme(
      backgroundColor: KColors.background,
      surfaceTintColor: Colors.transparent,
      foregroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontFamily: 'Inter', fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white),
      systemOverlayStyle: SystemUiOverlayStyle.light,
    ),

    cardTheme: CardThemeData(
      color: const Color(0xFF1E1938),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: const Color(0xFF1E1938),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      titleTextStyle: const TextStyle(fontFamily: 'Inter', fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white),
    ),

    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF2E2653),
      contentTextStyle: const TextStyle(fontFamily: 'Inter', color: Colors.white, fontWeight: FontWeight.w500),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),

    popupMenuTheme: PopupMenuThemeData(
      color: const Color(0xFF2A2250),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF2A2150),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: KColors.selected, width: 1.5),
      ),
    ),

    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.all(Colors.white),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? KColors.selected : const Color(0xFF3A3262),
      ),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),

    dividerTheme: const DividerThemeData(color: Color(0x1FFFFFFF), space: 1, thickness: 1),

    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: KColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 68,
      indicatorShape: const StadiumBorder(),
      indicatorColor: KColors.selected,
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
          color: Colors.white,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    ),

    tabBarTheme: TabBarThemeData(
      labelColor: Colors.white,
      unselectedLabelColor: Colors.white,
      dividerColor: Colors.transparent,
      indicatorSize: TabBarIndicatorSize.tab,
      indicator: BoxDecoration(
        color: KColors.selected,
        borderRadius: BorderRadius.circular(20),
      ),
      labelStyle: const TextStyle(fontWeight: FontWeight.w700),
      unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
      overlayColor: WidgetStateProperty.all(Colors.transparent),
    ),

    sliderTheme: SliderThemeData(
      trackHeight: 4,
      activeTrackColor: KColors.selected,
      inactiveTrackColor: const Color(0x33FFFFFF),
      thumbColor: Colors.white,
      disabledThumbColor: const Color(0x55FFFFFF),
      overlayColor: const Color(0x227351FF),
      trackShape: const ModernSliderTrack(),
      tickMarkShape: SliderTickMarkShape.noTickMark,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8, elevation: 0, pressedElevation: 0),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
      valueIndicatorColor: KColors.selected,
      valueIndicatorTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
    ),

    chipTheme: ChipThemeData(
      showCheckmark: false,
      backgroundColor: KColors.lavender,
      selectedColor: KColors.selected,
      disabledColor: KColors.lavender,
      side: BorderSide.none,
      labelStyle: WidgetStateTextStyle.resolveWith(
        (s) => TextStyle(
          fontWeight: FontWeight.w600,
          color: s.contains(WidgetState.selected)
              ? Colors.white
              : KColors.ink,
        ),
      ),
    ),

    segmentedButtonTheme: SegmentedButtonThemeData(
      selectedIcon: SizedBox.shrink(),
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? KColors.selected
              : Colors.transparent,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? Colors.white
              : KColors.ink,
        ),
      ),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 14,
        ),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 14,
        ),
      ),
    ),
  );
}

/// A plain rounded slider track with no end dots and no tick marks.
class ModernSliderTrack extends SliderTrackShape with BaseSliderTrackShape {
  const ModernSliderTrack();

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isEnabled = false,
    bool isDiscrete = false,
    required TextDirection textDirection,
    double additionalActiveTrackHeight = 0,
  }) {
    final rect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    final radius = Radius.circular(rect.height / 2);
    final canvas = context.canvas;
    final inactive = Paint()..color = sliderTheme.inactiveTrackColor ?? const Color(0x33FFFFFF);
    final active = Paint()..color = sliderTheme.activeTrackColor ?? KColors.selected;
    canvas.drawRRect(RRect.fromRectAndRadius(rect, radius), inactive);
    final left = rect.left;
    final right = thumbCenter.dx.clamp(rect.left, rect.right).toDouble();
    if (right > left) {
      canvas.drawRRect(
        RRect.fromLTRBR(left, rect.top, right, rect.bottom, radius),
        active,
      );
    }
  }
}

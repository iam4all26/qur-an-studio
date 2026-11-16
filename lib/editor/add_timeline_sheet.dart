import 'package:flutter/material.dart';

import '../theme.dart';
import 'side_sheet.dart';

/// "Add to Timeline" sheet. Returns one of: slide, duplicate, image,
/// illustration, shape, text, subtitles, drawing, audio, video, screen, voice,
/// sfx, library. Returns null when closed.
Future<String?> showAddTimelineSheet(BuildContext context) {
  return showEditorSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x66000000),
    builder: (_) => const _AddTimelineSheet(),
  );
}

typedef _Item = (IconData, Color, String, String);

class _AddTimelineSheet extends StatelessWidget {
  const _AddTimelineSheet();

  static const _blue = Color(0xFF2F80ED);
  static const _orange = Color(0xFFF2994A);
  static const _pink = Color(0xFFE0407B);
  static const _green = Color(0xFF1FA463);
  static const _red = Color(0xFFE5532D);

  Widget _section(IconData icon, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: KColors.purple),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: KColors.ink)),
          const SizedBox(width: 10),
          const Expanded(child: Divider(height: 1, color: Color(0x1FFFFFFF))),
        ],
      ),
    );
  }

  /// Tiles in a grid. The number per row follows the width (2 to 5), and every label is shown in full.
  Widget _grid(BuildContext context, List<_Item> items) {
    return LayoutBuilder(builder: (context, box) {
      const gap = 8.0;
      final cols = ((box.maxWidth + gap) / (84 + gap)).floor().clamp(2, 5).toInt();
      final w = ((box.maxWidth - gap * (cols - 1)) / cols).floorToDouble();
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final it in items)
            SizedBox(
              width: w,
              height: 72,
              child: Material(
                color: Color.alphaBlend(it.$2.withAlpha(22), const Color(0xFF211A3F)),
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => Navigator.of(context).pop(it.$4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(it.$1, size: 24, color: it.$2),
                        const SizedBox(height: 5),
                        Text(
                          it.$3,
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: KColors.ink, height: 1.1),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final side = mq.orientation == Orientation.landscape;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: side ? double.infinity : mq.size.height * 0.9),
      child: Container(
        height: side ? double.infinity : null,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1A1333), Color(0xFF251C47)],
          ),
          borderRadius: side ? BorderRadius.zero : const BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!side)
                  Center(
                    child: Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(color: const Color(0xFF5A4C8E), borderRadius: BorderRadius.circular(3)),
                    ),
                  ),
                SizedBox(height: side ? 4 : 10),
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [KColors.purple, Color(0xFF8B3DF0)]),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.movie_creation_outlined, color: Colors.white, size: 26),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Add to Timeline',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: KColors.ink),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                _section(Icons.layers_outlined, 'Scene'),
                _grid(context, const [
                  (Icons.add_box_outlined, KColors.purple, 'New Slide', 'slide'),
                  (Icons.copy_all_outlined, KColors.purple, 'Duplicate Slide', 'duplicate'),
                ]),
                _section(Icons.image_outlined, 'Visual Elements'),
                _grid(context, const [
                  (Icons.image, _blue, 'Add Image', 'image'),
                  (Icons.emoji_objects, KColors.purple, 'Add Illustration', 'illustration'),
                  (Icons.crop_square, _orange, 'Add Shape', 'shape'),
                  (Icons.title, KColors.purple, 'Add Text', 'text'),
                  (Icons.closed_caption_outlined, _blue, 'Add Subtitles', 'subtitles'),
                  (Icons.draw_outlined, _pink, 'Add Drawing', 'drawing'),
                ]),
                _section(Icons.play_circle_outline, 'Media'),
                _grid(context, const [
                  (Icons.headphones, _green, 'Add Audio', 'audio'),
                  (Icons.videocam, _red, 'Add Video', 'video'),
                ]),
                _section(Icons.settings_outlined, 'More Options'),
                _grid(context, const [
                  (Icons.videocam_outlined, Colors.white, 'Screen Recording', 'screen'),
                  (Icons.mic_none, Colors.white, 'Record Voice', 'voice'),
                  (Icons.graphic_eq, Colors.white, 'Add Sound Effect', 'sfx'),
                  (Icons.folder_open, Colors.white, 'From Library', 'library'),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'dart:io';

import 'package:flutter/material.dart';

import '../export_history.dart';
import '../theme.dart';

/// The page shown right after an export finishes: the new video, quick actions
/// and the list of this project's exported videos.
class ExportSuccessView extends StatelessWidget {
  const ExportSuccessView({
    super.key,
    required this.latest,
    required this.history,
    required this.onPlay,
    required this.onShare,
    required this.onOpenWith,
    required this.onMore,
    required this.onRemove,
  });

  final ExportEntry latest;
  final List<ExportEntry> history;
  final void Function(ExportEntry) onPlay;
  final void Function(ExportEntry) onShare;
  final void Function(ExportEntry) onOpenWith;
  final VoidCallback onMore;
  final void Function(ExportEntry) onRemove;

  static const Color _soft = Color(0xFFB9B0D8);

  // Everything is drawn a little smaller on narrow screens, so it fits any phone.
  static double _k = 0.8;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    _k = (w / 400).clamp(0.72, 0.86).toDouble();
    final list = history.isEmpty ? [latest] : history;
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF2A1465), Color(0xFF160F33), KColors.background],
          stops: [0, 0.45, 1],
        ),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 20),
            children: [
              const SizedBox(height: 2),
              Center(
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0.5, end: 1),
                  duration: const Duration(milliseconds: 700),
                  curve: Curves.elasticOut,
                  builder: (context, v, child) => Transform.scale(scale: v, child: child),
                  child: const _CheckBadge(),
                ),
              ),
              SizedBox(height: 8 * _k),
              Text(
                'Project Successfully Exported',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 26 * _k, fontWeight: FontWeight.w800, color: Colors.white, height: 1.15),
              ),
              SizedBox(height: 6 * _k),
              Text(
                'Your video has been exported and saved\nin your device storage.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15 * _k, color: _soft, height: 1.3),
              ),
              SizedBox(height: 14 * _k),
              _latestCard(),
              SizedBox(height: 10 * _k),
              _actions(),
              SizedBox(height: 14 * _k),
              const Divider(height: 1, color: Color(0x26FFFFFF)),
              SizedBox(height: 12 * _k),
              Row(
                children: [
                  Icon(Icons.layers_outlined, color: Colors.white, size: 24 * _k),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('Project Exports',
                        style: TextStyle(fontSize: 20 * _k, fontWeight: FontWeight.w800, color: Colors.white)),
                  ),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 12 * _k, vertical: 5 * _k),
                    decoration: BoxDecoration(
                      color: const Color(0x4D6D28D9),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0x33FFFFFF)),
                    ),
                    child: Text(
                      '${list.length} ${list.length == 1 ? 'Video' : 'Videos'}',
                      style: TextStyle(fontSize: 13.5 * _k, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 10 * _k),
              for (final e in list) ...[
                _row(context, e),
                SizedBox(height: 8 * _k),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _latestCard() {
    return Container(
      padding: EdgeInsets.all(10 * _k),
      decoration: BoxDecoration(
        color: const Color(0x66231A48),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x40B9A0FF)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 12,
            child: SizedBox(
              height: 150 * _k,
              child: _Thumb(entry: latest, radius: 14, badgeSize: 12 * _k, maxHeight: 150 * _k),
            ),
          ),
          SizedBox(width: 12 * _k),
          Expanded(
            flex: 11,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  latest.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 16 * _k, fontWeight: FontWeight.w800, color: Colors.white, height: 1.2),
                ),
                SizedBox(height: 7 * _k),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 10 * _k, vertical: 4 * _k),
                      decoration: BoxDecoration(
                        color: const Color(0x666D28D9),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text('MP4',
                          style: TextStyle(fontSize: 14 * _k, fontWeight: FontWeight.w700, color: KColors.accent)),
                    ),
                    Text(latest.resolution, style: TextStyle(fontSize: 12.5 * _k, color: _soft)),
                  ],
                ),
                SizedBox(height: 7 * _k),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.insert_drive_file_outlined, size: 18 * _k, color: _soft),
                    const SizedBox(width: 6),
                    Text(latest.sizeText, style: TextStyle(fontSize: 14 * _k, color: _soft)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actions() {
    Widget tile(IconData icon, String label, VoidCallback tap, {bool primary = false, int flex = 11}) {
      return Expanded(
        flex: flex,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            child: Ink(
              height: 62 * _k / 0.8,
              decoration: BoxDecoration(
                gradient: primary
                    ? const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF8B6CFF), Color(0xFF6D28D9)],
                      )
                    : null,
                color: primary ? null : const Color(0x33231A48),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: primary ? const Color(0x80D6C8FF) : const Color(0x33B9A0FF)),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: tap,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 26 * _k, color: Colors.white),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(label,
                          style: TextStyle(fontSize: 13.5 * _k, fontWeight: FontWeight.w600, color: Colors.white)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        tile(Icons.play_arrow_rounded, 'Play', () => onPlay(latest), primary: true),
        tile(Icons.share_outlined, 'Share', () => onShare(latest)),
        tile(Icons.folder_open_outlined, 'Open File', () => onOpenWith(latest)),
        tile(Icons.more_vert, 'More', onMore, flex: 10),
      ],
    );
  }

  Widget _row(BuildContext context, ExportEntry e) {
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: const Color(0x4D231A48),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0x33B9A0FF)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => onPlay(e),
          child: Padding(
            padding: EdgeInsets.all(7 * _k),
            child: Row(
              children: [
                SizedBox(
                  width: 104 * _k / 0.8,
                  height: 62 * _k / 0.8,
                  child: _Thumb(entry: e, radius: 10, badgeSize: 10 * _k / 0.8, maxHeight: 62 * _k / 0.8),
                ),
                SizedBox(width: 10 * _k),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 14.5 * _k, fontWeight: FontWeight.w700, color: Colors.white)),
                      SizedBox(height: 5 * _k),
                      Wrap(
                        spacing: 10,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _meta(Icons.movie_outlined, 'MP4'),
                          _meta(null, e.shortResolution),
                          _meta(Icons.insert_drive_file_outlined, e.sizeText),
                        ],
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: Colors.white),
                  padding: EdgeInsets.zero,
                  color: KColors.editorCard,
                  onSelected: (v) {
                    if (v == 'play') onPlay(e);
                    if (v == 'share') onShare(e);
                    if (v == 'open') onOpenWith(e);
                    if (v == 'remove') onRemove(e);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'play', child: Text('Play')),
                    PopupMenuItem(value: 'share', child: Text('Share')),
                    PopupMenuItem(value: 'open', child: Text('Open with')),
                    PopupMenuItem(value: 'remove', child: Text('Remove from list')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _meta(IconData? icon, String text) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15 * _k, color: _soft),
            const SizedBox(width: 4),
          ],
          Text(text, style: TextStyle(fontSize: 12 * _k, color: _soft)),
        ],
      );
}

/// Picture of the video with the play icon and length in the corner.
class _Thumb extends StatelessWidget {
  const _Thumb({required this.entry, required this.radius, required this.badgeSize, required this.maxHeight});

  final ExportEntry entry;
  final double radius;
  final double badgeSize;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    // The picture has the shape of the video: wide, tall or square.
    final aspect = entry.width > 0 && entry.height > 0 ? entry.width / entry.height : 16 / 9;
    Widget picture;
    if (entry.thumbPath.isNotEmpty && File(entry.thumbPath).existsSync()) {
      picture = Image.file(File(entry.thumbPath), fit: BoxFit.cover, errorBuilder: (_, __, ___) => _fallback());
    } else {
      picture = _fallback();
    }
    return LayoutBuilder(builder: (context, box) {
      var w = box.maxWidth;
      var h = w / aspect;
      if (h > maxHeight) {
        h = maxHeight;
        w = h * aspect;
      }
      return Center(child: SizedBox(width: w, height: h, child: _frame(picture)));
    });
  }

  Widget _frame(Widget picture) {
    return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            picture,
            Positioned(
              right: 5,
              bottom: 5,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xB3000000),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.play_arrow_rounded, size: badgeSize + 2, color: Colors.white),
                    const SizedBox(width: 2),
                    Text(entry.clock,
                        style: TextStyle(fontSize: badgeSize, fontWeight: FontWeight.w700, color: Colors.white)),
                  ],
                ),
              ),
            ),
          ],
        ),
    );
  }

  Widget _fallback() => const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF41038B), Color(0xFF7351FF), KColors.gold],
          ),
        ),
        child: Center(child: Icon(Icons.movie_creation_outlined, color: Colors.white70, size: 30)),
      );
}

class _CheckBadge extends StatelessWidget {
  const _CheckBadge();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      height: 96,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(child: CustomPaint(painter: _ConfettiPainter())),
          Container(
            width: 84,
            height: 84,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF4ADE80), Color(0xFF16A34A)],
              ),
              boxShadow: [BoxShadow(color: Color(0x6622C55E), blurRadius: 22, spreadRadius: 1)],
            ),
            child: const Icon(Icons.check_rounded, size: 58, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  const _ConfettiPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    void bar(double dx, double dy, double angle, Color color, double w, double h) {
      canvas.save();
      canvas.translate(c.dx + dx, c.dy + dy);
      canvas.rotate(angle);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: w, height: h), Radius.circular(h / 2)),
        Paint()..color = color,
      );
      canvas.restore();
    }

    const gold = KColors.gold;
    const purple = Color(0xFF7351FF);
    const teal = Color(0xFF2DD4BF);
    const red = Color(0xFFFB5A5A);
    bar(-70, -32, -0.7, gold, 16, 6);
    bar(-92, -4, 0, red, 6, 6);
    bar(-74, 28, -0.8, teal, 11, 5);
    bar(70, -34, 0.7, gold, 16, 6);
    bar(86, -8, -0.15, purple, 20, 5);
    bar(74, 28, 0.8, teal, 11, 5);
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => false;
}

import 'dart:io';

import 'package:flutter/material.dart';

import 'media/media_library.dart';
import 'models.dart';
import 'theme.dart';

/// The watermark drawn over every slide of an exported video.
Widget watermarkOverlay(Watermark wm, double w, double h) {
  if (!wm.on) return const SizedBox.shrink();
  final hasImage = wm.kind == 'image' && wm.image.isNotEmpty && File(wm.image).existsSync();
  final hasText = wm.kind != 'image' && wm.text.trim().isNotEmpty;
  if (!hasImage && !hasText) return const SizedBox.shrink();
  final margin = w * 0.025;
  final child = Opacity(
    opacity: wm.opacity.clamp(0.1, 1.0).toDouble(),
    child: hasImage
        ? Image.file(File(wm.image), width: w * wm.size, fit: BoxFit.contain)
        : Text(
            wm.text,
            style: TextStyle(
              color: Colors.white,
              fontSize: w * wm.size * 0.2,
              fontWeight: FontWeight.w700,
              shadows: const [Shadow(color: Color(0xAA000000), blurRadius: 6)],
            ),
          ),
  );
  return Positioned.fill(
    child: Padding(
      padding: EdgeInsets.all(margin),
      child: Align(
        alignment: wm.corner == 'tl'
            ? Alignment.topLeft
            : wm.corner == 'tr'
                ? Alignment.topRight
                : wm.corner == 'bl'
                    ? Alignment.bottomLeft
                    : Alignment.bottomRight,
        child: child,
      ),
    ),
  );
}

/// The watermark settings card of the export screen.
class WatermarkCard extends StatefulWidget {
  const WatermarkCard({super.key, required this.wm, required this.onChanged, this.enabled = true});

  final Watermark wm;
  final ValueChanged<Watermark> onChanged;
  final bool enabled;

  @override
  State<WatermarkCard> createState() => _WatermarkCardState();
}

class _WatermarkCardState extends State<WatermarkCard> {
  late final TextEditingController _text = TextEditingController(text: widget.wm.text);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    String? path;
    try {
      path = await pickMedia(context, MediaKind.image);
    } catch (_) {
      path = null;
    }
    if (path == null || !mounted) return;
    widget.onChanged(widget.wm.copyWith(image: path, kind: 'image'));
  }

  @override
  Widget build(BuildContext context) {
    final wm = widget.wm;
    final on = widget.enabled;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.branding_watermark_outlined, color: KColors.purple),
            const SizedBox(width: 10),
            const Expanded(
              child: Text('Watermark', style: TextStyle(fontWeight: FontWeight.w700, color: KColors.accent)),
            ),
            Switch(
              value: wm.on,
              onChanged: on ? (v) => widget.onChanged(wm.copyWith(on: v)) : null,
            ),
          ],
        ),
        if (wm.on) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Text'),
                selected: wm.kind != 'image',
                onSelected: on ? (_) => widget.onChanged(wm.copyWith(kind: 'text')) : null,
              ),
              ChoiceChip(
                label: const Text('Image'),
                selected: wm.kind == 'image',
                onSelected: on ? (_) => widget.onChanged(wm.copyWith(kind: 'image')) : null,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (wm.kind == 'image')
            OutlinedButton.icon(
              onPressed: on ? _pickImage : null,
              icon: const Icon(Icons.image_outlined),
              label: Text(wm.image.isEmpty ? 'Choose an image' : 'Change image'),
            )
          else
            TextField(
              controller: _text,
              enabled: on,
              maxLength: 40,
              decoration: const InputDecoration(labelText: 'Watermark text', counterText: ''),
              onChanged: (v) => widget.onChanged(wm.copyWith(text: v)),
            ),
          const SizedBox(height: 8),
          const Text('Corner', style: TextStyle(fontSize: 12)),
          Wrap(
            spacing: 8,
            children: [
              for (final c in const [
                ('tl', 'Top left'),
                ('tr', 'Top right'),
                ('bl', 'Bottom left'),
                ('br', 'Bottom right'),
              ])
                ChoiceChip(
                  label: Text(c.$2),
                  selected: wm.corner == c.$1,
                  onSelected: on ? (_) => widget.onChanged(wm.copyWith(corner: c.$1)) : null,
                ),
            ],
          ),
          Text('Size: ${(wm.size * 100).round()} percent', style: const TextStyle(fontSize: 12)),
          Slider(
            value: wm.size.clamp(0.05, 0.4).toDouble(),
            min: 0.05,
            max: 0.4,
            onChanged: on ? (v) => widget.onChanged(wm.copyWith(size: v)) : null,
          ),
          Text('Strength: ${(wm.opacity * 100).round()} percent', style: const TextStyle(fontSize: 12)),
          Slider(
            value: wm.opacity.clamp(0.1, 1.0).toDouble(),
            min: 0.1,
            max: 1.0,
            onChanged: on ? (v) => widget.onChanged(wm.copyWith(opacity: v)) : null,
          ),
        ],
      ],
    );
  }
}

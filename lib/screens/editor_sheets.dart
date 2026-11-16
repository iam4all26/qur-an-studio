import '../editor/side_sheet.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:kainuwa_encoder/kainuwa_encoder.dart';

import '../animation_math.dart';
import '../text_reveal.dart';
import '../editor/hand_picker.dart';
import '../data/asset_catalog.dart';
import '../media/media_library.dart';
import '../models.dart';
import '../store/store_service.dart';
import '../theme.dart';
import '../widgets.dart';

class BackgroundChoice {
  const BackgroundChoice(this.type, this.value);

  /// color, asset or file
  final String type;
  final String value;
}

Future<BackgroundChoice?> showBackgroundSheet(BuildContext context) {
  return showEditorSheet<BackgroundChoice>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const FractionallySizedBox(heightFactor: 0.8, child: _BackgroundSheet()),
  );
}

class _BackgroundSheet extends StatelessWidget {
  const _BackgroundSheet();

  Future<void> _pickPhoto(BuildContext context) async {
    final navigator = Navigator.of(context);
    try {
      final path = await pickMedia(context, MediaKind.image);
      if (path != null) navigator.pop(BackgroundChoice('file', path));
    } catch (_) {
      // The picker was closed or failed. Stay on this sheet.
    }
  }

  @override
  Widget build(BuildContext context) {
    final backgrounds = allBackgrounds();
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Background', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              backgroundColor: const Color(0xFF2A2250),
              foregroundColor: Colors.white,
              shape: const StadiumBorder(),
            ),
            onPressed: () => _pickPhoto(context),
            icon: const Icon(Icons.photo_outlined),
            label: const Text('Choose a photo'),
          ),
          const SizedBox(height: 16),
          const Text('Colours', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFFB5ABD6))),
          const SizedBox(height: 8),
          ColorSwatches(
            onPick: (value) => Navigator.of(context).pop(BackgroundChoice('color', '$value')),
          ),
          const SizedBox(height: 16),
          const Text('Backgrounds', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFFB5ABD6))),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 16 / 11,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: backgrounds.length,
            itemBuilder: (context, index) {
              final item = backgrounds[index];
              return InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => Navigator.of(context).pop(BackgroundChoice(item.isFile ? 'file' : 'asset', item.path)),
                child: Column(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: SizedBox.expand(
                          child: catalogImage(item, fit: BoxFit.cover, cacheWidth: 400),
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Icons and illustrations. Returns the chosen item.
Future<CatalogItem?> showAssetSheet(BuildContext context) {
  return showEditorSheet<CatalogItem>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const FractionallySizedBox(heightFactor: 0.8, child: _AssetSheet()),
  );
}

class _AssetSheet extends StatelessWidget {
  const _AssetSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Add an icon', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ),
          ),
          Expanded(child: _PickGrid(items: allIcons(), columns: 4)),
        ],
      ),
    );
  }
}

class _PickGrid extends StatelessWidget {
  const _PickGrid({required this.items, required this.columns});

  final List<CatalogItem> items;
  final int columns;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('No icons yet. Islamic icons will come from the store.', textAlign: TextAlign.center),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        childAspectRatio: 0.9,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => Navigator.of(context).pop(item),
          child: Container(
            decoration: BoxDecoration(
              color: KColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: KColors.lavender),
            ),
            padding: const EdgeInsets.all(6),
            child: Column(
              children: [
                Expanded(child: catalogImage(item)),
                const SizedBox(height: 2),
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Returns rect, round or circle.
Future<String?> showShapeSheet(BuildContext context) {
  return showEditorSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: SingleChildScrollView(child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Add a shape', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _ShapeOption(
                  label: 'Rectangle',
                  child: Container(width: 64, height: 44, color: KColors.purple),
                  onTap: () => Navigator.of(sheetContext).pop('rect'),
                ),
                _ShapeOption(
                  label: 'Rounded',
                  child: Container(
                    width: 64,
                    height: 44,
                    decoration: BoxDecoration(
                      color: KColors.purple,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onTap: () => Navigator.of(sheetContext).pop('round'),
                ),
                _ShapeOption(
                  label: 'Circle',
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: const BoxDecoration(color: KColors.purple, shape: BoxShape.circle),
                  ),
                  onTap: () => Navigator.of(sheetContext).pop('circle'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (storeShapes().isNotEmpty) ...[
              const Text('More shapes', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final item in storeShapes())
                    InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => Navigator.of(sheetContext).pop('file:${item.path}'),
                      child: Container(
                        width: 72,
                        height: 72,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: KColors.lavender,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: catalogImage(item),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      )),
    ),
  );
}

class _ShapeOption extends StatelessWidget {
  const _ShapeOption({required this.label, required this.child, required this.onTap});

  final String label;
  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            SizedBox(height: 52, child: Center(child: child)),
            const SizedBox(height: 6),
            Text(label),
          ],
        ),
      ),
    );
  }
}

/// Returns the new length in milliseconds, or null. [minMs] is the shortest
/// allowed length (the narration cannot be cut off).
Future<int?> showDurationSheet(BuildContext context, int currentMs, {int minMs = 1000}) {
  return showEditorSheet<int>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _DurationSheet(currentMs: currentMs, minMs: minMs),
  );
}

class _DurationSheet extends StatefulWidget {
  const _DurationSheet({required this.currentMs, required this.minMs});

  final int currentMs;
  final int minMs;

  @override
  State<_DurationSheet> createState() => _DurationSheetState();
}

class _DurationSheetState extends State<_DurationSheet> {
  late final double _min = (widget.minMs / 1000).ceilToDouble().clamp(1.0, 59.0).toDouble();
  late double _seconds = (widget.currentMs / 1000).clamp(_min, 60.0).toDouble();

  @override
  Widget build(BuildContext context) {
    final steps = ((60 - _min) * 2).round().clamp(1, 1000).toInt();
    return SafeArea(
      child: SingleChildScrollView(child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Scene length', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text('${_seconds.toStringAsFixed(1)} seconds'),
            if (widget.minMs > 1000)
              Text(
                'Cannot be shorter than the narration (${(widget.minMs / 1000).toStringAsFixed(1)} s).',
                style: const TextStyle(fontSize: 12),
              ),
            Slider(
              value: _seconds,
              min: _min,
              max: 60,
              divisions: steps,
              onChanged: (v) => setState(() => _seconds = v),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop((_seconds * 1000).round()),
                  child: const Text('Apply'),
                ),
              ],
            ),
          ],
        ),
      )),
    );
  }
}

/// Returns text, icon, image or shape.
Future<String?> showAddSheet(BuildContext context) {
  return showEditorSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: SingleChildScrollView(child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Add to slide', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Row(
              children: [
                _AddOption(icon: Icons.title, label: 'Text', value: 'text', sheetContext: sheetContext),
                _AddOption(icon: Icons.star_outline, label: 'Icon', value: 'icon', sheetContext: sheetContext),
                _AddOption(icon: Icons.image_outlined, label: 'Image', value: 'image', sheetContext: sheetContext),
                _AddOption(icon: Icons.category_outlined, label: 'Shape', value: 'shape', sheetContext: sheetContext),
              ],
            ),
          ],
        ),
      )),
    ),
  );
}

class _AddOption extends StatelessWidget {
  const _AddOption({
    required this.icon,
    required this.label,
    required this.value,
    required this.sheetContext,
  });

  final IconData icon;
  final String label;
  final String value;
  final BuildContext sheetContext;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => Navigator.of(sheetContext).pop(value),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF2A2250),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              children: [
                Icon(icon, size: 28, color: Colors.white),
                const SizedBox(height: 8),
                Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Entrance animation settings for one item. Changes are applied to the item
/// straight away.
Future<void> showAnimateSheet(BuildContext context, Layer layer, int sceneMs) {
  return showEditorSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _AnimateSheet(layer: layer, sceneMs: sceneMs),
  );
}

class _AnimateSheet extends StatefulWidget {
  const _AnimateSheet({required this.layer, required this.sceneMs});

  final Layer layer;
  final int sceneMs;

  @override
  State<_AnimateSheet> createState() => _AnimateSheetState();
}

class _AnimateSheetState extends State<_AnimateSheet> {
  @override
  Widget build(BuildContext context) {
    final layer = widget.layer;
    final maxStart = (widget.sceneMs / 1000).clamp(1.0, 60.0).toDouble();
    final start = (layer.animStartMs / 1000).clamp(0.0, maxStart).toDouble();
    final length = (layer.animDurationMs / 1000).clamp(0.2, 3.0).toDouble();
    final animated = layer.animIn != 'none';

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Entrance animation', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text(
              'How this item appears on the slide. Press the play button on the slide to see it.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final kind in kAnimKinds)
                  ChoiceChip(
                    label: Text(animLabel(kind)),
                    selected: layer.animIn == kind,
                    onSelected: (_) => setState(() => layer.animIn = kind),
                  ),
              ],
            ),
            if (animated) ...[
              const SizedBox(height: 12),
              Text('Appears at ${start.toStringAsFixed(1)} s'),
              Slider(
                value: start,
                min: 0,
                max: maxStart,
                divisions: (maxStart * 10).round().clamp(1, 600).toInt(),
                onChanged: (v) => setState(() => layer.animStartMs = (v * 1000).round()),
              ),
              if (layer.animIn != 'appear') ...[
                Text('Animation length ${length.toStringAsFixed(1)} s'),
                Slider(
                  value: length,
                  min: 0.2,
                  max: 3.0,
                  divisions: 28,
                  onChanged: (v) => setState(() => layer.animDurationMs = (v * 1000).round()),
                ),
              ],
            ],
            const SizedBox(height: 16),
            const Text('Hand reveal', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            HandPicker(layer: layer, onChanged: () => setState(() {})),
            if (layer.type == 'text') ...[
              const SizedBox(height: 16),
              const Text('Text animation', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              const Text(
                'Shows the text piece by piece. It can be used together with the entrance above.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final kind in kTextAnimKinds)
                    ChoiceChip(
                      label: Text(textAnimLabel(kind)),
                      selected: layer.textAnim == kind,
                      onSelected: (_) => setState(() => layer.textAnim = kind),
                    ),
                ],
              ),
              if (layer.textAnim != 'none') ...[
                const SizedBox(height: 8),
                Text('Time per ${textUnitName(layer.textAnim)} ${(textUnitMs(layer) / 1000).toStringAsFixed(2)} s'),
                Slider(
                  value: (textUnitMs(layer) / 1000).clamp(0.02, 1.5).toDouble(),
                  min: 0.02,
                  max: 1.5,
                  divisions: 74,
                  onChanged: (v) => setState(() => layer.textAnimMs = (v * 1000).round()),
                ),
                if (!animated) ...[
                  Text('Starts ${start.toStringAsFixed(1)} s after it appears'),
                  Slider(
                    value: start,
                    min: 0,
                    max: maxStart,
                    divisions: (maxStart * 10).round().clamp(1, 600).toInt(),
                    onChanged: (v) => setState(() => layer.animStartMs = (v * 1000).round()),
                  ),
                ],
                Text(
                  'The whole text takes ${(textRevealTotalMs(layer) / 1000).toStringAsFixed(1)} s to appear.',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

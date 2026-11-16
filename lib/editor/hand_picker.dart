import 'package:flutter/material.dart';

import '../hands.dart';
import '../models.dart';
import '../theme.dart';

/// Choose a hand that draws the item onto the slide, and how long it takes.
class HandPicker extends StatelessWidget {
  const HandPicker({super.key, required this.layer, required this.onChanged});

  final Layer layer;

  /// Called after every change so the editor can save and redraw.
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    Widget tile(String id, Widget child, String name) {
      final on = layer.hand == id;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            layer.hand = id;
            onChanged();
          },
          child: Container(
            width: 72,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: on ? KColors.lavender : KColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: on ? KColors.purple : const Color(0xFF3D3266), width: on ? 2 : 1),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(height: 56, child: Center(child: child)),
                const SizedBox(height: 2),
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10)),
              ],
            ),
          ),
        ),
      );
    }

    final length = (layer.handMs / 1000).clamp(0.5, 10.0).toDouble();
    final start = (layer.animStartMs / 1000).clamp(0.0, 30.0).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 96,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              tile('', const Icon(Icons.block, size: 30), 'None'),
              for (final h in kHands)
                tile(h.id, Image.asset(h.asset, fit: BoxFit.contain, gaplessPlayback: true), h.name),
            ],
          ),
        ),
        if (layer.hand.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Drawing time ${length.toStringAsFixed(1)} s'),
          Slider(
            value: length,
            min: 0.5,
            max: 10,
            divisions: 19,
            onChanged: (v) {
              layer.handMs = (v * 1000).round();
              onChanged();
            },
          ),
          Text('Starts ${start.toStringAsFixed(1)} s after the item appears'),
          Slider(
            value: start,
            min: 0,
            max: 30,
            divisions: 60,
            onChanged: (v) {
              layer.animStartMs = (v * 1000).round();
              onChanged();
            },
          ),
          const Text(
            'The hand slides in, draws the item from left to right, then leaves. '
            'On text, this replaces the letter and word animations.',
            style: TextStyle(fontSize: 11),
          ),
        ],
      ],
    );
  }
}

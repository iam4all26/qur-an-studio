import 'side_sheet.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';
import '../widgets.dart';

/// Short name of a layer, shown on the timeline and in the layer list.
String layerLabel(Layer layer) {
  switch (layer.type) {
    case 'text':
      final first = layer.text.split('\n').first.trim();
      if (first.isEmpty) return 'Text';
      return first.length > 22 ? '${first.substring(0, 22)}...' : first;
    case 'asset':
      return 'Icon';
    case 'image':
      return 'Photo';
    case 'shape':
      switch (layer.shape) {
        case 'circle':
          return 'Circle';
        case 'round':
          return 'Rounded box';
        default:
          return 'Box';
      }
    default:
      return 'Item';
  }
}

IconData layerIcon(Layer layer) {
  switch (layer.type) {
    case 'text':
      return Icons.title;
    case 'asset':
      return Icons.emoji_objects_outlined;
    case 'image':
      return Icons.image_outlined;
    case 'shape':
      return layer.shape == 'circle' ? Icons.circle_outlined : Icons.crop_square;
    default:
      return Icons.layers_outlined;
  }
}

Widget _sheetTitle(String text) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: KColors.ink),
    ),
  );
}

// ---------------------------------------------------------------------------
// Volume: narration of this scene and music of the lesson
// ---------------------------------------------------------------------------

Future<void> showVolumeSheet(
  BuildContext context, {
  required Lesson lesson,
  required Scene scene,
  required VoidCallback onLive,
}) {
  return showEditorSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _VolumeSheet(lesson: lesson, scene: scene, onLive: onLive),
  );
}

class _VolumeSheet extends StatefulWidget {
  const _VolumeSheet({required this.lesson, required this.scene, required this.onLive});

  final Lesson lesson;
  final Scene scene;
  final VoidCallback onLive;

  @override
  State<_VolumeSheet> createState() => _VolumeSheetState();
}

class _VolumeSheetState extends State<_VolumeSheet> {
  @override
  Widget build(BuildContext context) {
    final scene = widget.scene;
    final lesson = widget.lesson;
    final hasNarration = scene.narrationPath.isNotEmpty;
    return SafeArea(
      child: SingleChildScrollView(child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sheetTitle('Volume and speed'),
            Text(
              hasNarration
                  ? 'Recitation of this scene ${(scene.narrationVolume * 100).round()}%'
                  : 'This scene has no recitation of its own. Select the audio on the timeline to change its volume.',
            ),
            Slider(
              value: scene.narrationVolume.clamp(0.0, 1.0).toDouble(),
              divisions: 20,
              onChanged: hasNarration
                  ? (v) {
                      setState(() => scene.narrationVolume = v);
                      widget.onLive();
                    }
                  : null,
            ),
            if (hasNarration) ...[
              Text('Recitation speed ${scene.narrationSpeed}x'.replaceAll('.0x', 'x')),
              const SizedBox(height: 6),
              SpeedChips(
                value: scene.narrationSpeed,
                onChanged: (v) {
                  setState(() => scene.narrationSpeed = v);
                  widget.onLive();
                },
              ),
            ],
          ],
        ),
      )),
    );
  }
}

// ---------------------------------------------------------------------------
// Speed: how fast the entrance animation of the selected item plays
// ---------------------------------------------------------------------------

const int _normalAnimMs = 800;
const List<double> _speeds = [0.5, 0.75, 1.0, 1.5, 2.0];

Future<void> showSpeedSheet(
  BuildContext context,
  Layer layer, {
  required VoidCallback onLive,
}) {
  return showEditorSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _SpeedSheet(layer: layer, onLive: onLive),
  );
}

class _SpeedSheet extends StatefulWidget {
  const _SpeedSheet({required this.layer, required this.onLive});

  final Layer layer;
  final VoidCallback onLive;

  @override
  State<_SpeedSheet> createState() => _SpeedSheetState();
}

class _SpeedSheetState extends State<_SpeedSheet> {
  bool _isSelected(double speed) {
    final ms = (_normalAnimMs / speed).round();
    return (widget.layer.animDurationMs - ms).abs() < 40;
  }

  @override
  Widget build(BuildContext context) {
    final layer = widget.layer;
    return SafeArea(
      child: SingleChildScrollView(child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sheetTitle('Speed'),
            Text(
              layer.animIn == 'none'
                  ? 'This item has no entrance animation yet. Use Animate to choose one, then set its speed here.'
                  : 'How fast the entrance animation of this item plays.',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final speed in _speeds)
                  ChoiceChip(
                    label: Text('${speed == speed.roundToDouble() ? speed.toInt() : speed}x'),
                    selected: _isSelected(speed),
                    onSelected: (_) {
                      setState(() => layer.animDurationMs = (_normalAnimMs / speed).round());
                      widget.onLive();
                    },
                  ),
              ],
            ),
          ],
        ),
      )),
    );
  }
}

// ---------------------------------------------------------------------------
// Layer: order of the items on the slide
// ---------------------------------------------------------------------------

Future<void> showLayersSheet(
  BuildContext context, {
  required Scene scene,
  required String? selectedId,
  required ValueChanged<String> onSelect,
  required VoidCallback onChanged,
}) {
  return showEditorSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _LayersSheet(
      scene: scene,
      selectedId: selectedId,
      onSelect: onSelect,
      onChanged: onChanged,
    ),
  );
}

class _LayersSheet extends StatefulWidget {
  const _LayersSheet({
    required this.scene,
    required this.selectedId,
    required this.onSelect,
    required this.onChanged,
  });

  final Scene scene;
  final String? selectedId;
  final ValueChanged<String> onSelect;
  final VoidCallback onChanged;

  @override
  State<_LayersSheet> createState() => _LayersSheetState();
}

class _LayersSheetState extends State<_LayersSheet> {
  void _reorder(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1;
    final shown = widget.scene.layers.reversed.toList();
    final item = shown.removeAt(oldIndex);
    shown.insert(newIndex, item);
    widget.scene.layers
      ..clear()
      ..addAll(shown.reversed);
    setState(() {});
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final shown = widget.scene.layers.reversed.toList();
    final maxHeight = MediaQuery.of(context).size.height * 0.6;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sheetTitle('Layers on this slide'),
            const Text('The top of the list is in front. Press and hold an item, then drag it to change the order. Tap an item to select it.'),
            const SizedBox(height: 8),
            if (shown.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('There is nothing on this slide yet. Use Add to put text, icons or pictures on it.'),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                child: ReorderableListView.builder(
                  shrinkWrap: true,
                  itemCount: shown.length,
                  onReorder: _reorder,
                  itemBuilder: (context, index) {
                    final layer = shown[index];
                    final selected = layer.id == widget.selectedId;
                    return ListTile(
                      key: ValueKey(layer.id),
                      contentPadding: EdgeInsets.zero,
                      selected: selected,
                      selectedTileColor: KColors.lavender,
                      leading: Icon(layerIcon(layer), color: KColors.purple),
                      title: Text(layerLabel(layer), maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () {
                        widget.onSelect(layer.id);
                        Navigator.of(context).pop();
                      },
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Extra audio clips on the Audio track
// ---------------------------------------------------------------------------

/// What to add from the Audio button. Returns narration, clip or reciter.
Future<String?> showSoundChooser(BuildContext context) {
  Widget option(BuildContext c, IconData icon, String title, String subtitle, String value) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.of(c).pop(value),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF2A2250),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: KColors.selected,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: Colors.white),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: const TextStyle(fontSize: 12.5, color: Color(0xFFB5ABD6))),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  return showEditorSheet<String>(
    context: context,
    builder: (c) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: _sheetTitle('Audio'),
          ),
          option(c, Icons.mic_none, 'Record or import recitation', 'Record your voice or import a recording for this scene', 'narration'),
          option(c, Icons.audio_file_outlined, 'Add an audio file', 'Add a recitation file at the playhead', 'clip'),
          option(c, Icons.record_voice_over_outlined, 'Change reciter', 'Replace the recitation of the whole video', 'reciter'),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// Settings of one audio clip. Returns duplicate or delete when one of those
/// buttons was tapped, otherwise null.
Future<String?> showAudioClipSheet(
  BuildContext context, {
  required AudioClip clip,
  required VoidCallback onLive,
}) {
  return showEditorSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _AudioClipSheet(clip: clip, onLive: onLive),
  );
}

class _AudioClipSheet extends StatefulWidget {
  const _AudioClipSheet({required this.clip, required this.onLive});

  final AudioClip clip;
  final VoidCallback onLive;

  @override
  State<_AudioClipSheet> createState() => _AudioClipSheetState();
}

class _AudioClipSheetState extends State<_AudioClipSheet> {
  String _seconds(int ms) => '${(ms / 1000).toStringAsFixed(1)} s';

  @override
  Widget build(BuildContext context) {
    final clip = widget.clip;
    final maxFade = math.max(0.0, math.min(5000.0, clip.durationMs / 2));
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sheetTitle(clip.label.isEmpty ? 'Audio clip' : clip.label),
            Text(
              'Starts at ${_seconds(clip.startMs)} and plays for ${_seconds(clip.durationMs)}. Drag it on the timeline to move it, and drag its ends to trim it.',
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            Text('Speed ${clip.speed}x'.replaceAll('.0x', 'x')),
            const SizedBox(height: 6),
            SpeedChips(
              value: clip.speed,
              onChanged: (s) {
                setState(() {
                  final old = clip.speed;
                  clip.speed = s;
                  var d = (clip.durationMs * old / s).round();
                  final room = ((clip.sourceMs - clip.trimMs) / s).floor();
                  if (room > 300) d = math.min(d, room);
                  clip.durationMs = math.max(300, d);
                });
                widget.onLive();
              },
            ),
            const SizedBox(height: 8),
            Text('Volume ${(clip.volume * 100).round()}%'),
            Slider(
              value: clip.volume.clamp(0.0, 1.0).toDouble(),
              divisions: 20,
              onChanged: (v) {
                setState(() => clip.volume = v);
                widget.onLive();
              },
            ),
            Text('Fade in ${_seconds(clip.fadeInMs)}'),
            Slider(
              value: math.min(clip.fadeInMs.toDouble(), maxFade),
              max: math.max(1.0, maxFade),
              divisions: maxFade >= 200 ? (maxFade / 100).round() : null,
              onChanged: maxFade < 100
                  ? null
                  : (v) {
                      setState(() => clip.fadeInMs = (v / 100).round() * 100);
                      widget.onLive();
                    },
            ),
            Text('Fade out ${_seconds(clip.fadeOutMs)}'),
            Slider(
              value: math.min(clip.fadeOutMs.toDouble(), maxFade),
              max: math.max(1.0, maxFade),
              divisions: maxFade >= 200 ? (maxFade / 100).round() : null,
              onChanged: maxFade < 100
                  ? null
                  : (v) {
                      setState(() => clip.fadeOutMs = (v / 100).round() * 100);
                      widget.onLive();
                    },
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.copy_all_outlined),
                    label: const Text('Duplicate'),
                    onPressed: () => Navigator.of(context).pop('duplicate'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete'),
                    onPressed: () => Navigator.of(context).pop('delete'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

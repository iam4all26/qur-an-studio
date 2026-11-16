import 'editor/side_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

/// Colors offered for text, shapes and backgrounds.
const List<int> kPalette = [
  0xFFFFFFFF,
  0xFF000000,
  0xFF1E1433,
  0xFF3B0F8C,
  0xFF6D28D9,
  0xFFEDE7FF,
  0xFFF6C101,
  0xFFF97316,
  0xFFDC2626,
  0xFFDB2777,
  0xFF16A34A,
  0xFF0D9488,
  0xFF2563EB,
  0xFF6B7280,
];

/// Asks for some text. Returns null when cancelled.
Future<String?> promptText(
  BuildContext context, {
  required String title,
  required String label,
  String initial = '',
  String confirm = 'Save',
  int maxLength = 60,
  bool multiline = false,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _PromptDialog(
      title: title,
      label: label,
      initial: initial,
      confirm: confirm,
      maxLength: maxLength,
      multiline: multiline,
    ),
  );
}

class _PromptDialog extends StatefulWidget {
  const _PromptDialog({
    required this.title,
    required this.label,
    required this.initial,
    required this.confirm,
    required this.maxLength,
    required this.multiline,
  });

  final String title;
  final String label;
  final String initial;
  final String confirm;
  final int maxLength;
  final bool multiline;

  @override
  State<_PromptDialog> createState() => _PromptDialogState();
}

class _PromptDialogState extends State<_PromptDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _done() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: widget.maxLength,
        minLines: 1,
        maxLines: widget.multiline ? 5 : 1,
        keyboardType: widget.multiline ? TextInputType.multiline : TextInputType.text,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(labelText: widget.label),
        onSubmitted: widget.multiline ? null : (_) => _done(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _done, child: Text(widget.confirm)),
      ],
    );
  }
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirm = 'Delete',
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(confirm),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// A row of color circles. Returns the chosen ARGB number, or null.
Future<int?> pickColor(
  BuildContext context, {
  String title = 'Text Color',
  int initial = 0xFF7351FF,
}) {
  return showEditorSheet<int>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ColorPanel(title: title, initial: initial),
  );
}

class _ColorPanel extends StatefulWidget {
  const _ColorPanel({required this.title, required this.initial});

  final String title;
  final int initial;

  @override
  State<_ColorPanel> createState() => _ColorPanelState();
}

class _ColorPanelState extends State<_ColorPanel> {
  late HSVColor _hsv;
  late double _alpha;
  int _tab = 0;
  late final TextEditingController _hex;

  @override
  void initState() {
    super.initState();
    final c = Color(widget.initial);
    _hsv = HSVColor.fromColor(c);
    _alpha = ((widget.initial >> 24) & 0xFF) / 255.0;
    _hex = TextEditingController();
    _syncHex();
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  int get _rgb => _hsv.toColor().value & 0xFFFFFF;
  int get _argb => ((_alpha * 255).round() << 24) | _rgb;
  int _channel(int shift) => (_rgb >> shift) & 0xFF;

  void _syncHex() {
    _hex.text = '#${_rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  void _setRgb(int rgb) {
    setState(() {
      _hsv = HSVColor.fromColor(Color(0xFF000000 | rgb));
      _syncHex();
    });
  }

  void _setHsv(HSVColor v) {
    setState(() {
      _hsv = v;
      _syncHex();
    });
  }

  void _setChannel(int shift, int value) {
    final v = value.clamp(0, 255);
    final rgb = (_rgb & ~(0xFF << shift)) | (v << shift);
    _setRgb(rgb);
  }

  static const List<int> _presets = [
    0xFFFFFFFF, 0xFF000000, 0xFFE5232B, 0xFFFB8C1B, 0xFFFFD21F, 0xFF22C55E, 0xFF2EE6E6,
    0xFF2563EB, 0xFF7351FF, 0xFFEC4EC0, 0xFFE0148C, 0xFFF9A8D4, 0xFF9CA3AF,
  ];

  Widget _swatch(int argb, {double size = 44}) {
    final selected = (argb & 0xFFFFFF) == _rgb;
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: () => _setRgb(argb & 0xFFFFFF),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Color(argb),
          shape: BoxShape.circle,
          border: Border.all(color: selected ? Colors.white : const Color(0x33FFFFFF), width: selected ? 3 : 1),
        ),
        child: selected
            ? Center(child: Container(width: 12, height: 12, decoration: const BoxDecoration(color: Color(0xFF7351FF), shape: BoxShape.circle)))
            : null,
      ),
    );
  }

  Widget _stepper(String label, int shift) {
    final value = _channel(shift);
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.only(left: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF241C48),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF3D3266)),
        ),
        child: Row(
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(width: 6),
            Expanded(child: Text('$value', style: const TextStyle(fontSize: 16))),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: () => _setChannel(shift, value + 1),
                  child: const Icon(Icons.keyboard_arrow_up, size: 22),
                ),
                InkWell(
                  onTap: () => _setChannel(shift, value - 1),
                  child: const Icon(Icons.keyboard_arrow_down, size: 22),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _picker() {
    return SizedBox(
      height: 150,
      child: Row(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                void update(Offset p) {
                  final hue = (p.dx / c.maxWidth).clamp(0.0, 1.0) * 360;
                  final value = 1 - (p.dy / c.maxHeight).clamp(0.0, 1.0);
                  _setHsv(HSVColor.fromAHSV(1, hue >= 360 ? 359.9 : hue, _hsv.saturation, value));
                }

                return GestureDetector(
                  onPanDown: (d) => update(d.localPosition),
                  onPanUpdate: (d) => update(d.localPosition),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            gradient: LinearGradient(
                              colors: [
                                for (var h = 0; h <= 360; h += 60)
                                  HSVColor.fromAHSV(1, h.toDouble(), _hsv.saturation, 1).toColor(),
                              ],
                            ),
                          ),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              gradient: const LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Color(0x00000000), Color(0xFF000000)],
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: (_hsv.hue / 360) * c.maxWidth - 11,
                        top: (1 - _hsv.value) * c.maxHeight - 11,
                        child: IgnorePointer(
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2.5),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 40,
            child: LayoutBuilder(
              builder: (context, c) {
                void update(Offset p) {
                  final sat = (p.dy / c.maxHeight).clamp(0.0, 1.0);
                  _setHsv(HSVColor.fromAHSV(1, _hsv.hue, sat, _hsv.value));
                }

                return GestureDetector(
                  onPanDown: (d) => update(d.localPosition),
                  onPanUpdate: (d) => update(d.localPosition),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.white, HSVColor.fromAHSV(1, _hsv.hue, 1, _hsv.value).toColor()],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 2,
                        right: 2,
                        top: _hsv.saturation * c.maxHeight - 9,
                        child: IgnorePointer(
                          child: Container(
                            height: 18,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(9),
                              border: Border.all(color: Colors.white, width: 2.5),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _solid() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Preset Colors', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final c in _presets) _swatch(c),
            InkWell(
              customBorder: const CircleBorder(),
              onTap: () => setState(() => _tab = 2),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0x66FFFFFF), width: 1.5),
                ),
                child: const Icon(Icons.add),
              ),
            ),
          ],
        ),
        const Divider(height: 28),
        const Text('Color Picker', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        _picker(),
        const SizedBox(height: 14),
        Row(
          children: [
            Container(
              width: 56,
              height: 44,
              decoration: BoxDecoration(
                color: Color(_argb),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
            const SizedBox(width: 12),
            const Text('HEX', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _hex,
                autocorrect: false,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.copy_outlined, size: 20),
                    onPressed: () => Clipboard.setData(ClipboardData(text: _hex.text)),
                  ),
                ),
                onChanged: (text) {
                  final clean = text.replaceAll('#', '').trim();
                  final n = clean.length == 6 ? int.tryParse(clean, radix: 16) : null;
                  if (n != null) {
                    setState(() => _hsv = HSVColor.fromColor(Color(0xFF000000 | n)));
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(children: [_stepper('R', 16), _stepper('G', 8), _stepper('B', 0)]),
        const SizedBox(height: 14),
        const Text('Opacity', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        Row(
          children: [
            Expanded(
              child: Slider(value: _alpha, onChanged: (v) => setState(() => _alpha = v)),
            ),
            Container(
              width: 70,
              padding: const EdgeInsets.symmetric(vertical: 10),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFF241C48),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF3D3266)),
              ),
              child: Text('${(_alpha * 100).round()}%', style: const TextStyle(fontSize: 16)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _palette() {
    final colors = <int>[];
    for (final lightness in const [0.82, 0.62, 0.42, 0.26]) {
      for (var h = 0; h < 360; h += 30) {
        colors.add(HSLColor.fromAHSL(1, h.toDouble(), 0.85, lightness).toColor().value);
      }
    }
    for (var g = 0; g < 12; g++) {
      final v = (g * 255 / 11).round();
      colors.add(0xFF000000 | (v << 16) | (v << 8) | v);
    }
    return Wrap(spacing: 10, runSpacing: 10, children: [for (final c in colors) _swatch(c, size: 38)]);
  }

  Widget _gradientNote() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 28),
      child: Text('Gradient colors are not available yet. Use Solid or Palette.'),
    );
  }

  Widget _tabButton(int index, IconData icon, String label) {
    final on = _tab == index;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => setState(() => _tab = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: on ? const Color(0xFF7351FF) : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height;
    return Container(
      constraints: BoxConstraints(maxHeight: height * 0.92),
      decoration: const BoxDecoration(
        color: Color(0xFF181230),
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 10, 8, 4),
              child: Row(
                children: [
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
                  Expanded(
                    child: Text(widget.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(backgroundColor: const Color(0xFF7351FF), foregroundColor: Colors.white),
                    onPressed: () => Navigator.of(context).pop(_argb),
                    child: const Text('Done', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0xFF241C48),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    _tabButton(0, Icons.circle, 'Solid'),
                    _tabButton(1, Icons.gradient, 'Gradient'),
                    _tabButton(2, Icons.palette_outlined, 'Palette'),
                  ],
                ),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
                child: _tab == 0 ? _solid() : (_tab == 1 ? _gradientNote() : _palette()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ColorSwatches extends StatelessWidget {
  const ColorSwatches({super.key, required this.onPick});

  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final value in kPalette)
          InkWell(
            customBorder: const CircleBorder(),
            onTap: () => onPick(value),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Color(value),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFB9A8E8), width: 1.5),
              ),
            ),
          ),
      ],
    );
  }
}

/// Simple purple cover used for courses until real covers exist.
class VideoCover extends StatelessWidget {
  const VideoCover({super.key, this.size = 56});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [KColors.deepPurple, KColors.purple],
        ),
      ),
      child: Icon(Icons.movie_creation_rounded, color: KColors.gold, size: size * 0.55),
    );
  }
}

/// A row of speed choices from 0.5x to 2x. Used for narration, music and audio clips.
class SpeedChips extends StatelessWidget {
  const SpeedChips({super.key, required this.value, required this.onChanged, this.enabled = true});

  final double value;
  final ValueChanged<double> onChanged;
  final bool enabled;

  static const List<double> speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final s in speeds)
          ChoiceChip(
            label: Text('${s}x'.replaceAll('.0x', 'x')),
            selected: (value - s).abs() < 0.01,
            onSelected: enabled ? (_) => onChanged(s) : null,
          ),
      ],
    );
  }
}

class CourseCover extends StatelessWidget {
  const CourseCover({super.key, this.size = 56});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [KColors.deepPurple, KColors.purple],
        ),
      ),
      child: Icon(Icons.school_rounded, color: KColors.gold, size: size * 0.55),
    );
  }
}

/// A small question mark that explains something when tapped. Used only where a label alone is not enough.
class HelpIcon extends StatelessWidget {
  const HelpIcon(this.text, {super.key, this.title});

  final String text;
  final String? title;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'What is this?',
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
      iconSize: 18,
      icon: const Icon(Icons.help_outline, color: Colors.white54),
      onPressed: () => showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: title == null ? null : Text(title!),
          content: Text(text),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('OK')),
          ],
        ),
      ),
    );
  }
}

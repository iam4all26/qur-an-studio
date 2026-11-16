import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../stage_shape.dart';
import '../theme.dart';

/// What the person chose when creating a video.
class VideoSetup {
  const VideoSetup(this.name, this.aspectW, this.aspectH);

  final String name;
  final int aspectW;
  final int aspectH;
}

Future<VideoSetup?> showVideoSetup(BuildContext context) {
  return showDialog<VideoSetup>(context: context, builder: (_) => const _VideoSetupDialog());
}

/// Lets the person pick a new shape for a video that already exists.
Future<(int, int)?> showShapePicker(BuildContext context, int currentW, int currentH) async {
  final setup = await showDialog<VideoSetup>(
    context: context,
    builder: (_) => _VideoSetupDialog(askName: false, initW: currentW, initH: currentH),
  );
  return setup == null ? null : (setup.aspectW, setup.aspectH);
}

class _VideoSetupDialog extends StatefulWidget {
  const _VideoSetupDialog({this.askName = true, this.initW = 16, this.initH = 9});

  final bool askName;
  final int initW;
  final int initH;

  @override
  State<_VideoSetupDialog> createState() => _VideoSetupDialogState();
}

class _VideoSetupDialogState extends State<_VideoSetupDialog> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _cw = TextEditingController(text: '3');
  final TextEditingController _ch = TextEditingController(text: '4');
  int _index = 0; // 0..3 presets, 4 custom

  @override
  void initState() {
    super.initState();
    final hit = kStagePresets.indexWhere((p) => p.w == widget.initW && p.h == widget.initH);
    if (hit >= 0) {
      _index = hit;
    } else if (widget.askName) {
      _index = 0;
    } else {
      _index = kStagePresets.length;
      _cw.text = '${widget.initW}';
      _ch.text = '${widget.initH}';
    }
  }

  bool get _custom => _index >= kStagePresets.length;

  (int, int) get _ratio {
    if (!_custom) return (kStagePresets[_index].w, kStagePresets[_index].h);
    var a = int.tryParse(_cw.text) ?? 1;
    var b = int.tryParse(_ch.text) ?? 1;
    a = a.clamp(1, 99).toInt();
    b = b.clamp(1, 99).toInt();
    // Keep it sensible: nothing wider than 3:1 or taller than 1:3.
    if (a > b * 3) a = b * 3;
    if (b > a * 3) b = a * 3;
    return (a, b);
  }

  @override
  void dispose() {
    _name.dispose();
    _cw.dispose();
    _ch.dispose();
    super.dispose();
  }

  void _create() {
    final r = _ratio;
    final text = _name.text.trim();
    Navigator.of(context).pop(VideoSetup(text.isEmpty ? 'Untitled video' : text, r.$1, r.$2));
  }

  /// A rectangle drawn in the exact shape of the format.
  Widget _shape(int a, int b, double box, {required bool on, Widget? child}) {
    final ratio = a / b;
    final w = ratio >= 1 ? box : box * ratio;
    final h = ratio >= 1 ? box / ratio : box;
    return SizedBox(
      width: box,
      height: box,
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: w,
          height: h,
          decoration: BoxDecoration(
            gradient: on
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF41038B), Color(0xFF7351FF)],
                  )
                : null,
            color: on ? null : const Color(0x14FFFFFF),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: on ? KColors.gold : const Color(0x66B9A0FF), width: on ? 2 : 1.4),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _card(int i, String title, String ratio, int a, int b, double width) {
    final on = _index == i;
    return GestureDetector(
      onTap: () => setState(() => _index = i),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: width,
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
        decoration: BoxDecoration(
          color: on ? const Color(0x337351FF) : const Color(0x0DFFFFFF),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: on ? KColors.gold : const Color(0x26FFFFFF), width: on ? 2 : 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _shape(a, b, 38, on: on),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(title,
                  maxLines: 1,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: on ? Colors.white : KColors.ink)),
            ),
            const SizedBox(height: 1),
            Text(ratio, style: TextStyle(fontSize: 11, color: on ? KColors.gold : Colors.white54)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = _ratio;
    final hint = _custom ? 'Your own shape' : kStagePresets[_index].hint;
    final title = _custom ? 'Custom' : kStagePresets[_index].title;
    final outSize = outputSizeFor(r.$1, r.$2, 1080);
    return Dialog(
      backgroundColor: KColors.editorCard,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.askName ? 'New video' : 'Video shape',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              if (widget.askName) ...[
                TextField(
                  controller: _name,
                  maxLength: 60,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Video name',
                    counterText: '',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              const Text('Choose the shape', style: TextStyle(fontWeight: FontWeight.w700, color: KColors.accent)),
              const SizedBox(height: 10),
              // Shows exactly how the video will look.
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0x1A000000),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    _shape(
                      r.$1,
                      r.$2,
                      132,
                      on: true,
                      child: Center(
                        child: Text('${r.$1}:${r.$2}',
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                    Text(hint, style: const TextStyle(fontSize: 12.5, color: Colors.white60)),
                    const SizedBox(height: 2),
                    Text('${outSize.$1} x ${outSize.$2} at 1080p',
                        style: const TextStyle(fontSize: 11.5, color: KColors.gold)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              LayoutBuilder(builder: (context, box) {
                const gap = 8.0;
                final cardW = (box.maxWidth - gap * 2) / 3;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (var i = 0; i < kStagePresets.length; i++)
                      _card(i, kStagePresets[i].title, kStagePresets[i].ratio, kStagePresets[i].w, kStagePresets[i].h, cardW),
                    _card(kStagePresets.length, 'Custom', 'Any shape', 3, 4, cardW),
                  ],
                );
              }),
              if (_custom) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('Ratio', style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(width: 12),
                    SizedBox(width: 64, child: _numberField(_cw)),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10),
                      child: Text(':', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                    ),
                    SizedBox(width: 64, child: _numberField(_ch)),
                  ],
                ),
              ],
              if (!widget.askName) ...[
                const SizedBox(height: 12),
                const Text('Everything on your slides is resized to fit the new shape. You can undo this.',
                    style: TextStyle(fontSize: 12.5, color: Colors.white60)),
              ],
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: KColors.gold, foregroundColor: KColors.onGold),
                    onPressed: _create,
                    child: Text(widget.askName ? 'Create' : 'Apply'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _numberField(TextEditingController c) => TextField(
        controller: c,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(2)],
        decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
        onChanged: (_) => setState(() {}),
      );
}

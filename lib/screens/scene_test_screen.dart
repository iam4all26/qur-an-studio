import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kainuwa_encoder/kainuwa_encoder.dart';

/// Step 2 proof screen: narration + music with volume and fades,
/// plus one animated text label on an image.
class SceneTestScreen extends StatefulWidget {
  const SceneTestScreen({super.key});

  @override
  State<SceneTestScreen> createState() => _SceneTestScreenState();
}

class _SceneTestScreenState extends State<SceneTestScreen> {
  String? _imagePath;
  String? _narrationPath;
  String? _musicPath;

  double _narrationVolume = 1.0;
  double _musicVolume = 0.3;
  bool _musicFades = true;

  bool _overlayOn = true;
  final TextEditingController _overlayText =
      TextEditingController(text: 'Welcome to Kainuwa Academy');
  String _animation = 'fade';
  double _overlayStart = 1.0;
  double _overlayLength = 0.8;

  bool _busy = false;
  int _progress = 0;
  bool _failed = false;
  String _status =
      'Choose an image and a narration file. Music and the text label are optional.';
  String? _unsavedVideo;

  @override
  void dispose() {
    _overlayText.dispose();
    super.dispose();
  }

  String _shortName(String path) {
    final name = path.split('/').last;
    return name.replaceFirst(RegExp(r'^\d+_'), '');
  }

  void _setMessage(String message, {bool failed = false}) {
    if (!mounted) return;
    setState(() {
      _status = message;
      _failed = failed;
    });
  }

  Future<void> _pick(Future<String?> Function() picker, void Function(String) assign, String what) async {
    try {
      final path = await picker();
      if (path != null && mounted) {
        setState(() => assign(path));
      }
    } on PlatformException catch (e) {
      _setMessage('Could not choose the $what: ${e.message}', failed: true);
    }
  }

  Future<void> _export() async {
    final image = _imagePath;
    final narration = _narrationPath;
    if (image == null || narration == null || _busy) return;

    setState(() {
      _busy = true;
      _progress = 0;
      _failed = false;
      _unsavedVideo = null;
      _status = 'Exporting. Keep this screen open.';
    });

    final stamp = DateTime.now().millisecondsSinceEpoch;
    final output = '${Directory.systemTemp.path}/kainuwa_$stamp.mp4';
    final sub = KainuwaEncoder.progress.listen((value) {
      if (mounted) setState(() => _progress = value);
    });

    final label = _overlayText.text.trim();
    try {
      await KainuwaEncoder.exportScene(
        imagePath: image,
        narrationPath: narration,
        outputPath: output,
        musicPath: _musicPath,
        narrationVolume: _narrationVolume,
        musicVolume: _musicVolume,
        musicFadeInMs: _musicFades ? 2000 : 0,
        musicFadeOutMs: _musicFades ? 2000 : 0,
        overlayText: (_overlayOn && label.isNotEmpty) ? label : null,
        overlayStartMs: (_overlayStart * 1000).round(),
        overlayDurationMs: (_overlayLength * 1000).round(),
        overlayAnimation: _animation,
      );
      await _save(output);
    } on PlatformException catch (e) {
      _setMessage('Export stopped: ${e.message}', failed: true);
    } finally {
      await sub.cancel();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save(String output) async {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    try {
      final saved = await KainuwaEncoder.saveToMovies(
        path: output,
        name: 'Kainuwa_Scene_$stamp.mp4',
      );
      if (mounted) setState(() => _unsavedVideo = null);
      _setMessage(
        'Done. The video was saved to $saved. Open it to check the sound levels, the fades and the animation.',
      );
      try {
        await File(output).delete();
      } catch (_) {}
    } on PlatformException catch (e) {
      if (mounted) setState(() => _unsavedVideo = output);
      _setMessage(
        'The video was exported but not saved yet (${e.message}). Tap Save video to try again.',
        failed: true,
      );
    }
  }

  Future<void> _cancel() async {
    try {
      await KainuwaEncoder.cancelExport();
    } on PlatformException catch (_) {}
  }

  Widget _fileRow({
    required String label,
    required String? path,
    required VoidCallback onChoose,
    VoidCallback? onClear,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            path == null ? '$label: none chosen' : '$label: ${_shortName(path)}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (onClear != null && path != null)
          TextButton(onPressed: _busy ? null : onClear, child: const Text('Clear')),
        OutlinedButton(
          onPressed: _busy ? null : onChoose,
          child: const Text('Choose'),
        ),
      ],
    );
  }

  Widget _slider({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String Function(double) format,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label: ${format(value)}'),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          onChanged: _busy ? null : onChanged,
        ),
      ],
    );
  }

  Widget _card(List<Widget> children) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final image = _imagePath;
    final ready = image != null && _narrationPath != null && !_busy;
    String pct(double v) => '${(v * 100).round()}%';
    String secs(double v) => '${v.toStringAsFixed(1)} s';

    return Scaffold(
      appBar: AppBar(title: const Text('Export test')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Step 2: sound and animation test',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          const Text(
            'Tests two sounds at once with separate volumes and fades, and one animated text label.',
          ),
          const SizedBox(height: 12),
          _card([
            _fileRow(
              label: 'Image',
              path: image,
              onChoose: () => _pick(KainuwaEncoder.pickImage, (p) => _imagePath = p, 'image'),
            ),
            if (image != null) ...[
              const SizedBox(height: 8),
              Center(child: Image.file(File(image), height: 140, fit: BoxFit.contain)),
            ],
          ]),
          _card([
            _fileRow(
              label: 'Narration',
              path: _narrationPath,
              onChoose: () => _pick(KainuwaEncoder.pickAudio, (p) => _narrationPath = p, 'narration'),
            ),
            _slider(
              label: 'Narration volume',
              value: _narrationVolume,
              min: 0,
              max: 1,
              divisions: 20,
              format: pct,
              onChanged: (v) => setState(() => _narrationVolume = v),
            ),
          ]),
          _card([
            _fileRow(
              label: 'Music',
              path: _musicPath,
              onChoose: () => _pick(KainuwaEncoder.pickAudio, (p) => _musicPath = p, 'music'),
              onClear: () => setState(() => _musicPath = null),
            ),
            _slider(
              label: 'Music volume',
              value: _musicVolume,
              min: 0,
              max: 1,
              divisions: 20,
              format: pct,
              onChanged: (v) => setState(() => _musicVolume = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Fade in and fade out (2 s each)'),
              value: _musicFades,
              onChanged: _busy ? null : (v) => setState(() => _musicFades = v),
            ),
          ]),
          _card([
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Animated text label'),
              value: _overlayOn,
              onChanged: _busy ? null : (v) => setState(() => _overlayOn = v),
            ),
            if (_overlayOn) ...[
              TextField(
                controller: _overlayText,
                enabled: !_busy,
                maxLength: 40,
                decoration: const InputDecoration(labelText: 'Label text'),
              ),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 'fade', label: Text('Fade')),
                  ButtonSegment(value: 'slide', label: Text('Slide')),
                  ButtonSegment(value: 'pop', label: Text('Pop')),
                  ButtonSegment(value: 'zoom', label: Text('Zoom')),
                ],
                selected: {_animation},
                onSelectionChanged: _busy ? null : (s) => setState(() => _animation = s.first),
              ),
              _slider(
                label: 'Starts at',
                value: _overlayStart,
                min: 0,
                max: 10,
                divisions: 20,
                format: secs,
                onChanged: (v) => setState(() => _overlayStart = v),
              ),
              _slider(
                label: 'Animation length',
                value: _overlayLength,
                min: 0.3,
                max: 3,
                divisions: 27,
                format: secs,
                onChanged: (v) => setState(() => _overlayLength = v),
              ),
            ],
          ]),
          const SizedBox(height: 8),
          if (_busy) ...[
            LinearProgressIndicator(value: _progress > 0 ? _progress / 100 : null),
            const SizedBox(height: 8),
            Text('$_progress%'),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: _cancel, child: const Text('Cancel export')),
          ] else
            FilledButton(
              onPressed: ready ? _export : null,
              child: const Text('Export MP4'),
            ),
          if (_unsavedVideo != null && !_busy) ...[
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => _save(_unsavedVideo!),
              child: const Text('Save video'),
            ),
          ],
          const SizedBox(height: 16),
          Text(
            _status,
            style: TextStyle(color: _failed ? scheme.error : scheme.onSurface),
          ),
        ],
      ),
    );
  }
}

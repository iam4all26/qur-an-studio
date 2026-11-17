import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:kainuwa_encoder/kainuwa_encoder.dart';

import '../theme.dart';
import 'resource_manager.dart' show kDataBase;

/// One short recitation (Al-Fatihah 1:2) per reciter, saved once in quran/preview.
/// Only one preview plays at a time; [playing] and [loading] hold the reciter id.
class ReciterPreview {
  ReciterPreview._();

  static const String _clipId = 'reciter_preview';
  static final ValueNotifier<String?> playing = ValueNotifier<String?>(null);
  static final ValueNotifier<String?> loading = ValueNotifier<String?>(null);
  static int _token = 0;
  static Timer? _timer;

  static Future<void> stop() async {
    _token++;
    _timer?.cancel();
    playing.value = null;
    loading.value = null;
    try {
      await KainuwaEncoder.stopClip(_clipId);
    } catch (_) {}
  }

  /// Plays the preview, or stops it when this reciter is already playing or loading.
  /// [onError] gets a short message when the sample cannot be fetched or played.
  static Future<void> toggle(String id, String urlTemplate, void Function(String) onError) async {
    if (playing.value == id || loading.value == id) {
      await stop();
      return;
    }
    await stop();
    if (urlTemplate.isEmpty) {
      onError('No preview for this reciter.');
      return;
    }
    final my = ++_token;
    loading.value = id;
    try {
      final root = '${await KainuwaEncoder.filesDir()}/quran/preview';
      await Directory(root).create(recursive: true);
      final file = File('$root/$id.mp3');
      if (!await file.exists() || await file.length() < 1000) {
        final url = urlTemplate.replaceAll('{SSS}', '001').replaceAll('{AAA}', '002');
        final c = HttpClient()..connectionTimeout = const Duration(seconds: 15);
        try {
          final res = await (await c.getUrl(Uri.parse(url))).close();
          if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
          final bytes = await res.fold<List<int>>(<int>[], (a, b) => a..addAll(b));
          await file.writeAsBytes(bytes, flush: true);
        } finally {
          c.close(force: true);
        }
      }
      if (my != _token) return;
      final ms = await KainuwaEncoder.audioDuration(file.path);
      if (my != _token) return;
      await KainuwaEncoder.playClip(_clipId, file.path);
      loading.value = null;
      playing.value = id;
      _timer = Timer(Duration(milliseconds: (ms > 0 ? ms : 8000) + 300), () {
        if (playing.value == id) playing.value = null;
      });
    } catch (e) {
      if (my == _token) {
        loading.value = null;
        onError('Could not play the preview. Check the internet connection. ($e)');
      }
    }
  }
}

/// Round purple play/stop button for one reciter.
class ReciterPreviewButton extends StatelessWidget {
  const ReciterPreviewButton({super.key, required this.id, required this.urlTemplate});

  final String id;
  final String urlTemplate;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: ReciterPreview.loading,
      builder: (context, loadingId, _) => ValueListenableBuilder<String?>(
        valueListenable: ReciterPreview.playing,
        builder: (context, playingId, __) => InkResponse(
          radius: 24,
          onTap: () => ReciterPreview.toggle(id, urlTemplate, (m) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
            }
          }),
          child: Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(color: KColors.selected, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: loadingId == id
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Icon(playingId == id ? Icons.stop : Icons.play_arrow, color: Colors.white, size: 22),
          ),
        ),
      ),
    );
  }
}

/// Round reciter picture: the copy saved on the phone, else downloaded once from the data
/// repo and saved; initials when there is no picture.
class ReciterAvatar extends StatefulWidget {
  const ReciterAvatar({super.key, required this.id, required this.name, this.image = '', this.radius = 24});

  final String id;
  final String name;
  final String image; // path inside the data repo, for example reciters/alafasy.jpg
  final double radius;

  @override
  State<ReciterAvatar> createState() => _ReciterAvatarState();
}

class _ReciterAvatarState extends State<ReciterAvatar> {
  String _path = '';

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    try {
      final dir = '${await KainuwaEncoder.filesDir()}/quran/pictures';
      final f = File('$dir/${widget.id}.jpg');
      if (await f.exists() && await f.length() > 1000) {
        if (mounted) setState(() => _path = f.path);
        return;
      }
      if (widget.image.isEmpty) return;
      final c = HttpClient()..connectionTimeout = const Duration(seconds: 10);
      try {
        final res = await (await c.getUrl(Uri.parse('$kDataBase${widget.image}'))).close();
        if (res.statusCode != 200) return;
        final bytes = await res.fold<List<int>>(<int>[], (a, b) => a..addAll(b));
        if (bytes.length < 1000) return;
        await Directory(dir).create(recursive: true);
        await f.writeAsBytes(bytes, flush: true);
        if (mounted) setState(() => _path = f.path);
      } finally {
        c.close(force: true);
      }
    } catch (_) {}
  }

  String get _initials {
    final parts = widget.name
        .replaceAll(RegExp(r'\([^)]*\)'), ' ')
        .split(RegExp(r'\s+'))
        .where((p) => RegExp(r'[A-Za-z]').hasMatch(p))
        .toList();
    if (parts.isEmpty) return '?';
    return (parts.first[0] + (parts.length > 1 ? parts.last[0] : '')).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.radius * 2;
    return CircleAvatar(
      radius: widget.radius,
      backgroundColor: const Color(0xFFEDE8FF),
      child: _path.isEmpty
          ? Text(_initials, style: const TextStyle(color: Color(0xFF3A2C8F), fontWeight: FontWeight.w800))
          : ClipOval(
              child: Image.file(
                File(_path),
                width: d,
                height: d,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    Text(_initials, style: const TextStyle(color: Color(0xFF3A2C8F), fontWeight: FontWeight.w800)),
              ),
            ),
    );
  }
}

import 'dart:io';

import 'package:flutter/material.dart';

import '../theme.dart';
import 'background_manager.dart';
import 'resource_manager.dart' show kDataBase;

String _size(int bytes) => bytes >= 1048576
    ? '${(bytes / 1048576).toStringAsFixed(1)} MB'
    : '${(bytes / 1024).toStringAsFixed(0)} KB';

class BackgroundsScreen extends StatefulWidget {
  const BackgroundsScreen({super.key});

  @override
  State<BackgroundsScreen> createState() => _BackgroundsScreenState();
}

class _BackgroundsScreenState extends State<BackgroundsScreen> {
  final bm = BackgroundManager.instance;

  @override
  void initState() {
    super.initState();
    bm.load().then((_) => bm.refresh());
  }

  Widget _thumb(BgClip c) {
    const size = 84.0;
    Widget fallback() => Container(
          width: size,
          height: size,
          color: KColors.surface,
          child: const Icon(Icons.movie_outlined),
        );
    return FutureBuilder<String>(
      future: bm.previewPath(c.id),
      builder: (context, snap) {
        final p = snap.data;
        if (p != null && File(p).existsSync()) {
          return Image.file(File(p), width: size, height: size, fit: BoxFit.cover);
        }
        if (c.preview.isEmpty) return fallback();
        return Image.network('$kDataBase${c.preview}',
            width: size, height: size, fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback());
      },
    );
  }

  Widget _row(BgClip c) {
    final ready = bm.isReady(c.id);
    final p = bm.progress[c.id];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            ClipRRect(borderRadius: BorderRadius.circular(10), child: _thumb(c)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text('${(c.durationMs / 1000).round()} s, ${_size(c.sizeBytes)}',
                      style: const TextStyle(fontSize: 12)),
                  if (c.attribution.isNotEmpty)
                    Text(c.attribution, style: const TextStyle(fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis),
                  if (c.licence.isNotEmpty)
                    Text(c.licence, style: const TextStyle(fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis),
                  if (p != null) ...[
                    const SizedBox(height: 6),
                    LinearProgressIndicator(value: p),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (ready)
              IconButton(
                tooltip: 'Delete download',
                onPressed: bm.busy ? null : () => bm.remove(c),
                icon: const Icon(Icons.delete_outline),
              )
            else
              IconButton.filledTonal(
                tooltip: 'Download',
                onPressed: bm.busy ? null : () => bm.download(c),
                icon: const Icon(Icons.download),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Video backgrounds'),
        actions: [
          IconButton(
            tooltip: 'Refresh list',
            onPressed: bm.busy ? null : bm.refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: bm,
        builder: (context, _) {
          final cats = <String, List<BgClip>>{};
          for (final c in bm.clips) {
            cats.putIfAbsent(c.category, () => []).add(c);
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Moving backgrounds for your videos. Download the ones you like; they work offline afterwards.',
                style: TextStyle(fontSize: 13),
              ),
              if (bm.busy && bm.clips.isEmpty) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
              if (bm.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(bm.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              if (!bm.busy && bm.clips.isEmpty && bm.error == null)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: Text('No clips are published yet.'),
                ),
              for (final e in cats.entries) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 16, bottom: 6),
                  child: Text(e.key, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: KColors.gold)),
                ),
                for (final c in e.value) _row(c),
              ],
            ],
          );
        },
      ),
    );
  }
}

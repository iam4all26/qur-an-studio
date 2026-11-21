import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'reciter_media.dart';
import 'resource_manager.dart';

/// Reciter names and pictures by id, read from the downloaded reciters list.
class ReciterLookup {
  static Map<String, (String, String)>? _cache;

  static Future<Map<String, (String, String)>> all() async {
    final have = _cache;
    if (have != null) return have;
    final out = <String, (String, String)>{};
    try {
      final rm = ResourceManager.instance;
      await rm.load();
      final e = rm.byId('reciters');
      if (e != null && rm.isReady('reciters')) {
        final j = jsonDecode(await File(await rm.pathOf(e)).readAsString()) as Map<String, dynamic>;
        for (final r in (j['reciters'] as List? ?? const [])) {
          final m = r as Map<String, dynamic>;
          out['${m['id']}'] = ('${m['name'] ?? m['id']}', '${m['image'] ?? ''}');
        }
        _cache = out;
      }
    } catch (_) {}
    return out;
  }
}

/// Small round picture of the reciter (nothing when the video has no reciter stored).
class ReciterBadge extends StatelessWidget {
  const ReciterBadge({super.key, required this.id, this.radius = 12});
  final String id;
  final double radius;

  @override
  Widget build(BuildContext context) {
    if (id.isEmpty) return const SizedBox.shrink();
    return FutureBuilder<Map<String, (String, String)>>(
      future: ReciterLookup.all(),
      builder: (context, snap) {
        final r = snap.data?[id];
        return ReciterAvatar(id: id, name: r?.$1 ?? id, image: r?.$2 ?? '', radius: radius);
      },
    );
  }
}

/// The reciter's name as text.
class ReciterName extends StatelessWidget {
  const ReciterName({super.key, required this.id, this.style});
  final String id;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    if (id.isEmpty) return const SizedBox.shrink();
    return FutureBuilder<Map<String, (String, String)>>(
      future: ReciterLookup.all(),
      builder: (context, snap) => Text(
        snap.data?[id]?.$1 ?? '',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      ),
    );
  }
}

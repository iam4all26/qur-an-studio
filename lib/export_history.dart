import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:kainuwa_encoder/kainuwa_encoder.dart';

/// One finished export, remembered so the success screen can list the project's videos.
class ExportEntry {
  ExportEntry({
    required this.id,
    required this.lessonId,
    required this.name,
    required this.uri,
    required this.width,
    required this.height,
    required this.sizeBytes,
    required this.durationMs,
    required this.thumbPath,
    required this.atMs,
  });

  final String id;
  final String lessonId;
  final String name; // file name without .mp4
  final String uri; // content address of the saved video, may be empty
  final int width;
  final int height;
  final int sizeBytes;
  final int durationMs;
  final String thumbPath; // may be empty
  final int atMs;

  String get quality {
    switch (math.min(width, height)) {
      case 480:
        return 'SD';
      case 720:
        return 'HD';
      case 1080:
        return 'FHD';
      case 1440:
        return '2K';
      default:
        return '';
    }
  }

  String get resolution {
    final base = '$width×$height';
    return quality.isEmpty ? base : '$base ($quality)';
  }

  String get shortResolution => '$width×$height';

  String get sizeText {
    final kb = sizeBytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(0)} KB';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
    return '${(mb / 1024).toStringAsFixed(2)} GB';
  }

  String get clock {
    final total = (durationMs / 1000).round();
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    final ss = s.toString().padLeft(2, '0');
    if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$ss';
    return '${m.toString().padLeft(2, '0')}:$ss';
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'lessonId': lessonId,
        'name': name,
        'uri': uri,
        'width': width,
        'height': height,
        'sizeBytes': sizeBytes,
        'durationMs': durationMs,
        'thumbPath': thumbPath,
        'atMs': atMs,
      };

  static ExportEntry fromJson(Map<String, dynamic> j) => ExportEntry(
        id: (j['id'] ?? '').toString(),
        lessonId: (j['lessonId'] ?? '').toString(),
        name: (j['name'] ?? 'Video').toString(),
        uri: (j['uri'] ?? '').toString(),
        width: (j['width'] as num?)?.toInt() ?? 0,
        height: (j['height'] as num?)?.toInt() ?? 0,
        sizeBytes: (j['sizeBytes'] as num?)?.toInt() ?? 0,
        durationMs: (j['durationMs'] as num?)?.toInt() ?? 0,
        thumbPath: (j['thumbPath'] ?? '').toString(),
        atMs: (j['atMs'] as num?)?.toInt() ?? 0,
      );
}

/// Stores the export list in a small JSON file inside the app's own folder.
class ExportHistory {
  ExportHistory._();

  static const int _keep = 40;

  static Future<Directory> dir() async {
    final base = await KainuwaEncoder.filesDir();
    final d = Directory('$base/export_history');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static Future<List<ExportEntry>> _all() async {
    try {
      final file = File('${(await dir()).path}/history.json');
      if (!await file.exists()) return [];
      final data = jsonDecode(await file.readAsString());
      if (data is! List) return [];
      return [
        for (final item in data)
          if (item is Map<String, dynamic>) ExportEntry.fromJson(item),
      ];
    } catch (_) {
      return [];
    }
  }

  static Future<void> _write(List<ExportEntry> all) async {
    try {
      final file = File('${(await dir()).path}/history.json');
      await file.writeAsString(jsonEncode([for (final e in all) e.toJson()]), flush: true);
    } catch (_) {}
  }

  /// Newest first.
  static Future<List<ExportEntry>> load(String lessonId) async {
    final all = await _all();
    final mine = all.where((e) => e.lessonId == lessonId).toList();
    mine.sort((a, b) => b.atMs.compareTo(a.atMs));
    return mine;
  }

  static Future<void> add(ExportEntry entry) async {
    final all = await _all();
    all.removeWhere((e) => e.id == entry.id);
    all.add(entry);
    all.sort((a, b) => b.atMs.compareTo(a.atMs));
    while (all.length > _keep) {
      final old = all.removeLast();
      await _dropThumb(old);
    }
    await _write(all);
  }

  static Future<void> remove(String id) async {
    final all = await _all();
    final hit = all.where((e) => e.id == id).toList();
    all.removeWhere((e) => e.id == id);
    for (final e in hit) {
      await _dropThumb(e);
    }
    await _write(all);
  }

  static Future<void> _dropThumb(ExportEntry e) async {
    if (e.thumbPath.isEmpty) return;
    try {
      await File(e.thumbPath).delete();
    } catch (_) {}
  }
}

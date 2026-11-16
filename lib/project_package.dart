import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:kainuwa_encoder/kainuwa_encoder.dart';

import 'models.dart';

/// A .kainuwa file holds one whole course with every picture, video and sound it uses,
/// so it can be opened on another phone exactly as it was (all items, times and settings).
///
/// Layout: the 8 letters KAINUWA1, then the length of the header (8 bytes), then the header
/// (JSON: the course and the list of files with their sizes), then the files one after another.
class ProjectPackage {
  static const String _magic = 'KAINUWA1';
  static const String _prefix = '@m/';

  static bool _isFilePath(Object? v) => v is String && v.startsWith('/') && v.length > 1;

  /// Writes the course to [target]. Returns how many media files were included.
  static Future<int> exportTo(Course course, String target) async {
    final names = <String, String>{}; // original path -> name inside the file
    final sizes = <String, int>{};
    var counter = 0;

    Object? walk(Object? node) {
      if (node is Map) {
        return node.map((k, v) => MapEntry(k, walk(v)));
      }
      if (node is List) {
        return node.map(walk).toList();
      }
      if (_isFilePath(node)) {
        final path = node as String;
        final file = File(path);
        if (!file.existsSync()) return node;
        final known = names[path];
        if (known != null) return '$_prefix$known';
        final base = path.split('/').last.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
        final name = '${counter++}_$base';
        names[path] = name;
        sizes[name] = file.lengthSync();
        return '$_prefix$name';
      }
      return node;
    }

    final courseJson = walk(jsonDecode(jsonEncode(course.toJson())));
    final order = names.entries.toList();
    final header = utf8.encode(jsonEncode({
      'format': 'kainuwa-course',
      'version': 1,
      'course': courseJson,
      'files': [
        for (final e in order) {'name': e.value, 'size': sizes[e.value]}
      ],
    }));

    final out = File(target).openWrite();
    try {
      out.add(utf8.encode(_magic));
      final len = ByteData(8)..setInt64(0, header.length);
      out.add(len.buffer.asUint8List());
      out.add(header);
      for (final e in order) {
        await out.addStream(File(e.key).openRead());
      }
      await out.flush();
    } finally {
      await out.close();
    }
    return order.length;
  }

  /// Reads a .kainuwa file and returns the course, with its media copied into the app.
  static Future<Course> importFrom(String source) async {
    final raf = await File(source).open();
    try {
      final magic = await raf.read(8);
      if (utf8.decode(magic, allowMalformed: true) != _magic) {
        throw const FormatException('This is not a Qur\'an Studio project file.');
      }
      final lenBytes = await raf.read(8);
      final headerLen = ByteData.sublistView(Uint8List.fromList(lenBytes)).getInt64(0);
      if (headerLen <= 0 || headerLen > 200 * 1024 * 1024) {
        throw const FormatException('The project file is damaged.');
      }
      final header = jsonDecode(utf8.decode(await raf.read(headerLen))) as Map<String, dynamic>;
      if (header['format'] != 'kainuwa-course') {
        throw const FormatException('This project file type is not supported.');
      }

      final newCourseId = newId();
      final base = await KainuwaEncoder.filesDir();
      final dir = Directory('$base/imported/$newCourseId');
      await dir.create(recursive: true);

      final files = (header['files'] as List).cast<Map<String, dynamic>>();
      final where = <String, String>{};
      for (final f in files) {
        final name = f['name'] as String;
        var left = (f['size'] as num).toInt();
        final target = File('${dir.path}/$name');
        final sink = target.openWrite();
        try {
          while (left > 0) {
            final chunk = await raf.read(left > 262144 ? 262144 : left);
            if (chunk.isEmpty) {
              throw const FormatException('The project file is incomplete.');
            }
            sink.add(chunk);
            left -= chunk.length;
          }
          await sink.flush();
        } finally {
          await sink.close();
        }
        where[name] = target.path;
      }

      Object? walk(Object? node) {
        if (node is Map) return node.map((k, v) => MapEntry(k, walk(v)));
        if (node is List) return node.map(walk).toList();
        if (node is String && node.startsWith(_prefix)) {
          return where[node.substring(_prefix.length)] ?? '';
        }
        return node;
      }

      final json = Map<String, dynamic>.from(walk(header['course']) as Map);
      json['id'] = newCourseId;
      return Course.fromJson(json);
    } finally {
      await raf.close();
    }
  }
}

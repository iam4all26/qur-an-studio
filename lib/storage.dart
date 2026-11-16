import 'dart:convert';
import 'dart:io';

import 'package:kainuwa_encoder/kainuwa_encoder.dart';

import 'models.dart';

/// Saves courses and settings as small JSON files inside the app's private
/// storage. Everything stays on the phone.
class StorageService {
  Directory? _dir;

  Future<Directory> _root() async {
    final existing = _dir;
    if (existing != null) return existing;
    final base = await KainuwaEncoder.filesDir();
    final dir = Directory('$base/kainuwa_data');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _dir = dir;
    return dir;
  }

  Future<Map<String, dynamic>?> _readJson(String name) async {
    final dir = await _root();
    final file = File('${dir.path}/$name');
    if (!await file.exists()) return null;
    try {
      final data = jsonDecode(await file.readAsString());
      if (data is Map<String, dynamic>) return data;
    } catch (_) {
      // Keep the unreadable file so nothing is lost, then start fresh.
      try {
        await file.rename('${file.path}.bad');
      } catch (_) {}
    }
    return null;
  }

  Future<void> _writeJson(String name, Map<String, dynamic> data) async {
    final dir = await _root();
    final file = File('${dir.path}/$name');
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(data), flush: true);
    await temp.rename(file.path);
  }

  Future<List<Course>> loadCourses() async {
    final data = await _readJson('courses.json');
    final raw = data?['courses'];
    final courses = <Course>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map<String, dynamic>) {
          try {
            courses.add(Course.fromJson(item));
          } catch (_) {}
        }
      }
    }
    return courses;
  }

  Future<void> saveCourses(List<Course> courses) {
    return _writeJson('courses.json', {
      'courses': courses.map((c) => c.toJson()).toList(),
    });
  }

  Future<AppSettings> loadSettings() async {
    final data = await _readJson('settings.json');
    if (data == null) return const AppSettings();
    return AppSettings.fromJson(data);
  }

  Future<void> saveSettings(AppSettings settings) {
    return _writeJson('settings.json', settings.toJson());
  }
}

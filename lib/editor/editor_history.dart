import 'dart:convert';

import '../models.dart';

/// Keeps snapshots of one lesson so that edits can be undone and redone.
class EditorHistory {
  EditorHistory(Lesson lesson) : _current = _encode(lesson);

  static const int _limit = 60;

  final List<String> _undo = <String>[];
  final List<String> _redo = <String>[];
  String _current;

  static String _encode(Lesson lesson) => jsonEncode(lesson.toJson());

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  /// Call after every finished edit. A snapshot is stored only when something changed.
  void record(Lesson lesson) {
    final next = _encode(lesson);
    if (next == _current) return;
    _undo.add(_current);
    if (_undo.length > _limit) _undo.removeAt(0);
    _redo.clear();
    _current = next;
  }

  /// Goes back one step. Returns false when there is nothing to undo.
  bool undo(Lesson lesson) {
    if (_undo.isEmpty) return false;
    _redo.add(_current);
    _current = _undo.removeLast();
    _restore(lesson, _current);
    return true;
  }

  /// Goes forward one step. Returns false when there is nothing to redo.
  bool redo(Lesson lesson) {
    if (_redo.isEmpty) return false;
    _undo.add(_current);
    _current = _redo.removeLast();
    _restore(lesson, _current);
    return true;
  }

  void _restore(Lesson lesson, String json) {
    final data = jsonDecode(json);
    if (data is! Map<String, dynamic>) return;
    final copy = Lesson.fromJson(data);
    lesson.title = copy.title;
    lesson.aspectW = copy.aspectW;
    lesson.aspectH = copy.aspectH;
    lesson.musicPath = copy.musicPath;
    lesson.musicVolume = copy.musicVolume;
    lesson.musicFade = copy.musicFade;
    lesson.hiddenTracks
      ..clear()
      ..addAll(copy.hiddenTracks);
    lesson.audioClips
      ..clear()
      ..addAll(copy.audioClips);
    lesson.scenes
      ..clear()
      ..addAll(copy.scenes);
  }
}

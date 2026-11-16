class SrtCue {
  const SrtCue(this.startMs, this.endMs, this.text);
  final int startMs;
  final int endMs;
  final String text;
}

int? _stamp(String s) {
  final m = RegExp(r'(\d+):(\d+):(\d+)[,.](\d+)').firstMatch(s);
  if (m == null) return null;
  final ms = int.parse(m.group(4)!.padRight(3, '0').substring(0, 3));
  return ((int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!)) * 60 + int.parse(m.group(3)!)) * 1000 + ms;
}

/// Reads the text of an .srt file into timed captions.
List<SrtCue> parseSrt(String raw) {
  final text = raw.replaceAll('﻿', '').replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final cues = <SrtCue>[];
  for (final block in text.split(RegExp(r'\n\s*\n'))) {
    final lines = block.trim().split('\n');
    final at = lines.indexWhere((l) => l.contains('-->'));
    if (at < 0) continue;
    final parts = lines[at].split('-->');
    if (parts.length < 2) continue;
    final start = _stamp(parts[0]);
    final end = _stamp(parts[1]);
    if (start == null || end == null || end <= start) continue;
    final body = lines
        .sublist(at + 1)
        .join('\n')
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll(RegExp(r'\{[^}]*\}'), '')
        .trim();
    if (body.isEmpty) continue;
    cues.add(SrtCue(start, end, body));
  }
  return cues;
}

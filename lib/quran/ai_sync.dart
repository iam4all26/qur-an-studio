import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:kainuwa_encoder/kainuwa_encoder.dart';

/// How the service is called.
/// openai = speech-to-text endpoint of the OpenAI kind (word times), gemini = Google Gemini.
enum AiKind { openai, gemini }

class AiProvider {
  const AiProvider({
    required this.id,
    required this.name,
    required this.kind,
    required this.baseUrl,
    required this.model,
    required this.note,
    this.editableUrl = false,
  });

  final String id;
  final String name;
  final AiKind kind;
  final String baseUrl;
  final String model;
  final String note;

  /// The address can be changed (any service that follows the OpenAI speech-to-text format).
  final bool editableUrl;
}

/// The services the app can use for Auto Sync. Model names can be changed in the settings
/// because providers rename them.
const List<AiProvider> kAiProviders = [
  AiProvider(
    id: 'openai',
    name: 'OpenAI (Whisper)',
    kind: AiKind.openai,
    baseUrl: 'https://api.openai.com/v1',
    model: 'whisper-1',
    note: 'Speech to text with the time of every word. Paid, charged by the minute of audio.',
  ),
  AiProvider(
    id: 'groq',
    name: 'Groq (Whisper)',
    kind: AiKind.openai,
    baseUrl: 'https://api.groq.com/openai/v1',
    model: 'whisper-large-v3',
    note: 'Fast Whisper. Has a free tier with daily limits.',
  ),
  AiProvider(
    id: 'gemini',
    name: 'Google Gemini',
    kind: AiKind.gemini,
    baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
    model: 'gemini-2.5-flash',
    note: 'Listens to the recording and returns where each verse starts. Less exact than Whisper (experimental). '
        'Recordings up to about 14 MB.',
  ),
  AiProvider(
    id: 'custom',
    name: 'Other (OpenAI format)',
    kind: AiKind.openai,
    baseUrl: '',
    model: '',
    note: 'Any service that has an audio/transcriptions address in the OpenAI format and returns word times. '
        'Enter its address (ending in /v1) and model.',
    editableUrl: true,
  ),
];

/// API keys and settings, kept in a file in the app's private storage on the phone. They are
/// sent only to the service the person chose, and the file is not encrypted.
class AiConfig {
  AiConfig._();
  static final AiConfig instance = AiConfig._();

  String activeId = '';
  final Map<String, Map<String, String>> _data = {};
  bool _loaded = false;

  Future<File> _file() async {
    final base = await KainuwaEncoder.filesDir();
    final dir = Directory('$base/quran');
    if (!await dir.exists()) await dir.create(recursive: true);
    return File('${dir.path}/ai_config.json');
  }

  Future<void> load({bool force = false}) async {
    if (_loaded && !force) return;
    _loaded = true;
    try {
      final f = await _file();
      if (!await f.exists()) return;
      final j = jsonDecode(await f.readAsString());
      if (j is! Map) return;
      activeId = '${j['active'] ?? ''}';
      _data.clear();
      final p = j['providers'];
      if (p is Map) {
        p.forEach((k, v) {
          if (v is Map) _data['$k'] = v.map((a, b) => MapEntry('$a', '$b'));
        });
      }
    } catch (_) {}
  }

  Future<void> save() async {
    final f = await _file();
    await f.writeAsString(jsonEncode({'active': activeId, 'providers': _data}), flush: true);
  }

  AiProvider? providerById(String id) {
    for (final p in kAiProviders) {
      if (p.id == id) return p;
    }
    return null;
  }

  String keyOf(String id) => _data[id]?['key'] ?? '';
  String modelOf(String id) {
    final m = _data[id]?['model'] ?? '';
    return m.isNotEmpty ? m : (providerById(id)?.model ?? '');
  }

  String baseOf(String id) {
    final b = _data[id]?['base'] ?? '';
    return b.isNotEmpty ? b : (providerById(id)?.baseUrl ?? '');
  }

  bool isReady(String id) => keyOf(id).isNotEmpty && modelOf(id).isNotEmpty && baseOf(id).isNotEmpty;

  /// The provider to use, or null when no key was added.
  AiProvider? get active {
    final p = providerById(activeId);
    if (p != null && isReady(p.id)) return p;
    for (final x in kAiProviders) {
      if (isReady(x.id)) return x;
    }
    return null;
  }

  Future<void> set(String id, {required String key, required String model, String base = ''}) async {
    _data[id] = {'key': key.trim(), 'model': model.trim(), 'base': base.trim()};
    if (activeId.isEmpty || !isReady(activeId)) activeId = id;
    await save();
  }

  Future<void> remove(String id) async {
    _data.remove(id);
    if (activeId == id) activeId = '';
    await save();
  }

  Future<void> setActive(String id) async {
    activeId = id;
    await save();
  }
}

class AsrWord {
  AsrWord(this.text, this.startMs, this.endMs);
  final String text;
  final int startMs;
  final int endMs;
}

class AiSyncResult {
  AiSyncResult(this.boundaries, this.matchedPercent, this.note);

  /// n + 1 boundaries in ms for n verses.
  final List<int> boundaries;
  final int matchedPercent;
  final String note;
}

class AiSyncException implements Exception {
  AiSyncException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Auto Sync with an AI service: the recording is sent to the service, the answer is lined up
/// with the known verse text, and the start of every verse becomes a boundary.
class AiSync {
  AiSync._();

  static const int _openaiLimit = 25 * 1024 * 1024;
  static const int _geminiLimit = 14 * 1024 * 1024;

  static Future<AiSyncResult> run({
    required AiProvider provider,
    required AiConfig config,
    required String audioPath,
    required int totalMs,
    required List<String> verses,
  }) async {
    final file = File(audioPath);
    if (!await file.exists()) throw AiSyncException('The audio file is no longer available.');
    final size = await file.length();
    final key = config.keyOf(provider.id);
    final model = config.modelOf(provider.id);
    final base = config.baseOf(provider.id).replaceAll(RegExp(r'/+$'), '');
    if (provider.kind == AiKind.gemini) {
      if (size > _geminiLimit) {
        throw AiSyncException(
            'This recording is ${_mb(size)} MB. Gemini accepts about 14 MB here. Use a shorter recording or choose Whisper.');
      }
      final starts = await _gemini(base, model, key, file, verses);
      return _fromStarts(starts, totalMs, verses.length);
    }
    if (size > _openaiLimit) {
      throw AiSyncException(
          'This recording is ${_mb(size)} MB. The service accepts up to 25 MB. Use a shorter recording.');
    }
    final words = await _whisper(base, model, key, file);
    return alignWords(verses, words, totalMs);
  }

  static String _mb(int bytes) => (bytes / 1048576).toStringAsFixed(1);

  // ---------------------------------------------------------------- network

  static Future<String> _send(HttpClientRequest req, Uint8List body, {required Duration wait}) async {
    req.contentLength = body.length;
    req.add(body);
    final res = await req.close().timeout(wait);
    final text = await res.transform(utf8.decoder).join().timeout(wait);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      var msg = text;
      try {
        final j = jsonDecode(text);
        if (j is Map) {
          final e = j['error'];
          if (e is Map && e['message'] != null) {
            msg = '${e['message']}';
          } else if (e != null) {
            msg = '$e';
          }
        }
      } catch (_) {}
      if (msg.length > 300) msg = msg.substring(0, 300);
      if (res.statusCode == 401 || res.statusCode == 403) {
        throw AiSyncException('The service refused the API key (HTTP ${res.statusCode}). Check the key. $msg');
      }
      if (res.statusCode == 429) {
        throw AiSyncException('Too many requests or no credit left (HTTP 429). $msg');
      }
      throw AiSyncException('The service answered HTTP ${res.statusCode}. $msg');
    }
    return text;
  }

  static String _ext(String path) {
    final i = path.lastIndexOf('.');
    return i < 0 ? '' : path.substring(i + 1).toLowerCase();
  }

  static String _mime(String ext) {
    switch (ext) {
      case 'mp3':
        return 'audio/mpeg';
      case 'wav':
        return 'audio/wav';
      case 'm4a':
      case 'mp4':
        return 'audio/mp4';
      case 'aac':
        return 'audio/aac';
      case 'ogg':
      case 'opus':
        return 'audio/ogg';
      case 'flac':
        return 'audio/flac';
      default:
        return 'audio/mpeg';
    }
  }

  static Future<List<AsrWord>> _whisper(String base, String model, String key, File file) async {
    final boundary = '----quranstudio${DateTime.now().microsecondsSinceEpoch}';
    final ext = _ext(file.path);
    final out = BytesBuilder(copy: false);
    void field(String name, String value) {
      out.add(utf8.encode('--$boundary\r\nContent-Disposition: form-data; name="$name"\r\n\r\n$value\r\n'));
    }

    field('model', model);
    field('response_format', 'verbose_json');
    field('language', 'ar');
    field('temperature', '0');
    field('timestamp_granularities[]', 'word');
    field('timestamp_granularities[]', 'segment');
    out.add(utf8.encode('--$boundary\r\nContent-Disposition: form-data; name="file"; '
        'filename="recitation.${ext.isEmpty ? 'mp3' : ext}"\r\nContent-Type: ${_mime(ext)}\r\n\r\n'));
    out.add(await file.readAsBytes());
    out.add(utf8.encode('\r\n--$boundary--\r\n'));

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      final req = await client.postUrl(Uri.parse('$base/audio/transcriptions'));
      req.headers.set('Authorization', 'Bearer $key');
      req.headers.set('Content-Type', 'multipart/form-data; boundary=$boundary');
      final text = await _send(req, out.takeBytes(), wait: const Duration(minutes: 10));
      final j = jsonDecode(text);
      if (j is! Map) throw AiSyncException('The service answer could not be read.');
      final words = <AsrWord>[];
      final w = j['words'];
      if (w is List && w.isNotEmpty) {
        for (final x in w) {
          if (x is Map) {
            final t = '${x['word'] ?? x['text'] ?? ''}'.trim();
            final s = ((x['start'] as num?) ?? 0) * 1000;
            final e = ((x['end'] as num?) ?? 0) * 1000;
            if (t.isNotEmpty) words.add(AsrWord(t, s.round(), e.round()));
          }
        }
      }
      if (words.isEmpty) {
        // Only segments: spread the words of each segment evenly over its time.
        final seg = j['segments'];
        if (seg is List) {
          for (final x in seg) {
            if (x is! Map) continue;
            final parts = '${x['text'] ?? ''}'.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
            if (parts.isEmpty) continue;
            final s = (((x['start'] as num?) ?? 0) * 1000).round();
            final e = (((x['end'] as num?) ?? 0) * 1000).round();
            for (var i = 0; i < parts.length; i++) {
              final a = s + ((e - s) * i / parts.length).round();
              final b = s + ((e - s) * (i + 1) / parts.length).round();
              words.add(AsrWord(parts[i], a, b));
            }
          }
        }
      }
      if (words.isEmpty) throw AiSyncException('The service returned no words. Try another recording or service.');
      return words;
    } on SocketException catch (e) {
      throw AiSyncException('No connection to the service: ${e.message}');
    } finally {
      client.close(force: true);
    }
  }

  static Future<List<double>> _gemini(String base, String model, String key, File file, List<String> verses) async {
    final ext = _ext(file.path);
    final mime = (ext == 'm4a' || ext == 'mp4') ? 'audio/aac' : (ext == 'mp3' || ext.isEmpty ? 'audio/mp3' : _mime(ext));
    final list = StringBuffer();
    for (var i = 0; i < verses.length; i++) {
      final words = verses[i].trim().split(RegExp(r'\s+')).take(5).join(' ');
      list.writeln('${i + 1}: $words');
    }
    final prompt = 'This audio is a recitation of the Qur\'an: ${verses.length} consecutive verses, one after the other. '
        'For each verse give the time in seconds, from the start of the audio, at which the reciter begins that verse. '
        'The verses and their first words:\n$list'
        'Answer only with JSON in this form: {"starts":[number, ...]} with exactly ${verses.length} numbers in order.';
    final body = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': prompt},
            {
              'inline_data': {'mime_type': mime, 'data': base64Encode(await file.readAsBytes())}
            },
          ]
        }
      ],
      'generationConfig': {'temperature': 0, 'responseMimeType': 'application/json'},
    });
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      final req = await client.postUrl(Uri.parse('$base/models/$model:generateContent'));
      req.headers.set('x-goog-api-key', key);
      req.headers.set('Content-Type', 'application/json');
      final text = await _send(req, Uint8List.fromList(utf8.encode(body)), wait: const Duration(minutes: 5));
      final j = jsonDecode(text);
      var answer = '';
      if (j is Map && j['candidates'] is List && (j['candidates'] as List).isNotEmpty) {
        final c = (j['candidates'] as List).first;
        final parts = c is Map && c['content'] is Map ? (c['content'] as Map)['parts'] : null;
        if (parts is List) {
          for (final p in parts) {
            if (p is Map && p['text'] != null) answer += '${p['text']}';
          }
        }
      }
      answer = answer.trim().replaceAll(RegExp(r'^```(?:json)?'), '').replaceAll(RegExp(r'```$'), '').trim();
      final a = jsonDecode(answer);
      final s = a is Map ? a['starts'] : a;
      if (s is! List) throw AiSyncException('The answer did not contain the verse times.');
      return [for (final x in s) (x is num) ? x.toDouble() : (double.tryParse('$x') ?? -1)];
    } on SocketException catch (e) {
      throw AiSyncException('No connection to the service: ${e.message}');
    } on FormatException {
      throw AiSyncException('The answer of the service could not be read.');
    } finally {
      client.close(force: true);
    }
  }

  // -------------------------------------------------------------- results

  static AiSyncResult _fromStarts(List<double> starts, int totalMs, int n) {
    if (starts.length != n) {
      throw AiSyncException('The service returned ${starts.length} times for $n verses. Try again or use Whisper.');
    }
    final b = <int>[];
    for (var i = 0; i < n; i++) {
      final ms = (starts[i] * 1000).round() - (i == 0 ? 150 : 100);
      b.add(ms);
    }
    b.add(totalMs);
    _fix(b, totalMs);
    return AiSyncResult(b, 100, 'The AI gave the start of each verse (experimental). Check each verse.');
  }

  /// Makes the boundaries strictly increasing with room for every verse inside [0, total].
  static void _fix(List<int> b, int total) {
    final n = b.length - 1;
    const gap = 300;
    b[0] = b[0].clamp(0, math.max(0, total - gap * n)).toInt();
    for (var i = 1; i <= n; i++) {
      final lo = b[i - 1] + gap;
      final hi = total - gap * (n - i);
      b[i] = math.max(lo, math.min(b[i], math.max(lo, hi)));
    }
    b[n] = math.max(b[n], b[n - 1] + gap);
    if (b[n] > total && total > 0) {
      b[n] = total;
    }
  }

  // ------------------------------------------------------------ alignment

  /// Letters only, no marks, one spelling for the letters that are written in several ways.
  static String normalize(String s) {
    final b = StringBuffer();
    for (final r in s.runes) {
      if ((r >= 0x064B && r <= 0x065F) || r == 0x0670 || r == 0x0640 || (r >= 0x06D6 && r <= 0x06ED)) continue;
      switch (r) {
        case 0x0622:
        case 0x0623:
        case 0x0625:
        case 0x0671:
          b.writeCharCode(0x0627);
          break;
        case 0x0649:
        case 0x0626:
        case 0x06CC:
          b.writeCharCode(0x064A);
          break;
        case 0x0629:
          b.writeCharCode(0x0647);
          break;
        case 0x0624:
          b.writeCharCode(0x0648);
          break;
        case 0x06A9:
          b.writeCharCode(0x0643);
          break;
        default:
          if (r >= 0x0621 && r <= 0x064A) b.writeCharCode(r);
      }
    }
    return b.toString();
  }

  static double _sim(String a, String b) {
    if (a == b) return 1.0;
    if (a.isEmpty || b.isEmpty) return 0.0;
    var prev = List<int>.generate(b.length + 1, (j) => j);
    var cur = List<int>.filled(b.length + 1, 0);
    for (var i = 1; i <= a.length; i++) {
      cur[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        cur[j] = math.min(math.min(cur[j - 1] + 1, prev[j] + 1), prev[j - 1] + cost);
      }
      final t = prev;
      prev = cur;
      cur = t;
    }
    final d = prev[b.length];
    return 1.0 - d / math.max(a.length, b.length);
  }

  /// Lines the spoken words up with the verse text and returns the verse boundaries.
  static AiSyncResult alignWords(List<String> verses, List<AsrWord> asr, int totalMs) {
    final n = verses.length;
    // Expected words with their verse number.
    final exp = <String>[];
    final verseOf = <int>[];
    final firstOf = List<int>.filled(n, -1);
    for (var v = 0; v < n; v++) {
      for (final w in verses[v].split(RegExp(r'\s+'))) {
        final x = normalize(w);
        if (x.isEmpty) continue;
        if (firstOf[v] < 0) firstOf[v] = exp.length;
        exp.add(x);
        verseOf.add(v);
      }
    }
    final heard = <String>[];
    final heardWords = <AsrWord>[];
    for (final w in asr) {
      for (final part in w.text.split(RegExp(r'\s+'))) {
        final x = normalize(part);
        if (x.isEmpty) continue;
        heard.add(x);
        heardWords.add(AsrWord(x, w.startMs, w.endMs));
      }
    }
    final m = exp.length;
    final k = heard.length;
    if (m == 0 || k == 0) throw AiSyncException('There is nothing to line up.');

    // Banded alignment (rows = expected words, columns = heard words).
    final half = math.max(100, (math.max(m, k) * 0.15).ceil());
    final width = 2 * half + 1;
    final center = List<int>.generate(m + 1, (i) => (i * k / m).round());
    final score = Float64List((m + 1) * width);
    final dir = Uint8List((m + 1) * width); // 0 diagonal, 1 skip expected, 2 skip heard
    const neg = -1e18;
    const gap = 0.6;

    int col(int i, int j) => j - center[i] + half;

    for (var i = 0; i <= m; i++) {
      for (var c = 0; c < width; c++) {
        final j = center[i] - half + c;
        final at = i * width + c;
        if (j < 0 || j > k) {
          score[at] = neg;
          continue;
        }
        if (i == 0) {
          score[at] = 0; // heard words before the first verse are free
          dir[at] = 2;
          continue;
        }
        var best = neg;
        var d = 0;
        if (j > 0) {
          final pc = col(i - 1, j - 1);
          if (pc >= 0 && pc < width) {
            final ps = score[(i - 1) * width + pc];
            if (ps > neg / 2) {
              final s = _sim(exp[i - 1], heard[j - 1]);
              final v = ps + (s >= 0.6 ? 1.0 + s : -1.0);
              if (v > best) {
                best = v;
                d = 0;
              }
            }
          }
        }
        final uc = col(i - 1, j);
        if (uc >= 0 && uc < width) {
          final ps = score[(i - 1) * width + uc];
          if (ps > neg / 2 && ps - gap > best) {
            best = ps - gap;
            d = 1;
          }
        }
        if (j > 0 && c > 0) {
          final ps = score[at - 1];
          if (ps > neg / 2) {
            final cost = i == m ? 0.0 : gap * 0.7;
            if (ps - cost > best) {
              best = ps - cost;
              d = 2;
            }
          }
        }
        score[at] = best;
        dir[at] = d;
      }
    }

    // Best end in the last row (heard words after the last verse are free).
    var bestJ = -1;
    var bestScore = neg;
    for (var c = 0; c < width; c++) {
      final j = center[m] - half + c;
      if (j < 0 || j > k) continue;
      final v = score[m * width + c];
      if (v > bestScore) {
        bestScore = v;
        bestJ = j;
      }
    }
    if (bestJ < 0 || bestScore <= neg / 2) throw AiSyncException('The recording could not be lined up with the verses.');

    final matchOf = List<int>.filled(m, -1);
    var bi = m;
    var bj = bestJ;
    while (bi > 0) {
      final c = col(bi, bj);
      if (c < 0 || c >= width) break;
      final d = dir[bi * width + c];
      if (d == 0) {
        if (bj > 0 && _sim(exp[bi - 1], heard[bj - 1]) >= 0.6) matchOf[bi - 1] = bj - 1;
        bi--;
        bj--;
      } else if (d == 1) {
        bi--;
      } else {
        bj--;
        if (bj < 0) break;
      }
    }

    var matched = 0;
    for (final x in matchOf) {
      if (x >= 0) matched++;
    }
    final percent = (matched * 100 / m).round();
    if (percent < 30) {
      throw AiSyncException(
          'Only $percent% of the words matched the chosen verses. Check that the verses and the recording are the same.');
    }

    // Typical length of a spoken word, used when the first word of a verse was missed.
    final lens = <int>[for (final w in heardWords) math.max(0, w.endMs - w.startMs)]..sort();
    final avg = lens.isEmpty ? 400 : math.max(150, math.min(900, lens[lens.length ~/ 2]));

    final starts = List<int?>.filled(n, null);
    final ends = List<int?>.filled(n, null);
    for (var v = 0; v < n; v++) {
      for (var e = 0; e < m; e++) {
        if (verseOf[e] != v || matchOf[e] < 0) continue;
        if (starts[v] == null) {
          final behind = e - firstOf[v];
          starts[v] = math.max(0, heardWords[matchOf[e]].startMs - behind * avg);
        }
        ends[v] = heardWords[matchOf[e]].endMs;
      }
    }

    // Verses with no matched word: spread between the neighbours by word count.
    final words = List<int>.filled(n, 0);
    for (final v in verseOf) {
      words[v]++;
    }
    for (var v = 0; v < n; v++) {
      if (starts[v] != null) continue;
      var lo = v - 1;
      while (lo >= 0 && starts[lo] == null) {
        lo--;
      }
      var hi = v + 1;
      while (hi < n && starts[hi] == null) {
        hi++;
      }
      final loT = lo >= 0 ? starts[lo]! : 0;
      final hiT = hi < n ? starts[hi]! : totalMs;
      var before = 0;
      var span = 0;
      for (var x = math.max(lo, 0); x < hi && x < n; x++) {
        if (x < v) before += words[x];
        span += words[x];
      }
      starts[v] = loT + ((hiT - loT) * before / math.max(1, span)).round();
    }

    final b = <int>[];
    for (var v = 0; v < n; v++) {
      final s = starts[v]!;
      if (v == 0) {
        b.add(s - 150);
      } else {
        final prevEnd = ends[v - 1];
        if (prevEnd != null && prevEnd < s) {
          b.add(s - math.min(200, (s - prevEnd) ~/ 2));
        } else {
          b.add(s - 100);
        }
      }
    }
    final last = ends[n - 1];
    b.add(last == null ? totalMs : math.min(totalMs, last + 500));
    _fix(b, totalMs);
    return AiSyncResult(
      b,
      percent,
      '$percent% of the words were matched. Check each verse with Play this verse and adjust if needed.',
    );
  }
}

import 'package:flutter/foundation.dart';
import 'package:kainuwa_encoder/kainuwa_encoder.dart';

/// Loudness shapes of audio files, for drawing real waveforms. A file is read
/// once; the screen is told when a shape is ready.
class PeaksCache extends ChangeNotifier {
  PeaksCache._();

  static final PeaksCache instance = PeaksCache._();

  final Map<String, List<double>> _done = <String, List<double>>{};
  final Set<String> _busy = <String>{};

  /// The shape of [path] (values 0 to 1), or null while it is still being read.
  List<double>? peaksFor(String path) {
    if (path.isEmpty) return null;
    final known = _done[path];
    if (known != null) return known.isEmpty ? null : known;
    if (_busy.add(path)) _load(path);
    return null;
  }

  Future<void> _load(String path) async {
    try {
      _done[path] = await KainuwaEncoder.audioPeaks(path, bins: 240);
    } catch (_) {
      _done[path] = const <double>[];
    }
    _busy.remove(path);
    notifyListeners();
  }
}

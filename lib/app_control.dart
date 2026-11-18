import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:kainuwa_encoder/kainuwa_encoder.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'quran/resource_manager.dart' show kDataBase;
import 'theme.dart';

/// What the owner sets in data/app_config.json of the qurans-data repo.
class AppConfig {
  const AppConfig({
    this.playUrl = '',
    this.minVersion = '',
    this.latestVersion = '',
    this.updateText = '',
    this.annId = '',
    this.annTitle = '',
    this.annText = '',
    this.maintenanceOn = false,
    this.maintenanceText = '',
    this.allOff = false,
    this.allText = '',
    this.features = const [],
    this.featureText = '',
  });

  final String playUrl;
  final String minVersion;
  final String latestVersion;
  final String updateText;
  final String annId;
  final String annTitle;
  final String annText;
  final bool maintenanceOn;
  final String maintenanceText;
  final bool allOff;
  final String allText;
  final List<String> features;
  final String featureText;

  static int _i(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
  static String _s(Object? v) => v is String ? v : '';

  factory AppConfig.fromJson(Map<String, dynamic> j) {
    final ann = j['announcement'] is Map ? j['announcement'] as Map : const {};
    final mt = j['maintenance'] is Map ? j['maintenance'] as Map : const {};
    final off = j['disabled'] is Map ? j['disabled'] as Map : const {};
    return AppConfig(
      playUrl: _s(j['play_url']).trim(),
      minVersion: _s(j['min_version']).trim(),
      latestVersion: _s(j['latest_version']).trim(),
      updateText: _s(j['update_message']),
      annId: _s(ann['id']).trim(),
      annTitle: _s(ann['title']),
      annText: _s(ann['text']),
      maintenanceOn: mt['on'] == true,
      maintenanceText: _s(mt['text']),
      allOff: off['all'] == true,
      allText: _s(off['all_text']),
      features: [for (final f in (off['features'] is List ? off['features'] as List : const [])) '$f'],
      featureText: _s(off['feature_text']),
    );
  }
}

/// Remote control of the app. The app only downloads one small file; it sends nothing about
/// the user. The last file read is saved, so the app works offline with the last known settings.
class AppControl extends ChangeNotifier {
  AppControl._();
  static final AppControl instance = AppControl._();

  AppConfig config = const AppConfig();
  int build = 0;
  String version = '';
  String packageName = 'com.kainuwa.quranstudio';
  bool checking = false;
  bool _softHidden = false;
  String _seenAnn = '';
  String _laterVersion = '';
  int _fetchedAt = 0;
  bool _started = false;

  Future<File> _file() async => File('${await KainuwaEncoder.filesDir()}/quran/app_control.json');

  Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      final info = await PackageInfo.fromPlatform();
      build = int.tryParse(info.buildNumber) ?? 0;
      version = info.version;
      if (info.packageName.isNotEmpty) packageName = info.packageName;
    } catch (_) {}
    try {
      final f = await _file();
      if (await f.exists()) {
        final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        if (j['config'] is Map) config = AppConfig.fromJson(Map<String, dynamic>.from(j['config'] as Map));
        _seenAnn = '${j['seenAnn'] ?? ''}';
        _laterVersion = '${j['laterVersion'] ?? ''}';
        _fetchedAt = (j['fetched'] as num?)?.toInt() ?? 0;
      }
    } catch (_) {}
    notifyListeners();
    // Every start reads the file, so a change you publish is seen at the next launch.
    await refresh(force: true);
  }

  Map<String, dynamic> _raw = {};

  Future<void> _save() async {
    try {
      final f = await _file();
      await f.parent.create(recursive: true);
      await f.writeAsString(jsonEncode({
        'config': _raw,
        'fetched': _fetchedAt,
        'seenAnn': _seenAnn,
        'laterVersion': _laterVersion,
      }));
    } catch (_) {}
  }

  /// Reads the control file. Without internet the saved settings stay in force.
  Future<void> refresh({bool force = false}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!force && now - _fetchedAt < const Duration(minutes: 30).inMilliseconds) return;
    checking = true;
    notifyListeners();
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final uri = Uri.parse('${kDataBase}app_config.json').replace(queryParameters: {'cb': '$now'});
      final res = await (await client.getUrl(uri)).close().timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final body = await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 12));
        final j = jsonDecode(body);
        if (j is Map<String, dynamic>) {
          _raw = j;
          config = AppConfig.fromJson(j);
          _fetchedAt = now;
          await _save();
        }
      }
    } catch (_) {
      // Offline or the file is not published yet: keep the saved settings.
    } finally {
      client.close(force: true);
      checking = false;
      notifyListeners();
    }
  }

  /// Compares version names such as 1.1.0 and 1.10.2 number by number: negative when a is older.
  static int compareVersions(String a, String b) {
    List<int> parts(String v) =>
        v.split(RegExp(r'[.+\-]')).map((p) => int.tryParse(p.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0).toList();
    final x = parts(a);
    final y = parts(b);
    final n = x.length > y.length ? x.length : y.length;
    for (var i = 0; i < n; i++) {
      final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
      if (d != 0) return d;
    }
    return 0;
  }

  bool _older(String than) => version.isNotEmpty && than.isNotEmpty && compareVersions(version, than) < 0;

  bool get forceUpdate => _older(config.minVersion);
  bool get softUpdate =>
      !forceUpdate && _older(config.latestVersion) && _laterVersion != config.latestVersion && !_softHidden;
  bool get annPending => config.annId.isNotEmpty && config.annId != _seenAnn;

  /// A message that blocks the whole app, or null.
  String? get blockedTitle {
    if (forceUpdate) return 'Update required';
    if (config.allOff) return 'Qur\'an Studio is paused';
    if (config.maintenanceOn) return 'Back soon';
    return null;
  }

  String get blockedText {
    if (forceUpdate) {
      return config.updateText.isNotEmpty
          ? config.updateText
          : 'A new version of Qur\'an Studio is needed to continue. Please update from Google Play.';
    }
    if (config.allOff) return config.allText.isNotEmpty ? config.allText : 'Please try again later.';
    return config.maintenanceText.isNotEmpty ? config.maintenanceText : 'We are making improvements. Please try again soon.';
  }

  bool featureOff(String name) => config.features.contains(name);
  String get featureMessage =>
      config.featureText.isNotEmpty ? config.featureText : 'This feature is temporarily unavailable.';

  void dismissAnnouncement() {
    _seenAnn = config.annId;
    _save();
    notifyListeners();
  }

  void later() {
    _softHidden = true;
    _laterVersion = config.latestVersion;
    _save();
    notifyListeners();
  }

  /// Opens the Play Store page of the app (the Play Store app first, then the web page).
  Future<void> openStore() async {
    final custom = config.playUrl;
    final id = packageName;
    final targets = <Uri>[
      if (custom.isNotEmpty) Uri.parse(custom) else Uri.parse('market://details?id=$id'),
      Uri.parse('https://play.google.com/store/apps/details?id=$id'),
    ];
    for (final u in targets) {
      try {
        if (await launchUrl(u, mode: LaunchMode.externalApplication)) return;
      } catch (_) {}
    }
  }
}

/// Wraps the whole app: shows the blocking, update and announcement screens when the control
/// file asks for them, and checks the file again when the app comes back to the front.
class AppControlGate extends StatefulWidget {
  const AppControlGate({super.key, required this.child});
  final Widget child;

  @override
  State<AppControlGate> createState() => _AppControlGateState();
}

class _AppControlGateState extends State<AppControlGate> with WidgetsBindingObserver {
  final ctl = AppControl.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ctl.start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) ctl.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ctl,
      builder: (context, _) {
        final blocked = ctl.blockedTitle;
        return Stack(
          fit: StackFit.expand,
          children: [
            widget.child,
            if (blocked != null)
              Positioned.fill(child: _Blocked(title: blocked, text: ctl.blockedText, update: ctl.forceUpdate, ctl: ctl))
            else ...[
              if (ctl.annPending) Positioned.fill(child: _Announcement(ctl: ctl)),
              if (ctl.softUpdate) Positioned(left: 12, right: 12, top: 0, child: _SoftUpdate(ctl: ctl)),
            ],
          ],
        );
      },
    );
  }
}

class _Blocked extends StatelessWidget {
  const _Blocked({required this.title, required this.text, required this.update, required this.ctl});
  final String title;
  final String text;
  final bool update;
  final AppControl ctl;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF0E0B1E),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(update ? Icons.system_update : Icons.pause_circle_outline, size: 64, color: KColors.gold),
                const SizedBox(height: 18),
                Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14.5, height: 1.4)),
                const SizedBox(height: 24),
                if (update)
                  FilledButton.icon(
                    onPressed: ctl.openStore,
                    icon: const Icon(Icons.shop_outlined),
                    label: const Text('Update on Google Play'),
                  )
                else
                  OutlinedButton(
                    onPressed: ctl.checking ? null : () => ctl.refresh(force: true),
                    child: Text(ctl.checking ? 'Checking...' : 'Try again'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Announcement extends StatelessWidget {
  const _Announcement({required this.ctl});
  final AppControl ctl;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xB3000000),
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(28),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: KColors.surface, borderRadius: BorderRadius.circular(20)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (ctl.config.annTitle.isNotEmpty)
                Text(ctl.config.annTitle, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              if (ctl.config.annTitle.isNotEmpty) const SizedBox(height: 8),
              Flexible(
                child: SingleChildScrollView(
                  child: Text(ctl.config.annText, style: const TextStyle(fontSize: 14.5, height: 1.4)),
                ),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(onPressed: ctl.dismissAnnouncement, child: const Text('OK')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SoftUpdate extends StatelessWidget {
  const _SoftUpdate({required this.ctl});
  final AppControl ctl;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Material(
        color: KColors.selected,
        elevation: 6,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  ctl.config.updateText.isNotEmpty ? ctl.config.updateText : 'A new version is available.',
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                ),
              ),
              TextButton(onPressed: ctl.openStore, child: const Text('Update', style: TextStyle(color: Colors.white))),
              TextButton(onPressed: ctl.later, child: const Text('Later', style: TextStyle(color: Colors.white70))),
            ],
          ),
        ),
      ),
    );
  }
}

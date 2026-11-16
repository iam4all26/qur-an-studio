import 'package:flutter/material.dart';

import '../quran/about_screen.dart';

import '../app_state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'scene_test_screen.dart';

class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key});

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  final ScrollController _scroll = ScrollController();
  final List<GlobalKey> _keys = List.generate(4, (_) => GlobalKey());
  int _tab = 0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _go(int index) {
    setState(() => _tab = index);
    final ctx = _keys[index].currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 250), alignment: 0.0);
    }
  }

  Widget _card({
    required Key key,
    required IconData icon,
    required String title,
    String? help,
    required Widget child,
  }) {
    return Container(
      key: key,
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1938),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: KColors.selected.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: Colors.white, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              ),
              if (help != null) HelpIcon(help, title: title),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _choice({
    required bool on,
    required VoidCallback onTap,
    required Widget child,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: on ? const Color(0xFF7351FF) : const Color(0xFF1F1840),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: on ? const Color(0xFF7351FF) : const Color(0xFF30265A), width: on ? 2 : 1),
        ),
        child: child,
      ),
    );
  }

  Widget _segment(String label, bool on, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? const Color(0xFF7351FF) : const Color(0xFF1F1840),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF30265A)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700), textAlign: TextAlign.center)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final settings = state.settings;
    const tabs = <(IconData, String)>[
      (Icons.settings_outlined, 'General'),
      (Icons.file_download_outlined, 'Export'),
      (Icons.code, 'Tools'),
      (Icons.info_outline, 'About'),
    ];

    return SafeArea(
      child: ListView(
        controller: _scroll,
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Settings', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1938),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  for (var i = 0; i < tabs.length; i++)
                    InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => _go(i),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: _tab == i ? const Color(0xFF7351FF) : Colors.transparent,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            Icon(tabs[i].$1, size: 20),
                            const SizedBox(width: 8),
                            Text(tabs[i].$2, style: const TextStyle(fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          _card(
            key: _keys[0],
            icon: Icons.stay_current_portrait,
            title: 'App Layout',
            child: Column(
              children: [
                _choice(
                  on: !settings.landscape,
                  onTap: () => state.updateSettings(settings.copyWith(orientation: 'portrait')),
                  child: Row(
                    children: [
                      const Icon(Icons.stay_current_portrait, size: 36),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Portrait', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                            Text('Tall, phone style', style: TextStyle(color: Color(0xFFB5ABD6))),
                          ],
                        ),
                      ),
                      Icon(!settings.landscape ? Icons.circle : Icons.circle_outlined),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                _choice(
                  on: settings.landscape,
                  onTap: () => state.updateSettings(settings.copyWith(orientation: 'landscape')),
                  child: Row(
                    children: [
                      const Icon(Icons.stay_current_landscape, size: 36),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Landscape', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                            Text('Wide, video style', style: TextStyle(color: Color(0xFFB5ABD6))),
                          ],
                        ),
                      ),
                      Icon(settings.landscape ? Icons.circle : Icons.circle_outlined),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _card(
            key: _keys[1],
            icon: Icons.play_circle_outline,
            title: 'Export Defaults',
            help: 'The starting choices for every new export. You can still change quality, frame rate and bitrate on the export page of each video.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Video Size (Resolution)', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _segment('1280 x 720', settings.videoHeight == 720,
                        () => state.updateSettings(settings.copyWith(videoHeight: 720))),
                    const SizedBox(width: 8),
                    _segment('1920 x 1080', settings.videoHeight == 1080,
                        () => state.updateSettings(settings.copyWith(videoHeight: 1080))),
                  ],
                ),
                const SizedBox(height: 14),
                const Text('Frame Rate', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _segment('24 per second', settings.frameRate == 24,
                        () => state.updateSettings(settings.copyWith(frameRate: 24))),
                    const SizedBox(width: 8),
                    _segment('30 per second', settings.frameRate == 30,
                        () => state.updateSettings(settings.copyWith(frameRate: 30))),
                  ],
                ),
              ],
            ),
          ),
          _card(
            key: _keys[2],
            icon: Icons.code,
            title: 'Tools',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.movie_creation_outlined),
              title: const Text('Export Test'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const SceneTestScreen()),
              ),
            ),
          ),
          _card(
            key: _keys[3],
            icon: Icons.info_outline,
            title: "About Qur'an Studio",
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Version 1.0.0. Works offline. Projects stay on this phone.'),
              subtitle: const Text('Credits and licences'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const AboutScreen()),
              ),
            ),
          ),
          if (state.loadError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(state.loadError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
        ],
      ),
    );
  }
}

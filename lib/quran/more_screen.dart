import 'package:flutter/material.dart';

import '../app_state.dart';
import '../theme.dart';
import 'about_screen.dart';
import 'reciters_screen.dart';
import 'resources_screen.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  Widget _nav(BuildContext context, IconData icon, String title, String sub, Widget page) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(sub),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page)),
      ),
    );
  }

  Widget _seg(String label, bool on, VoidCallback tap) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: tap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? KColors.selected : KColors.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final s = state.settings;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          const Text('More', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          _nav(context, Icons.cloud_download_outlined, 'Resources',
              "Qur'an text, translations, reciter list and font", const ResourcesScreen()),
          _nav(context, Icons.mic_none, 'Reciters', 'Favorites, downloads and your own audio',
              const RecitersScreen()),
          _nav(context, Icons.info_outline, 'About and credits', 'Sources and licences',
              const AboutScreen()),
          const SizedBox(height: 16),
          const Text('Export defaults', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text(
            'Starting choices for each export. You can still change them on the export page.',
            style: TextStyle(fontSize: 12, color: KColors.accent),
          ),
          const SizedBox(height: 10),
          const Text('Video size', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Row(
            children: [
              _seg('720p', s.videoHeight == 720, () => state.updateSettings(s.copyWith(videoHeight: 720))),
              const SizedBox(width: 8),
              _seg('1080p', s.videoHeight == 1080, () => state.updateSettings(s.copyWith(videoHeight: 1080))),
            ],
          ),
          const SizedBox(height: 12),
          const Text('Frame rate', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Row(
            children: [
              _seg('24 fps', s.frameRate == 24, () => state.updateSettings(s.copyWith(frameRate: 24))),
              const SizedBox(width: 8),
              _seg('30 fps', s.frameRate == 30, () => state.updateSettings(s.copyWith(frameRate: 30))),
            ],
          ),
          const SizedBox(height: 16),
          const Text('App layout', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Row(
            children: [
              _seg('Portrait', !s.landscape, () => state.updateSettings(s.copyWith(orientation: 'portrait'))),
              const SizedBox(width: 8),
              _seg('Landscape', s.landscape, () => state.updateSettings(s.copyWith(orientation: 'landscape'))),
            ],
          ),
          if (state.loadError != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(state.loadError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
        ],
      ),
    );
  }
}

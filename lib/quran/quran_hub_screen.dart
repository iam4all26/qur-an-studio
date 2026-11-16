import 'package:flutter/material.dart';

import 'phase0_screen.dart';
import 'resources_screen.dart';

/// Temporary tab that holds the Qur'an tools until the Phase 1 home screen
/// replaces it.
class QuranHubScreen extends StatelessWidget {
  const QuranHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Qur'an Studio")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.cloud_download_outlined),
              title: const Text('Resources'),
              subtitle: const Text('Download and verify Qur\'an data, translations, reciters, font'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ResourcesScreen()),
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.science_outlined),
              title: const Text('Phase 0 test'),
              subtitle: const Text('Build one verse video'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const Phase0Screen()),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import 'quran_library_screen.dart';
import 'reciters_screen.dart';
import 'sync_studio_screen.dart';

/// The Library tab: the Qur'an, the reciters and the sync studio.
class QuranHubScreen extends StatelessWidget {
  const QuranHubScreen({super.key});

  Widget _item(BuildContext context, IconData icon, String title, String sub, Widget page) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(sub),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Library')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _item(context, Icons.menu_book_outlined, "Qur'an", 'Browse 114 surahs and choose verses',
              const QuranLibraryScreen()),
          _item(context, Icons.mic_none, 'Reciters', 'Favorites, downloads and your own audio',
              const RecitersScreen()),
          _item(context, Icons.graphic_eq, 'Sync my recording', 'Mark each verse in your own audio',
              const SyncStudioScreen()),
        ],
      ),
    );
  }
}

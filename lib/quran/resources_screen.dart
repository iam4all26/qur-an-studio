import 'package:flutter/material.dart';

import 'quran_db.dart';
import 'resource_manager.dart';

class ResourcesScreen extends StatefulWidget {
  const ResourcesScreen({super.key});

  @override
  State<ResourcesScreen> createState() => _ResourcesScreenState();
}

class _ResourcesScreenState extends State<ResourcesScreen> {
  final rm = ResourceManager.instance;
  String? _check;

  @override
  void initState() {
    super.initState();
    rm.addListener(_tick);
    rm.load().then((_) {
      if (rm.catalog.isEmpty) rm.refreshCatalog();
    });
  }

  @override
  void dispose() {
    rm.removeListener(_tick);
    super.dispose();
  }

  void _tick() {
    if (mounted) setState(() {});
  }

  String _size(int b) {
    if (b >= 1024 * 1024) return '${(b / 1048576).toStringAsFixed(1)} MB';
    if (b >= 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
    return '$b B';
  }

  String _label(ResourceEntry e) {
    switch (e.id) {
      case 'quran':
        return "Qur'an text (6,236 verses)";
      case 'en_sahih':
        return 'English: Sahih International';
      case 'ha_gumi':
        return 'Hausa: Abu Bakr Gumi';
      case 'reciters':
        return 'Reciter list';
      default:
        return e.family != null ? 'Font: ${e.family}' : e.id;
    }
  }

  Future<void> _verify() async {
    await rm.loadFonts();
    final db = await QuranDb.open();
    if (db == null) {
      setState(() => _check = "Qur'an text is not downloaded yet.");
      return;
    }
    final problem = await db.selfCheck();
    setState(() => _check = problem ?? 'Check passed: 114 surahs, 6,236 verses.');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Resources')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'The Qur\'an text, translations, reciter list and font are downloaded once '
            'and then work offline. Each file is checked against its SHA-256 before it is saved.',
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: rm.busy ? null : rm.downloadAll,
                  child: const Text('Download all'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: rm.busy ? null : rm.refreshCatalog,
                child: const Text('Check for updates'),
              ),
            ],
          ),
          if (rm.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(rm.error!, style: TextStyle(color: scheme.error)),
            ),
          const SizedBox(height: 12),
          if (rm.catalog.isEmpty && rm.busy) const LinearProgressIndicator(),
          for (final e in rm.catalog) _row(e, scheme),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: _verify, child: const Text('Verify data')),
          if (_check != null)
            Padding(padding: const EdgeInsets.only(top: 8), child: Text(_check!)),
          const SizedBox(height: 20),
          const Text(
            "Credits: Qur'an text from the Tanzil Project (tanzil.net), unmodified. "
            'English translation: Sahih International via Tanzil. '
            'Hausa translation from QuranEnc.com (version 1.2.2). '
            'Font: Amiri Quran (SIL Open Font Licence). '
            'Recitations belong to their reciters and are downloaded on the phone.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _row(ResourceEntry e, ColorScheme scheme) {
    final st = rm.stateOf(e);
    final p = rm.progress[e.id];
    final status = switch (st) {
      ResourceState.ready => 'Ready',
      ResourceState.outdated => 'Update available',
      ResourceState.missing => 'Not downloaded',
    };
    return Card(
      child: ListTile(
        title: Text(_label(e)),
        subtitle: p != null
            ? Padding(
                padding: const EdgeInsets.only(top: 6),
                child: LinearProgressIndicator(value: p),
              )
            : Text('${_size(e.sizeBytes)}  -  $status'),
        trailing: st == ResourceState.ready
            ? Icon(Icons.check_circle, color: scheme.primary)
            : TextButton(
                onPressed: rm.busy ? null : () => rm.download(e),
                child: Text(st == ResourceState.outdated ? 'Update' : 'Download'),
              ),
      ),
    );
  }
}

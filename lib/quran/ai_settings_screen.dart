import 'package:flutter/material.dart';

import '../theme.dart';
import 'ai_sync.dart';

/// More, AI Auto Sync: the person adds an API key for one or more services and picks which one
/// Auto Sync uses.
class AiSettingsScreen extends StatefulWidget {
  const AiSettingsScreen({super.key});

  @override
  State<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends State<AiSettingsScreen> {
  final cfg = AiConfig.instance;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    cfg.load().then((_) {
      if (mounted) setState(() => _ready = true);
    });
  }

  String _mask(String key) {
    if (key.length <= 8) return '********';
    return '${key.substring(0, 3)}...${key.substring(key.length - 4)}';
  }

  Future<void> _edit(AiProvider p) async {
    final key = TextEditingController(text: cfg.keyOf(p.id));
    final model = TextEditingController(text: cfg.modelOf(p.id));
    final base = TextEditingController(text: cfg.baseOf(p.id));
    var hide = true;
    final saved = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: Text(p.name),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: key,
                  obscureText: hide,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: 'API key',
                    suffixIcon: IconButton(
                      icon: Icon(hide ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setD(() => hide = !hide),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: model,
                  autocorrect: false,
                  decoration: const InputDecoration(labelText: 'Model'),
                ),
                if (p.editableUrl) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: base,
                    autocorrect: false,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(labelText: 'Address, for example https://host/v1'),
                  ),
                ],
                const SizedBox(height: 10),
                const Text(
                  'Model names change over time. If the service says the model is not found, '
                  'type the current name from its website.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    final k = key.text.trim();
    final m = model.text.trim();
    final b = base.text.trim();
    key.dispose();
    model.dispose();
    base.dispose();
    if (saved != true || !mounted) return;
    if (k.isEmpty) {
      await cfg.remove(p.id);
    } else {
      await cfg.set(p.id, key: k, model: m, base: p.editableUrl ? b : '');
    }
    if (mounted) setState(() {});
  }

  Future<void> _remove(AiProvider p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Remove the ${p.name} key?'),
        content: const Text('The key is deleted from this phone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true) return;
    await cfg.remove(p.id);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final active = _ready ? cfg.active : null;
    return Scaffold(
      appBar: AppBar(title: const Text('AI Auto Sync')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Auto Sync listens to your own recording and places the start of every verse for you, in '
            'Library, Sync my recording. Add the API key of an AI service you have an account with.',
            style: TextStyle(fontSize: 13.5),
          ),
          const SizedBox(height: 8),
          const Text(
            'Your key is kept only on this phone, in the app\'s private storage (not encrypted), and is sent '
            'only to the service you choose. The recording is sent to that service when you press Auto Sync, '
            'and the service may charge you for it.',
            style: TextStyle(fontSize: 12, color: KColors.accent),
          ),
          const SizedBox(height: 12),
          for (final p in kAiProviders)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
                        if (_ready && cfg.isReady(p.id))
                          ChoiceChip(
                            label: const Text('In use'),
                            selected: active?.id == p.id,
                            onSelected: (_) async {
                              await cfg.setActive(p.id);
                              if (mounted) setState(() {});
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(p.note, style: const TextStyle(fontSize: 12.5)),
                    const SizedBox(height: 6),
                    if (_ready && cfg.isReady(p.id))
                      Text('Key ${_mask(cfg.keyOf(p.id))}  -  model ${cfg.modelOf(p.id)}',
                          style: const TextStyle(fontSize: 12))
                    else
                      const Text('No key added', style: TextStyle(fontSize: 12)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        OutlinedButton(
                          onPressed: _ready ? () => _edit(p) : null,
                          child: Text(_ready && cfg.keyOf(p.id).isNotEmpty ? 'Change' : 'Add key'),
                        ),
                        if (_ready && cfg.keyOf(p.id).isNotEmpty) ...[
                          const SizedBox(width: 8),
                          TextButton(onPressed: () => _remove(p), child: const Text('Remove')),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
          const Text(
            'Tip: Whisper (OpenAI or Groq) gives the time of each word, so it is the most exact. '
            'The result is a first placement: always play each verse and adjust with Set Start and Set End.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}

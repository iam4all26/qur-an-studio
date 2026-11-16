import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme.dart';
import 'store_service.dart';

const List<(String, String)> _kTypes = [
  ('font', 'Fonts'),
  ('background', 'Backgrounds'),
  ('shape', 'Shapes'),
  ('icon', 'Icons'),
  ('image', 'Images'),
];

class StoreTab extends StatefulWidget {
  const StoreTab({super.key, required this.active, this.showTitle = true});

  /// False when the screen already has its own title bar.
  final bool showTitle;

  /// True while this tab is the one on screen. The store loads the first time.
  final bool active;

  @override
  State<StoreTab> createState() => _StoreTabState();
}

class _StoreTabState extends State<StoreTab> {
  final StoreService _store = StoreService.instance;
  List<StoreItem> _items = [];
  bool _loading = false;
  bool _loaded = false;
  String? _error;
  int _tab = 0;
  String _cat = 'All';
  bool _selecting = false;
  final Set<String> _sel = {};
  final Map<String, double> _progress = {};

  @override
  void initState() {
    super.initState();
    _store.addListener(_changed);
    if (widget.active) _load();
  }

  @override
  void didUpdateWidget(StoreTab old) {
    super.didUpdateWidget(old);
    if (widget.active && !_loaded && !_loading) _load();
  }

  @override
  void dispose() {
    _store.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _store.fetchCatalog();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loaded = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not open the store. Check your internet and the store address.\n$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool> _downloadOne(StoreItem item) async {
    setState(() => _progress[item.id] = 0);
    try {
      await _store.download(item, (p) {
        if (mounted) setState(() => _progress[item.id] = p);
      });
      return true;
    } catch (e) {
      return false;
    } finally {
      if (mounted) setState(() => _progress.remove(item.id));
    }
  }

  Future<void> _download(StoreItem item) async {
    final ok = await _downloadOne(item);
    if (!ok) _snack('Download failed for ${item.name}.');
  }

  Future<void> _downloadSelected() async {
    final todo = _items.where((i) => _sel.contains(i.id) && !_store.isInstalled(i.id)).toList();
    if (todo.isEmpty) {
      setState(() {
        _sel.clear();
        _selecting = false;
      });
      return;
    }
    var failed = 0;
    for (final item in todo) {
      if (!mounted) return;
      if (!await _downloadOne(item)) failed++;
    }
    if (!mounted) return;
    setState(() {
      _sel.clear();
      _selecting = false;
    });
    _snack(failed == 0
        ? 'Downloaded ${todo.length} item${todo.length == 1 ? '' : 's'}.'
        : 'Downloaded ${todo.length - failed}. $failed failed, try those again.');
  }

  Future<void> _editAddress() async {
    final controller = TextEditingController(text: _store.base);
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Store address'),
        content: TextField(
          controller: controller,
          autocorrect: false,
          maxLines: 3,
          minLines: 1,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Save')),
        ],
      ),
    );
    if (saved == true) {
      await _store.setBase(controller.text);
      _loaded = false;
      await _load();
    }
    controller.dispose();
  }

  // ---- pictures ----

  Widget _picture(String source, {required bool network, BoxFit fit = BoxFit.contain}) {
    final lower = source.toLowerCase();
    final fallback = const Center(child: Icon(Icons.image_outlined, color: Color(0xFFB5ABD6)));
    if (lower.endsWith('.svg')) {
      return network
          ? SvgPicture.network(source, fit: fit, placeholderBuilder: (_) => fallback)
          : SvgPicture.file(File(source), fit: fit);
    }
    return network
        ? Image.network(source, fit: fit, errorBuilder: (_, __, ___) => fallback)
        : Image.file(File(source), fit: fit, errorBuilder: (_, __, ___) => fallback);
  }

  /// A picture of the item: the downloaded file when we have it, otherwise the store preview.
  Widget _thumb(StoreItem item, {BoxFit fit = BoxFit.contain}) {
    final installed = _store.installed.where((i) => i.id == item.id).toList();
    if (installed.isNotEmpty && item.type != 'font') {
      return _picture(installed.first.path, network: false, fit: fit);
    }
    final source = item.preview.isNotEmpty ? item.preview : (item.type == 'font' ? '' : item.file);
    if (source.isEmpty) {
      return Center(child: Icon(item.type == 'font' ? Icons.font_download_outlined : Icons.image_outlined));
    }
    return _picture(_store.urlFor(source), network: true, fit: fit);
  }

  String _sizeText(StoreItem item) {
    if (item.sizeKb <= 0) return '';
    return item.sizeKb >= 1024 ? '${(item.sizeKb / 1024).toStringAsFixed(1)} MB' : '${item.sizeKb} KB';
  }

  // ---- preview ----

  Future<void> _openPreview(StoreItem item) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final installed = _store.installed.where((i) => i.id == item.id).toList();
        final isInstalled = installed.isNotEmpty;
        final sample = item.type == 'font' && isInstalled && installed.first.family.isNotEmpty;
        return Dialog(
          backgroundColor: KColors.surface,
          insetPadding: const EdgeInsets.all(18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 240,
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: KColors.lavender, borderRadius: BorderRadius.circular(16)),
                  child: sample
                      ? Center(
                          child: Text(
                            'Aa\nQuran ɓɗƙƴ',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontFamily: installed.first.family, fontSize: 40, color: Colors.white),
                          ),
                        )
                      : _thumb(item),
                ),
                const SizedBox(height: 12),
                Text(item.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(
                  [
                    if (item.category.trim().isNotEmpty) item.category.trim(),
                    _sizeText(item),
                    if (isInstalled) 'Installed',
                  ].where((e) => e.isNotEmpty).join('  -  '),
                  style: const TextStyle(color: Color(0xFFB5ABD6)),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        child: const Text('Close'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: isInstalled
                          ? OutlinedButton(
                              onPressed: () {
                                Navigator.of(dialogContext).pop();
                                _store.remove(item.id);
                              },
                              child: const Text('Remove'),
                            )
                          : FilledButton(
                              onPressed: () {
                                Navigator.of(dialogContext).pop();
                                _download(item);
                              },
                              child: const Text('Download'),
                            ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ---- cards ----

  void _toggle(StoreItem item) {
    setState(() {
      if (!_sel.remove(item.id)) _sel.add(item.id);
      if (_sel.isEmpty) _selecting = false;
    });
  }

  Widget _card(StoreItem item) {
    final installed = _store.isInstalled(item.id);
    final progress = _progress[item.id];
    final picked = _sel.contains(item.id);
    final fg = picked ? Colors.white : KColors.ink;
    final sub = picked ? Colors.white70 : const Color(0xFFB5ABD6);
    final size = _sizeText(item);
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => _selecting ? _toggle(item) : _openPreview(item),
      onLongPress: () {
        if (!_selecting) setState(() => _selecting = true);
        _toggle(item);
      },
      child: Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: picked ? KColors.selected : KColors.surface,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: KColors.lavender, borderRadius: BorderRadius.circular(14)),
                child: ClipRRect(borderRadius: BorderRadius.circular(10), child: _thumb(item)),
              ),
            ),
            const SizedBox(height: 6),
            Text(item.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: fg, height: 1.15)),
            Text(
              [if (size.isNotEmpty) size, if (installed) 'Installed'].join('  -  '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10.5, color: sub),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 32,
              child: progress != null
                  ? Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, value: progress <= 0 ? null : progress),
                      ),
                    )
                  : installed
                      ? OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding: EdgeInsets.zero,
                            shape: const StadiumBorder(),
                            textStyle: const TextStyle(fontSize: 12),
                            foregroundColor: fg,
                            side: BorderSide(color: picked ? Colors.white54 : const Color(0xFF3D3266)),
                          ),
                          onPressed: _selecting ? null : () => _store.remove(item.id),
                          child: const Text('Remove'),
                        )
                      : FilledButton(
                          style: FilledButton.styleFrom(
                            padding: EdgeInsets.zero,
                            shape: const StadiumBorder(),
                            textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                            backgroundColor: picked ? Colors.white : null,
                            foregroundColor: picked ? KColors.selected : null,
                          ),
                          onPressed: _selecting ? null : () => _download(item),
                          child: const Text('Download'),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill(String label, bool on, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: on ? KColors.selected : KColors.surface,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(label,
              style: TextStyle(color: Colors.white, fontWeight: on ? FontWeight.w700 : FontWeight.w500, fontSize: 14)),
        ),
      ),
    );
  }

  List<String> _categories(List<StoreItem> items) {
    const order = ['Hausa Ready', 'Sans Serif', 'Serif', 'Display', 'Handwriting', 'Monospace'];
    final set = <String>{};
    for (final i in items) {
      set.add(i.category.trim().isEmpty ? 'Other' : i.category.trim());
    }
    final keys = set.toList()
      ..sort((a, b) {
        int rank(String k) {
          final i = order.indexOf(k);
          return i >= 0 ? i : (k == 'Other' ? 999 : 100);
        }

        final d = rank(a).compareTo(rank(b));
        return d != 0 ? d : a.compareTo(b);
      });
    return keys;
  }

  String _catOf(StoreItem i) => i.category.trim().isEmpty ? 'Other' : i.category.trim();

  @override
  Widget build(BuildContext context) {
    final type = _kTypes[_tab].$1;
    final ofType = _items.where((i) => i.type == type).toList();
    final cats = _categories(ofType);
    if (_cat != 'All' && !cats.contains(_cat)) _cat = 'All';
    final shown = ofType.where((i) => _cat == 'All' || _catOf(i) == _cat).toList();

    Widget body;
    if (_loading && !_loaded) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 14),
              FilledButton(onPressed: _load, child: const Text('Try again')),
              const SizedBox(height: 8),
              OutlinedButton(onPressed: _editAddress, child: const Text('Store address')),
            ],
          ),
        ),
      );
    } else if (shown.isEmpty) {
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView(children: const [
          SizedBox(height: 120),
          Center(child: Text('Nothing here yet.')),
        ]),
      );
    } else {
      body = RefreshIndicator(
        onRefresh: _load,
        child: GridView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(14, 8, 14, _selecting ? 90 : 16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 0.64,
          ),
          itemCount: shown.length,
          itemBuilder: (context, i) => _card(shown[i]),
        ),
      );
    }

    final selectable = shown.where((i) => !_store.isInstalled(i.id)).toList();
    return SafeArea(
      child: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: widget.showTitle ? const Text('Store', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -0.3)) : const SizedBox.shrink(),
                    ),
                    IconButton(
                      tooltip: _selecting ? 'Cancel selecting' : 'Select several',
                      icon: Icon(_selecting ? Icons.close : Icons.select_all),
                      onPressed: () => setState(() {
                        _selecting = !_selecting;
                        if (!_selecting) _sel.clear();
                      }),
                    ),
                    IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: _load),
                    IconButton(tooltip: 'Store address', icon: const Icon(Icons.link), onPressed: _editAddress),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (var t = 0; t < _kTypes.length; t++)
                        _pill(_kTypes[t].$2, _tab == t, () {
                          setState(() {
                            _tab = t;
                            _cat = 'All';
                            _sel.clear();
                            _selecting = false;
                          });
                        }),
                    ],
                  ),
                ),
              ),
              if (cats.length > 1 || (cats.length == 1 && cats.first != 'Other'))
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _pill('All', _cat == 'All', () => setState(() => _cat = 'All')),
                        for (final c in cats) _pill(c, _cat == c, () => setState(() => _cat = c)),
                      ],
                    ),
                  ),
                ),
              Expanded(child: body),
            ],
          ),
          if (_selecting)
            Positioned(
              left: 14,
              right: 14,
              bottom: 12,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: KColors.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFF3D3266)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('${_sel.length} selected', style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    TextButton(
                      onPressed: selectable.isEmpty
                          ? null
                          : () => setState(() {
                                if (selectable.every((i) => _sel.contains(i.id))) {
                                  _sel.removeAll(selectable.map((i) => i.id));
                                } else {
                                  _sel.addAll(selectable.map((i) => i.id));
                                }
                              }),
                      child: const Text('Select all'),
                    ),
                    const SizedBox(width: 6),
                    FilledButton(
                      onPressed: _sel.isEmpty || _progress.isNotEmpty ? null : _downloadSelected,
                      child: Text('Download (${_sel.length})'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

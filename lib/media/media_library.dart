import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:kainuwa_encoder/kainuwa_encoder.dart';
import 'package:photo_manager/photo_manager.dart';

import '../theme.dart';

enum MediaKind { image, video, audio }

/// Opens the in-app media library and returns the chosen file path, or null.
Future<String?> pickMedia(BuildContext context, MediaKind kind) async {
  final result = await Navigator.of(context).push<Object>(
    MaterialPageRoute<Object>(builder: (_) => MediaLibraryScreen(kind: kind)),
  );
  if (result is String) return result;
  if (result is List<String> && result.isNotEmpty) return result.first;
  return null;
}

/// Like [pickMedia], but the user can select several files (long press, or the select button).
/// Returns an empty list when nothing was chosen.
Future<List<String>> pickMediaMany(BuildContext context, MediaKind kind) async {
  final result = await Navigator.of(context).push<Object>(
    MaterialPageRoute<Object>(builder: (_) => MediaLibraryScreen(kind: kind, multi: true)),
  );
  if (result is List<String>) return result;
  if (result is String) return [result];
  return [];
}

class MediaLibraryScreen extends StatefulWidget {
  const MediaLibraryScreen({super.key, required this.kind, this.multi = false});

  final MediaKind kind;
  final bool multi;

  @override
  State<MediaLibraryScreen> createState() => _MediaLibraryScreenState();
}

class _MediaLibraryScreenState extends State<MediaLibraryScreen> with WidgetsBindingObserver {
  static const int _pageSize = 60;

  final ScrollController _scroll = ScrollController();
  bool _checking = true;
  bool _allowed = false;
  bool _loading = false;
  bool _hasMore = true;
  String _problem = '';
  bool _opening = false;
  bool _selecting = false;
  final List<AssetEntity> _picked = [];
  List<AssetPathEntity> _albums = [];
  AssetPathEntity? _album;
  final List<AssetEntity> _assets = [];
  int _page = 0;
  String? _listenId;
  StreamSubscription<void>? _doneSub;

  RequestType get _type {
    switch (widget.kind) {
      case MediaKind.image:
        return RequestType.image;
      case MediaKind.video:
        return RequestType.video;
      case MediaKind.audio:
        return RequestType.audio;
    }
  }

  String get _title {
    switch (widget.kind) {
      case MediaKind.image:
        return 'Photos';
      case MediaKind.video:
        return 'Videos';
      case MediaKind.audio:
        return 'Audio';
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 600) _loadMore();
    });
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scroll.dispose();
    _doneSub?.cancel();
    if (_listenId != null) {
      KainuwaEncoder.stopAudio().then((_) {}, onError: (_) {});
    }
    super.dispose();
  }

  /// Plays a sound here, before it is added, so it can be heard first. Tap again to stop.
  Future<void> _listen(AssetEntity a) async {
    if (_listenId == a.id) {
      _listenId = null;
      setState(() {});
      try {
        await KainuwaEncoder.stopAudio();
      } catch (_) {}
      return;
    }
    try {
      final file = await a.originFile ?? await a.file;
      if (file == null) {
        _say('That sound could not be played.');
        return;
      }
      _doneSub ??= KainuwaEncoder.playbackDone.listen((_) {
        if (mounted && _listenId != null) setState(() => _listenId = null);
      });
      await KainuwaEncoder.stopAudio();
      await KainuwaEncoder.playAudio(file.path);
      if (mounted) setState(() => _listenId = a.id);
    } catch (_) {
      _say('That sound could not be played.');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back from the permission screen or the phone settings: check again.
    if (state == AppLifecycleState.resumed && !_allowed && !_checking) _start();
  }

  Future<void> _start() async {
    setState(() => _checking = true);
    PermissionState state;
    try {
      state = await PhotoManager.requestPermissionExtend(
        requestOption: PermissionRequestOption(
          androidPermission: AndroidPermission(type: RequestType.all, mediaLocation: false),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _allowed = false;
      });
      return;
    }
    if (!mounted) return;
    if (!state.hasAccess) {
      setState(() {
        _checking = false;
        _allowed = false;
      });
      return;
    }
    List<AssetPathEntity> albums = [];
    try {
      albums = await PhotoManager.getAssetPathList(
        type: _type,
        onlyAll: false,
        // Without a sort order, old Android phones reject the request ("ORDER BY LIMIT").
        filterOption: FilterOptionGroup(
          orders: [const OrderOption(type: OrderOptionType.createDate, asc: false)],
        ),
      );
    } catch (_) {
      albums = [];
    }
    if (!mounted) return;
    setState(() {
      _checking = false;
      _allowed = true;
      _albums = albums;
    });
    if (albums.isNotEmpty) await _selectAlbum(albums.first);
  }

  Future<void> _selectAlbum(AssetPathEntity album) async {
    setState(() {
      _album = album;
      _assets.clear();
      _page = 0;
      _hasMore = true;
    });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    final album = _album;
    if (album == null || _loading || !_hasMore) return;
    _loading = true;
    try {
      var list = <AssetEntity>[];
      try {
        list = await album.getAssetListPaged(page: _page, size: _pageSize);
      } catch (e) {
        _problem = 'Listing failed: $e';
      }
      if (list.isEmpty && _page == 0) {
        // Some phones answer the paged request with nothing: ask for a range instead.
        try {
          list = await album.getAssetListRange(start: 0, end: _pageSize);
          if (list.isNotEmpty) _problem = '';
        } catch (e) {
          _problem = 'Listing failed: $e';
        }
      }
      if (list.isEmpty && _page == 0 && _problem.isEmpty) {
        int count = -1;
        try {
          count = await album.assetCountAsync;
        } catch (_) {}
        _problem = 'The album says it has $count item(s) but none could be listed.';
      }
      if (!mounted || album != _album) return;
      setState(() {
        _assets.addAll(list);
        _page += 1;
        _hasMore = list.length == _pageSize;
      });
    } catch (_) {
      if (mounted) setState(() => _hasMore = false);
    } finally {
      _loading = false;
    }
  }

  void _toggle(AssetEntity a) {
    setState(() {
      final i = _picked.indexWhere((x) => x.id == a.id);
      if (i >= 0) {
        _picked.removeAt(i);
      } else {
        _picked.add(a);
      }
    });
  }

  void _tapAsset(AssetEntity a) {
    if (widget.multi && (_selecting || _picked.isNotEmpty)) {
      _toggle(a);
    } else {
      _choose(a);
    }
  }

  void _holdAsset(AssetEntity a) {
    if (!widget.multi) return;
    setState(() => _selecting = true);
    if (!_picked.any((x) => x.id == a.id)) _toggle(a);
  }

  Future<void> _finishMany() async {
    if (_opening || _picked.isEmpty) return;
    setState(() => _opening = true);
    try {
      final paths = <String>[];
      for (final a in _picked) {
        final file = await a.originFile ?? await a.file;
        if (file != null) paths.add(file.path);
      }
      if (!mounted) return;
      if (paths.isEmpty) {
        _say('Those files could not be opened.');
        return;
      }
      Navigator.of(context).pop(paths);
    } catch (_) {
      _say('Those files could not be opened.');
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _choose(AssetEntity asset) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final file = await asset.originFile ?? await asset.file;
      if (!mounted) return;
      if (file == null) {
        _say('That file could not be opened.');
        return;
      }
      Navigator.of(context).pop(widget.multi ? <String>[file.path] : file.path);
    } catch (_) {
      _say('That file could not be opened.');
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _systemPicker() async {
    try {
      String? path;
      switch (widget.kind) {
        case MediaKind.image:
          path = await KainuwaEncoder.pickImage();
          break;
        case MediaKind.video:
          path = await KainuwaEncoder.pickVideo();
          break;
        case MediaKind.audio:
          path = await KainuwaEncoder.pickAudio();
          break;
      }
      if (path != null && mounted) Navigator.of(context).pop(widget.multi ? <String>[path] : path);
    } catch (_) {
      // The system picker was closed.
    }
  }

  void _say(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  String _clock(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  Widget _albumMenu() {
    final album = _album;
    if (album == null) return const SizedBox.shrink();
    return PopupMenuButton<AssetPathEntity>(
      onSelected: _selectAlbum,
      itemBuilder: (_) => [
        for (final a in _albums) PopupMenuItem<AssetPathEntity>(value: a, child: Text(a.name)),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(album.name, style: const TextStyle(fontWeight: FontWeight.w700)),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }

  Widget _message(String text, {bool settings = false}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            if (settings)
              FilledButton(
                onPressed: _start,
                child: const Text('Try again'),
              ),
            if (settings) const SizedBox(height: 8),
            if (settings)
              OutlinedButton(
                onPressed: () => PhotoManager.openSetting(),
                child: const Text('Open app settings'),
              ),
            if (settings) const SizedBox(height: 8),
            OutlinedButton(onPressed: _systemPicker, child: const Text('Browse other files')),
          ],
        ),
      ),
    );
  }

  Widget _grid() {
    final audio = widget.kind == MediaKind.audio;
    if (audio) {
      return ListView.builder(
        controller: _scroll,
        itemCount: _assets.length,
        itemBuilder: (context, i) {
          final a = _assets[i];
          return ListTile(
            leading: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _listen(a),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _listenId == a.id ? KColors.purple : KColors.lavender,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _listenId == a.id ? Icons.stop : Icons.play_arrow,
                  color: Colors.white,
                ),
              ),
            ),
            title: Text(a.title ?? 'Audio', maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(_clock(a.duration)),
            selected: _picked.any((x) => x.id == a.id),
            selectedTileColor: const Color(0x33A78BFA),
            trailing: _picked.any((x) => x.id == a.id)
                ? CircleAvatar(
                    radius: 13,
                    backgroundColor: KColors.purple,
                    child: Text('${_picked.indexWhere((x) => x.id == a.id) + 1}',
                        style: const TextStyle(color: Colors.white, fontSize: 12)),
                  )
                : null,
            onTap: () => _tapAsset(a),
            onLongPress: () => _holdAsset(a),
          );
        },
      );
    }
    return GridView.builder(
      controller: _scroll,
      padding: const EdgeInsets.all(4),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemCount: _assets.length,
      itemBuilder: (context, i) {
        final a = _assets[i];
        final order = _picked.indexWhere((x) => x.id == a.id);
        return InkWell(
          onTap: () => _tapAsset(a),
          onLongPress: () => _holdAsset(a),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _Thumb(asset: a),
              if (order >= 0)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0x44A78BFA),
                      border: Border.all(color: KColors.purple, width: 3),
                    ),
                  ),
                ),
              if (order >= 0)
                Positioned(
                  left: 6,
                  top: 6,
                  child: CircleAvatar(
                    radius: 12,
                    backgroundColor: KColors.purple,
                    child: Text('${order + 1}', style: const TextStyle(color: Colors.white, fontSize: 12)),
                  ),
                ),
              if (widget.kind == MediaKind.video)
                Positioned(
                  right: 4,
                  bottom: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xAA000000),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(_clock(a.duration), style: const TextStyle(fontSize: 11, color: Colors.white)),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (_checking) {
      body = const Center(child: CircularProgressIndicator());
    } else if (!_allowed) {
      body = _message(
        'Allow access to your media so Kainuwa Studio can show your files here.',
        settings: true,
      );
    } else if (_assets.isEmpty && !_loading && !_hasMore) {
      body = _message(_problem.isEmpty ? 'Nothing found here.' : 'Nothing found here.\n\n$_problem');
    } else {
      body = _grid();
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(_picked.isEmpty ? _title : '${_picked.length} selected'),
        actions: [
          if (widget.multi)
            IconButton(
              tooltip: 'Select several',
              icon: Icon(_selecting ? Icons.close : Icons.select_all),
              onPressed: () => setState(() {
                _selecting = !_selecting;
                if (!_selecting) _picked.clear();
              }),
            ),
          if (_allowed) _albumMenu(),
          IconButton(
            tooltip: 'Browse other files',
            icon: const Icon(Icons.folder_open_outlined),
            onPressed: _systemPicker,
          ),
        ],
        bottom: _opening
            ? const PreferredSize(
                preferredSize: Size.fromHeight(3),
                child: LinearProgressIndicator(minHeight: 3),
              )
            : null,
      ),
      body: body,
      bottomNavigationBar: _picked.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  onPressed: _finishMany,
                  icon: const Icon(Icons.add),
                  label: Text('Add ${_picked.length} ${_picked.length == 1 ? 'file' : 'files'}'),
                ),
              ),
            ),
    );
  }
}

class _Thumb extends StatefulWidget {
  const _Thumb({required this.asset});

  final AssetEntity asset;

  @override
  State<_Thumb> createState() => _ThumbState();
}

class _ThumbState extends State<_Thumb> {
  late final Future<Uint8List?> _data =
      widget.asset.thumbnailDataWithSize(const ThumbnailSize(240, 240));

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _data,
      builder: (context, snap) {
        final bytes = snap.data;
        if (bytes == null) return const ColoredBox(color: Color(0xFF241C48));
        return Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true);
      },
    );
  }
}

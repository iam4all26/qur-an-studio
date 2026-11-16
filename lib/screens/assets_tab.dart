import 'package:flutter/material.dart';

import '../data/asset_catalog.dart';
import '../theme.dart';

class AssetsTab extends StatelessWidget {
  const AssetsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: DefaultTabController(
        length: 9,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Assets',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                ),
              ),
            ),
            const TabBar(
              isScrollable: true,
              tabs: [
                Tab(text: 'Backgrounds'),
                Tab(text: 'Icons'),
                Tab(text: 'Illustrations'),
                Tab(text: 'Social media'),
                Tab(text: 'Developer'),
                Tab(text: 'Languages'),
                Tab(text: 'Crypto'),
                Tab(text: 'Apps and stores'),
                Tab(text: 'Payments'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _AssetGrid(items: allBackgrounds(), columns: 2, aspect: 16 / 11, kind: _Kind.photo),
                  _AssetGrid(items: allIcons(), columns: 4, aspect: 0.85, kind: _Kind.png),
                  _AssetGrid(items: kIllustrations, columns: 3, aspect: 0.9, kind: _Kind.png),
                  _AssetGrid(items: kSocialIcons, columns: 4, aspect: 0.85, kind: _Kind.png),
                  _AssetGrid(items: kDeveloperIcons, columns: 4, aspect: 0.85, kind: _Kind.png),
                  _AssetGrid(items: kLanguageIcons, columns: 4, aspect: 0.85, kind: _Kind.png),
                  _AssetGrid(items: kCryptoIcons, columns: 4, aspect: 0.85, kind: _Kind.png),
                  _AssetGrid(items: kAppIcons, columns: 4, aspect: 0.85, kind: _Kind.png),
                  _AssetGrid(items: kPaymentIcons, columns: 4, aspect: 0.85, kind: _Kind.png),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _Kind { photo, png }

class _AssetGrid extends StatelessWidget {
  const _AssetGrid({
    required this.items,
    required this.columns,
    required this.aspect,
    required this.kind,
  });

  final List<CatalogItem> items;
  final int columns;
  final double aspect;
  final _Kind kind;

  Widget _picture(CatalogItem item, {double? size}) {
    switch (kind) {
      case _Kind.png:
        return SizedBox(width: size, height: size, child: catalogImage(item));
      case _Kind.photo:
        return SizedBox(width: size, child: catalogImage(item, fit: BoxFit.cover));
    }
  }

  void _preview(BuildContext context, CatalogItem item) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: kind == _Kind.photo
                      ? catalogImage(item)
                      : _picture(item, size: 220),
                ),
              ),
              const SizedBox(height: 12),
              Text(item.name, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        childAspectRatio: aspect,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _preview(context, item),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1E1938),
              borderRadius: BorderRadius.circular(16),
            ),
            padding: const EdgeInsets.all(6),
            child: Column(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox.expand(
                      child: kind == _Kind.photo
                          ? catalogImage(item, fit: BoxFit.cover, cacheWidth: 480)
                          : Padding(
                              padding: const EdgeInsets.all(4),
                              child: _picture(item),
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

import '../editor/side_sheet.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme.dart';
import 'store_service.dart';

/// Shapes, icons and images downloaded from the store, in category tabs. Returns the chosen item.
Future<InstalledItem?> showStoreGraphicsSheet(BuildContext context) {
  final items = [
    ...StoreService.instance.ofType('shape'),
    ...StoreService.instance.ofType('icon'),
    ...StoreService.instance.ofType('image'),
  ];
  return showEditorSheet<InstalledItem>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => _GraphicsSheet(items: items),
  );
}

class _GraphicsSheet extends StatefulWidget {
  const _GraphicsSheet({required this.items});

  final List<InstalledItem> items;

  @override
  State<_GraphicsSheet> createState() => _GraphicsSheetState();
}

class _GraphicsSheetState extends State<_GraphicsSheet> {
  String _cat = 'All';

  String _catOf(InstalledItem i) => i.category.trim().isEmpty ? 'Other' : i.category.trim();

  Widget _pill(String label, bool on, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: on ? KColors.selected : KColors.lavender,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(label,
              style: TextStyle(color: on ? Colors.white : KColors.ink, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }

  Widget _picture(InstalledItem item) {
    if (item.path.toLowerCase().endsWith('.svg')) {
      return SvgPicture.file(
        File(item.path),
        fit: BoxFit.contain,
        colorFilter: item.type == 'icon' ? const ColorFilter.mode(Colors.white, BlendMode.srcIn) : null,
      );
    }
    return Image.file(File(item.path), fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const Icon(Icons.image_outlined));
  }

  @override
  Widget build(BuildContext context) {
    final cats = widget.items.map(_catOf).toSet().toList()..sort();
    final shown = widget.items.where((i) => _cat == 'All' || _catOf(i) == _cat).toList();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('From the store', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            if (widget.items.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('Download shapes, icons and images from the Store tab first.'),
              )
            else ...[
              if (cats.length > 1)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    _pill('All', _cat == 'All', () => setState(() => _cat = 'All')),
                    for (final c in cats) _pill(c, _cat == c, () => setState(() => _cat = c)),
                  ]),
                ),
              const SizedBox(height: 12),
              Flexible(
                child: GridView.builder(
                  shrinkWrap: true,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                  ),
                  itemCount: shown.length,
                  itemBuilder: (context, i) {
                    final item = shown[i];
                    return InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => Navigator.of(context).pop(item),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: KColors.lavender,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          children: [
                            Expanded(child: _picture(item)),
                            const SizedBox(height: 4),
                            Text(item.name,
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

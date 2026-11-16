import 'package:flutter/material.dart';

/// Shared state for the landscape side panel. The editor listens to [inset] and
/// leaves that much room on the right while a panel is open.
class EditorSide {
  static final ValueNotifier<double> inset = ValueNotifier<double>(0);

  /// Distance from the top of the screen to the bottom of the header (set by the editor).
  static double top = 0;
}

/// Same as showModalBottomSheet in portrait. In landscape the sheet opens as a panel on the
/// right, under the header, so the canvas and the timeline stay visible and are resized to fit.
Future<T?> showEditorSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  Color? backgroundColor,
  Color? barrierColor,
  bool showDragHandle = false,
}) async {
  final mq = MediaQuery.of(context);
  if (mq.orientation != Orientation.landscape) {
    return showModalBottomSheet<T>(
      context: context,
      builder: builder,
      isScrollControlled: isScrollControlled,
      backgroundColor: backgroundColor,
      barrierColor: barrierColor,
      showDragHandle: showDragHandle,
    );
  }
  final width = (mq.size.width * 0.36).clamp(300.0, 460.0).toDouble() + mq.padding.right;
  final top = EditorSide.top;
  EditorSide.inset.value = width;
  try {
    return await showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (ctx, a, b) => Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: EdgeInsets.only(top: top),
          child: Builder(
            builder: (c) => SizedBox(
              width: width,
              height: mq.size.height - top - MediaQuery.of(c).viewInsets.bottom,
              child: Material(
                color: const Color(0xFF16122B),
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    border: Border(left: BorderSide(color: Color(0x1FFFFFFF))),
                  ),
                  child: Builder(builder: builder),
                ),
              ),
            ),
          ),
        ),
      ),
      transitionBuilder: (ctx, anim, secondary, child) => SlideTransition(
        position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
            .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
        child: child,
      ),
    );
  } finally {
    EditorSide.inset.value = 0;
  }
}

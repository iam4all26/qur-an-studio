import 'package:flutter/foundation.dart';

import 'models.dart';

/// What a Pro subscription unlocks. The gates are already built into the app; they stay open for
/// everyone while [Pro.enforced] is false. To start charging: set enforced to true, connect
/// Google Play Billing (a subscription product, for example qs_pro_monthly) in [Pro.refresh]
/// and [Pro.buy], and have the server or Play confirm the purchase before [owned] is set.
enum ProFeature {
  removeWatermark,
  customWatermark,
  removeOutro,
  premiumReciters,
}

class Pro extends ChangeNotifier {
  Pro._();
  static final Pro instance = Pro._();

  /// Turn on when Pro is ready to be sold. While false every feature is free for everyone.
  static const bool enforced = false;

  bool _owned = false;

  /// True when the person has an active Pro subscription (set from Play Billing).
  bool get owned => _owned;

  bool has(ProFeature f) => !enforced || _owned;

  /// Reads the active subscription from Google Play. Not connected yet.
  Future<void> refresh() async {}

  /// Starts the Google Play subscription flow. Not connected yet; returns whether it succeeded.
  Future<bool> buy() async => false;

  /// The watermark to draw: without Pro it is always on with the default text, and cannot be
  /// removed or changed.
  Watermark watermarkFor(Watermark chosen) {
    if (has(ProFeature.removeWatermark) && has(ProFeature.customWatermark)) return chosen;
    return const Watermark(on: true);
  }
}

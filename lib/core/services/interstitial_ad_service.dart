import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'ad_service.dart';

/// Manages loading and showing a full-screen Interstitial (video) ad.
///
/// Usage:
///   1. Call `preload()` as early as possible (e.g. when transfer starts).
///   2. Call `show()` when the transfer is complete.
///
/// The ad is automatically re-preloaded after it is shown so it's ready for
/// the next transfer session.
class InterstitialAdService {
  InterstitialAdService._();
  static final InterstitialAdService instance = InterstitialAdService._();

  InterstitialAd? _interstitialAd;
  bool _isAdReady = false;

  /// Pre-load the interstitial so it shows instantly when called.
  void preload() {
    if (kIsWeb || !AdService.instance.adsEnabled) return;

    InterstitialAd.load(
      adUnitId: AdService.instance.interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _isAdReady = true;
          debugPrint('✅ [InterstitialAd] Loaded and ready.');

          _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              _interstitialAd = null;
              _isAdReady = false;
              // Preload the next one for the next transfer.
              preload();
              debugPrint('🔄 [InterstitialAd] Dismissed — preloading next.');
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              ad.dispose();
              _interstitialAd = null;
              _isAdReady = false;
              debugPrint('❌ [InterstitialAd] Failed to show: $error');
            },
          );
        },
        onAdFailedToLoad: (error) {
          _isAdReady = false;
          debugPrint('❌ [InterstitialAd] Failed to load: $error');
        },
      ),
    );
  }

  /// Show the interstitial ad if it is ready and ads are enabled.
  /// Returns true if the ad was shown, false otherwise.
  bool show() {
    if (kIsWeb || !AdService.instance.adsEnabled || !_isAdReady || _interstitialAd == null) {
      debugPrint('ℹ️ [InterstitialAd] Not ready or ads disabled — skipping.');
      return false;
    }
    _interstitialAd!.show();
    _isAdReady = false;
    debugPrint('📢 [InterstitialAd] Showing interstitial.');
    return true;
  }
}

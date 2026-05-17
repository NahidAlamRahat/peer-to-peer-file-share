// Mobile (Android/iOS) real InterstitialAdService.
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'ad_service.dart';

class InterstitialAdService {
  InterstitialAdService._();
  static final InterstitialAdService instance = InterstitialAdService._();

  InterstitialAd? _interstitialAd;
  bool _isAdReady = false;

  void preload() {
    if (!AdService.instance.adsEnabled) return;

    InterstitialAd.load(
      adUnitId: AdService.instance.interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _isAdReady = true;
          debugPrint('✅ [InterstitialAd] Loaded and ready.');

          _interstitialAd!.fullScreenContentCallback =
              FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              _interstitialAd = null;
              _isAdReady = false;
              preload(); // preload next one
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

  bool show() {
    if (!AdService.instance.adsEnabled || !_isAdReady || _interstitialAd == null) {
      return false;
    }
    _interstitialAd!.show();
    _isAdReady = false;
    debugPrint('📢 [InterstitialAd] Showing interstitial.');
    return true;
  }
}

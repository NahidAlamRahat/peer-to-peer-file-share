import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../services/ad_service.dart';

/// A reusable Banner Ad widget.
///
/// • Shows nothing (SizedBox.shrink) when AdService reports ads are disabled.
/// • On Web or non-Android platforms it is also hidden.
/// • Automatically disposes the BannerAd to prevent memory leaks.
class AdBannerWidget extends StatefulWidget {
  const AdBannerWidget({super.key});

  @override
  State<AdBannerWidget> createState() => _AdBannerWidgetState();
}

class _AdBannerWidgetState extends State<AdBannerWidget> {
  BannerAd? _bannerAd;
  bool _isLoaded = false;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb && AdService.instance.adsEnabled) {
      _loadBanner();
    }
  }

  void _loadBanner() {
    _bannerAd = BannerAd(
      adUnitId: AdService.instance.bannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _isLoaded = true);
          debugPrint('✅ [AdBanner] Banner ad loaded.');
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          debugPrint('❌ [AdBanner] Failed to load: $error');
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Don't show on web or if ads are disabled or not yet loaded.
    if (kIsWeb || !AdService.instance.adsEnabled || !_isLoaded || _bannerAd == null) {
      return const SizedBox.shrink();
    }

    return SafeArea(
      child: Container(
        alignment: Alignment.center,
        width: _bannerAd!.size.width.toDouble(),
        height: _bannerAd!.size.height.toDouble(),
        child: AdWidget(ad: _bannerAd!),
      ),
    );
  }
}

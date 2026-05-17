import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';

/// AdService handles the remote on/off toggle for all ads via Firebase Remote Config.
///
/// ── How it works ──────────────────────────────────────────────────────────────
/// Firebase Remote Config stores a boolean key `ads_enabled`.
///   • Default value  → false  (ads OFF until you explicitly turn them on)
///   • To turn ads ON → Firebase Console → Remote Config → set ads_enabled = true → Publish
///   • To turn ads OFF → set ads_enabled = false → Publish
///
/// The app fetches the remote value every hour in production.
/// In debug mode it always uses the TEST ad unit IDs regardless of the toggle,
/// so you can always verify ads are working during development.
/// ──────────────────────────────────────────────────────────────────────────────

class AdService {
  AdService._();
  static final AdService instance = AdService._();

  // ── Remote Config key ───────────────────────────────────────────────────────
  static const String _adsEnabledKey = 'ads_enabled';

  // ── AdMob Unit IDs ──────────────────────────────────────────────────────────
  //  Google's official TEST IDs (safe to use during development).
  //  ⚠️  REPLACE with your real Ad Unit IDs from AdMob before publishing.
  static const String _testBannerUnitId =
      'ca-app-pub-3940256099942544/6300978111';
  static const String _testInterstitialUnitId =
      'ca-app-pub-3940256099942544/1033173712';

  //  ── YOUR REAL AD UNIT IDs (fill these before release) ───────────────────
  //  static const String _realBannerUnitId     = 'ca-app-pub-XXXXXXXXXXXXXXXX/XXXXXXXXXX';
  //  static const String _realInterstitialUnitId = 'ca-app-pub-XXXXXXXXXXXXXXXX/XXXXXXXXXX';

  // ── State ───────────────────────────────────────────────────────────────────
  bool _adsEnabled = false;

  /// Whether ads should currently be shown.
  /// In debug mode this is always true so you can test ads locally.
  bool get adsEnabled => kDebugMode ? true : _adsEnabled;

  /// Banner Ad Unit ID to use (test vs production).
  String get bannerAdUnitId => _testBannerUnitId;
  //  Replace ↑ with the line below once you have real IDs:
  //  String get bannerAdUnitId => kDebugMode ? _testBannerUnitId : _realBannerUnitId;

  /// Interstitial Ad Unit ID to use (test vs production).
  String get interstitialAdUnitId => _testInterstitialUnitId;
  //  Replace ↑ with the line below once you have real IDs:
  //  String get interstitialAdUnitId => kDebugMode ? _testInterstitialUnitId : _realInterstitialUnitId;

  // ── Initialise ───────────────────────────────────────────────────────────────
  Future<void> init() async {
    try {
      final remoteConfig = FirebaseRemoteConfig.instance;

      await remoteConfig.setConfigSettings(RemoteConfigSettings(
        // Fetch new values from Firebase every hour in production.
        // In debug mode fetch every 30 seconds for fast iteration.
        fetchTimeout: const Duration(seconds: 10),
        minimumFetchInterval:
            kDebugMode ? const Duration(seconds: 30) : const Duration(hours: 1),
      ));

      // Default: ads OFF until you publish ads_enabled = true in Firebase Console.
      await remoteConfig.setDefaults(const {
        _adsEnabledKey: false,
      });

      // Fetch + activate latest values.
      await remoteConfig.fetchAndActivate();

      _adsEnabled = remoteConfig.getBool(_adsEnabledKey);

      debugPrint(
          '📢 [AdService] Remote Config fetched. ads_enabled = $_adsEnabled');
    } catch (e) {
      // If Firebase / network fails, keep ads OFF to avoid crashes.
      _adsEnabled = false;
      debugPrint('⚠️ [AdService] Remote Config fetch failed: $e');
    }
  }

  /// Call this to refresh the remote value at runtime (e.g. app resumed).
  Future<void> refresh() async {
    try {
      final remoteConfig = FirebaseRemoteConfig.instance;
      await remoteConfig.fetchAndActivate();
      _adsEnabled = remoteConfig.getBool(_adsEnabledKey);
      debugPrint(
          '🔄 [AdService] Remote Config refreshed. ads_enabled = $_adsEnabled');
    } catch (_) {}
  }
}

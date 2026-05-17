// Conditional export: stub on web, AdMob on mobile.
export 'interstitial_ad_service_stub.dart'
    if (dart.library.io) 'interstitial_ad_service_mobile.dart';

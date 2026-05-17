// Conditional export: stub on web, real implementation on mobile.
// dart.library.io is available on Android/iOS but NOT on web.
export 'mobile_ads_init_stub.dart'
    if (dart.library.io) 'mobile_ads_init_native.dart';

// Conditional export: stub on web, AdMob on mobile.
export 'ad_banner_widget_stub.dart'
    if (dart.library.io) 'ad_banner_widget_mobile.dart';

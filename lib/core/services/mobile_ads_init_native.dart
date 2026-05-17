// Native (Android / iOS) — real MobileAds initialization.
import 'package:google_mobile_ads/google_mobile_ads.dart';

Future<void> initializeMobileAds() async {
  await MobileAds.instance.initialize();
}

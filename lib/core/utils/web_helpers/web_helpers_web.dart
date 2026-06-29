// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:js' as js;

void checkIncognitoStatus(void Function(bool) callback) {
  if (js.context.hasProperty('checkIncognito')) {
    js.context.callMethod('checkIncognito', [callback]);
  }
}

String getWebUrl() {
  return html.window.location.href;
}

void triggerPopunderAd() {
  final script = html.ScriptElement()
    ..type = 'text/javascript'
    ..src = 'https://onionclose.com/d3/72/3b/d3723b40affae7bdf83b03e797bc5d14.js';
  html.document.head?.append(script);
}

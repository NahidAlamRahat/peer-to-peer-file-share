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

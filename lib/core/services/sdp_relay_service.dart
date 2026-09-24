import 'package:http/http.dart' as http;

/// Uploads/downloads SDP to a free pastebin relay so users can share
/// a short 6-char session code instead of scanning a QR code.
///
/// Requires a tiny internet connection just for SDP exchange (~2 KB).
/// Actual file transfer remains fully local (same Wi-Fi / hotspot).
class SdpRelayService {
  static const _baseUrl = 'https://dpaste.com';

  /// Uploads [sdpCode] (compressed SDP) to the relay.
  /// Returns a short uppercase code like "A7K9X2".
  static Future<String> upload(String sdpCode) async {
    final response = await http
        .post(
          Uri.parse('$_baseUrl/api/v2/'),
          body: {
            'content': sdpCode,
            'syntax': 'text',
            'expiry_days': '1',
          },
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 201) {
      throw Exception('Relay upload failed: ${response.statusCode}');
    }

    // Response body is a URL like "https://dpaste.com/ABCDEF\n"
    final url = response.body.trim().replaceAll('"', '');
    final code = url.split('/').last.toUpperCase();
    if (code.isEmpty) throw Exception('Invalid relay response');
    return code;
  }

  /// Downloads SDP from the relay using the [code] returned by [upload].
  static Future<String> download(String code) async {
    final url = '$_baseUrl/${code.trim().toUpperCase()}.txt';
    final response = await http
        .get(Uri.parse(url))
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 404) {
      throw Exception('Code not found. It may have expired or is incorrect.');
    }
    if (response.statusCode != 200) {
      throw Exception('Relay download failed: ${response.statusCode}');
    }

    final content = response.body.trim();
    if (content.isEmpty) throw Exception('Empty response from relay');
    return content;
  }
}

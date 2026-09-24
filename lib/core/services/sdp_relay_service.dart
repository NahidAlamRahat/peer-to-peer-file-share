import 'package:http/http.dart' as http;

/// SDP Relay using the built-in Vercel serverless function at /api/relay.
///
/// Sender uploads OFFER → gets session code.
/// Receiver downloads OFFER by code → generates ANSWER → uploads ANSWER.
/// Sender polls for ANSWER automatically → auto-connects, no manual scan needed!
class SdpRelayService {
  static const _relayBase = 'https://peertransfer.app/api/relay';

  // ── Offer ─────────────────────────────────────────────────────────────────

  /// Uploads the compressed offer SDP.
  /// Returns the session code (e.g. "A7K9X2") to show to the receiver.
  static Future<String> uploadOffer(String sdpCode) async {
    return await _upload(sdpCode, 'offer');
  }

  /// Downloads the offer SDP using the session code entered by the receiver.
  static Future<String> downloadOffer(String sessionCode) async {
    return await _download(sessionCode, 'offer');
  }

  // ── Answer ────────────────────────────────────────────────────────────────

  /// Receiver calls this after generating the answer SDP.
  /// Uses the SAME session code (derived from offer) so sender can find it.
  static Future<void> uploadAnswer(String sessionCode, String answerSdp) async {
    final url = Uri.parse('$_relayBase?code=${sessionCode.toUpperCase()}&type=answer');
    final response = await http
        .post(url, body: answerSdp)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw Exception('Answer upload failed: ${response.statusCode}');
    }
  }

  /// Sender polls this to get the receiver's answer.
  /// Returns null if answer not ready yet.
  static Future<String?> pollAnswer(String sessionCode) async {
    final url = Uri.parse('$_relayBase?code=${sessionCode.toUpperCase()}&type=answer');
    final response = await http
        .get(url)
        .timeout(const Duration(seconds: 5));
    if (response.statusCode == 404) return null; // not ready yet
    if (response.statusCode == 200) return response.body.trim();
    throw Exception('Poll failed: ${response.statusCode}');
  }

  // ── Internal ──────────────────────────────────────────────────────────────

  static Future<String> _upload(String sdpCode, String type) async {
    // First upload to dpaste to get a short slug as session code
    final dpasteRes = await http.post(
      Uri.parse('https://dpaste.com/api/v2/'),
      body: {'content': sdpCode, 'syntax': 'text', 'expiry_days': '1'},
    ).timeout(const Duration(seconds: 15));

    if (dpasteRes.statusCode != 201) {
      throw Exception('Relay upload failed: ${dpasteRes.statusCode}');
    }

    final url = dpasteRes.body.trim().replaceAll('"', '');
    final sessionCode = url.split('/').last.toUpperCase();
    if (sessionCode.isEmpty) throw Exception('Invalid relay response');

    // Now also store in Vercel relay keyed by sessionCode so it can be polled
    final vercelUrl = Uri.parse('$_relayBase?code=$sessionCode&type=$type');
    await http.post(vercelUrl, body: sdpCode).timeout(const Duration(seconds: 15));

    return sessionCode;
  }

  static Future<String> _download(String sessionCode, String type) async {
    // Try Vercel relay first (faster polling)
    try {
      final vercelUrl = Uri.parse('$_relayBase?code=${sessionCode.toUpperCase()}&type=$type');
      final res = await http.get(vercelUrl).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200 && res.body.trim().isNotEmpty) {
        return res.body.trim();
      }
    } catch (_) {}

    // Fallback: dpaste direct download
    final dpasteUrl = 'https://dpaste.com/${sessionCode.toUpperCase()}.txt';
    final res = await http.get(Uri.parse(dpasteUrl)).timeout(const Duration(seconds: 15));
    if (res.statusCode == 404) throw Exception('Code not found. Check the code and try again.');
    if (res.statusCode != 200) throw Exception('Download failed: ${res.statusCode}');
    final content = res.body.trim();
    if (content.isEmpty) throw Exception('Empty response');
    return content;
  }
}

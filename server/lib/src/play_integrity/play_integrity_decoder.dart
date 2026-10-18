import 'dart:convert';

import 'package:googleapis/playintegrity/v1.dart';
import 'package:googleapis_auth/auth_io.dart';

/// Decodes Play Integrity tokens with Google's server API
/// (`decodeIntegrityToken`).
///
/// Credentials come from Application Default Credentials, for example a
/// service account key file referenced by `GOOGLE_APPLICATION_CREDENTIALS`,
/// in the Google Cloud project linked in Play Console. Never commit that
/// file.
abstract interface class PlayIntegrityDecoder {
  /// Returns the decoded `tokenPayloadExternal` as JSON.
  Future<Map<String, Object?>> decode(String token);
}

/// [PlayIntegrityDecoder] using the googleapis client.
final class GooglePlayIntegrityDecoder implements PlayIntegrityDecoder {
  GooglePlayIntegrityDecoder._(this._client, this.packageName);

  /// Creates a decoder using Application Default Credentials.
  static Future<GooglePlayIntegrityDecoder> create(String packageName) async {
    final client = await clientViaApplicationDefaultCredentials(
      scopes: [PlayIntegrityApi.playintegrityScope],
    );
    return GooglePlayIntegrityDecoder._(client, packageName);
  }

  final AutoRefreshingAuthClient _client;

  /// The application id the tokens belong to.
  final String packageName;

  @override
  Future<Map<String, Object?>> decode(String token) async {
    final response = await PlayIntegrityApi(_client).v1.decodeIntegrityToken(
      DecodeIntegrityTokenRequest(integrityToken: token),
      packageName,
    );
    final payload = response.tokenPayloadExternal;
    if (payload == null) throw const FormatException('empty payload');
    return toPlainJson(payload);
  }

  /// Converts a googleapis payload to plain maps and lists.
  ///
  /// googleapis `toJson()` is shallow: nested values stay typed objects.
  /// A JSON round trip makes every level a `Map` or `List`.
  static Map<String, Object?> toPlainJson(TokenPayloadExternal payload) =>
      (jsonDecode(jsonEncode(payload)) as Map).cast<String, Object?>();

  /// Closes the HTTP client.
  void close() => _client.close();
}

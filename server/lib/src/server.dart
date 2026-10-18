import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'app_attest/app_attest_verifier.dart';
import 'challenge_store.dart';
import 'play_integrity/play_integrity_decoder.dart';
import 'play_integrity/play_integrity_policy.dart';
import 'verification_result.dart';

/// HTTP routes of the reference server.
///
/// * `POST /v1/challenge` → `{"challenge": "..."}`. The app passes the
///   challenge as `requestHash` to `Integrity.requestToken`.
/// * `POST /v1/android/verify` with `{"token", "challenge"}`.
/// * `POST /v1/ios/attest` with `{"attestation", "keyId", "challenge"}`.
/// * `POST /v1/ios/assert` with `{"assertion", "keyId", "challenge"}`.
///
/// Verification responses are `200 {"ok": true}` or `403 {"ok": false}`.
/// Failure reasons go to [onFailure] for server-side logging and are only
/// included in responses when [exposeFailureReasons] is `true` (for
/// development), so attackers do not learn which check failed. An
/// assertion for a key the server does not know returns
/// `409 {"ok": false, "action": "reattest"}`: the app should call
/// `Integrity.reset()` and request a new token. Tokens are never logged.
///
/// Request bodies above [maxBodyBytes] are rejected, `/v1/challenge`
/// returns 503 when too many challenges are outstanding, and Android tokens
/// are shape-checked before the Google API is called.
///
/// REFERENCE EXAMPLE: no authentication, rate limiting or persistent
/// storage. Bind attested keys to your user accounts and store them in a
/// database before using this in production.
final class IntegrityServer {
  /// Creates the server. Either platform may be left out.
  IntegrityServer({
    this.playDecoder,
    this.playPolicy,
    this.appAttest,
    this.exposeFailureReasons = false,
    this.onFailure,
    ChallengeStore? challenges,
  }) : challenges = challenges ?? ChallengeStore();

  /// Largest accepted request body.
  static const int maxBodyBytes = 32 * 1024;

  /// Decodes Play Integrity tokens; `null` disables Android verification.
  final PlayIntegrityDecoder? playDecoder;

  /// Checks decoded Play Integrity payloads.
  final PlayIntegrityPolicy? playPolicy;

  /// Verifies App Attest objects; `null` disables iOS verification.
  final AppAttestVerifier? appAttest;

  /// Whether failure reasons are returned to the client. Development only.
  final bool exposeFailureReasons;

  /// Receives the route and failure reasons of every rejected request.
  final void Function(String route, List<String> failures)? onFailure;

  /// Issued challenges.
  final ChallengeStore challenges;

  /// Attested keys by canonical (standard base64) key id. In memory for the
  /// reference example only.
  final Map<String, AppAttestKey> keys = {};

  /// The shelf handler.
  Handler get handler {
    final router = Router()
      ..post('/v1/challenge', _challenge)
      ..post('/v1/android/verify', _android)
      ..post('/v1/ios/attest', _attest)
      ..post('/v1/ios/assert', _assert);
    return router.call;
  }

  Response _challenge(Request request) {
    final challenge = challenges.issue();
    if (challenge == null) return _json(503, {'ok': false});
    return _json(200, {'challenge': challenge});
  }

  Future<Response> _android(Request request) async {
    const route = 'android';
    final decoder = playDecoder;
    final policy = playPolicy;
    if (decoder == null || policy == null) return _json(501, _disabled);
    final body = await _body(request);
    final token = body?['token'];
    final challenge = body?['challenge'];
    if (token is! String || challenge is! String) return _badRequest;
    if (!challenges.consume(challenge)) {
      return _verdict(route, _unknownChallenge);
    }
    // Play Integrity tokens are compact JWE (5 base64url segments). Reject
    // anything else before spending Google API quota on it.
    if (!_looksLikeJwe(token)) {
      return _verdict(route, const VerificationResult.fail(['token_format']));
    }
    final Map<String, Object?> payload;
    try {
      payload = await decoder.decode(token);
    } on Object {
      return _verdict(route, const VerificationResult.fail(['decode_failed']));
    }
    return _verdict(
      route,
      policy.check(payload, expectedRequestHash: challenge),
    );
  }

  Future<Response> _attest(Request request) async {
    const route = 'ios_attest';
    final verifier = appAttest;
    if (verifier == null) return _json(501, _disabled);
    final body = await _body(request);
    final attestation = body?['attestation'];
    final keyId = body?['keyId'];
    final challenge = body?['challenge'];
    if (attestation is! String || keyId is! String || challenge is! String) {
      return _badRequest;
    }
    if (!challenges.consume(challenge)) {
      return _verdict(route, _unknownChallenge);
    }
    final canonicalKeyId = _canonicalKeyId(keyId);
    final bytes = _decodeBase64(attestation);
    if (canonicalKeyId == null || bytes == null) return _badRequest;
    final outcome = verifier.verifyAttestation(
      attestation: bytes,
      keyId: canonicalKeyId,
      clientDataHash: _clientDataHash(challenge),
    );
    final key = outcome.key;
    if (key != null) {
      if (keys.containsKey(canonicalKeyId)) {
        return _verdict(
          route,
          const VerificationResult.fail(['key_already_attested']),
        );
      }
      keys[canonicalKeyId] = key;
    }
    return _verdict(route, outcome.result);
  }

  Future<Response> _assert(Request request) async {
    const route = 'ios_assert';
    final verifier = appAttest;
    if (verifier == null) return _json(501, _disabled);
    final body = await _body(request);
    final assertion = body?['assertion'];
    final keyId = body?['keyId'];
    final challenge = body?['challenge'];
    if (assertion is! String || keyId is! String || challenge is! String) {
      return _badRequest;
    }
    if (!challenges.consume(challenge)) {
      return _verdict(route, _unknownChallenge);
    }
    final canonicalKeyId = _canonicalKeyId(keyId);
    final key = canonicalKeyId == null ? null : keys[canonicalKeyId];
    if (key == null) {
      _report(route, const ['unknown_key']);
      return _json(409, {'ok': false, 'action': 'reattest'});
    }
    final bytes = _decodeBase64(assertion);
    if (bytes == null) return _badRequest;
    return _verdict(
      route,
      verifier.verifyAssertion(
        assertion: bytes,
        key: key,
        clientDataHash: _clientDataHash(challenge),
      ),
    );
  }

  /// compliance_integrity uses SHA-256(UTF-8(requestHash)) as clientDataHash.
  static List<int> _clientDataHash(String challenge) =>
      sha256.convert(utf8.encode(challenge)).bytes;

  /// Returns the standard base64 form of a 32-byte key id, or `null`.
  static String? _canonicalKeyId(String keyId) {
    final bytes = _decodeBase64(keyId);
    return bytes != null && bytes.length == 32 ? base64.encode(bytes) : null;
  }

  static Uint8List? _decodeBase64(String value) {
    try {
      return base64.decode(value);
    } on FormatException {
      return null;
    }
  }

  static final RegExp _jwe = RegExp(
    r'^[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]*\.[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+$',
  );

  static bool _looksLikeJwe(String token) =>
      token.length >= 100 && token.length <= 16 * 1024 && _jwe.hasMatch(token);

  static const _disabled = {
    'ok': false,
    'failures': ['platform_disabled'],
  };
  static const _unknownChallenge = VerificationResult.fail([
    'unknown_or_expired_challenge',
  ]);

  static Response get _badRequest => _json(400, {'ok': false});

  static Future<Map<String, Object?>?> _body(Request request) async {
    if ((request.contentLength ?? 0) > maxBodyBytes) return null;
    try {
      final builder = BytesBuilder(copy: false);
      await for (final chunk in request.read()) {
        if (builder.length + chunk.length > maxBodyBytes) return null;
        builder.add(chunk);
      }
      final decoded = jsonDecode(utf8.decode(builder.takeBytes()));
      return decoded is Map<String, Object?> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  void _report(String route, List<String> failures) {
    try {
      onFailure?.call(route, failures);
    } on Object {
      // Logging must not change the response.
    }
  }

  Response _verdict(String route, VerificationResult result) {
    if (result.ok) return _json(200, result.toJson());
    _report(route, result.failures);
    return _json(
      403,
      exposeFailureReasons ? result.toJson() : const {'ok': false},
    );
  }

  static Response _json(int status, Map<String, Object?> body) => Response(
    status,
    body: jsonEncode(body),
    headers: {'content-type': 'application/json'},
  );
}

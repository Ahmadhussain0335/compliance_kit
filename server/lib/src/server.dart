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
/// Verification responses are `200 {"ok": true}` or
/// `403 {"ok": false, "failures": [...]}`. Tokens are never logged.
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
    ChallengeStore? challenges,
  }) : challenges = challenges ?? ChallengeStore();

  /// Decodes Play Integrity tokens; `null` disables Android verification.
  final PlayIntegrityDecoder? playDecoder;

  /// Checks decoded Play Integrity payloads.
  final PlayIntegrityPolicy? playPolicy;

  /// Verifies App Attest objects; `null` disables iOS verification.
  final AppAttestVerifier? appAttest;

  /// Issued challenges.
  final ChallengeStore challenges;

  /// Attested keys by key id. In memory for the reference example only.
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

  Response _challenge(Request request) =>
      _json(200, {'challenge': challenges.issue()});

  Future<Response> _android(Request request) async {
    final decoder = playDecoder;
    final policy = playPolicy;
    if (decoder == null || policy == null) return _json(501, _disabled);
    final body = await _body(request);
    final token = body?['token'];
    final challenge = body?['challenge'];
    if (token is! String || challenge is! String) return _badRequest;
    if (!challenges.consume(challenge)) return _verdict(_unknownChallenge);
    final Map<String, Object?> payload;
    try {
      payload = await decoder.decode(token);
    } on Object {
      return _verdict(const VerificationResult.fail(['decode_failed']));
    }
    return _verdict(policy.check(payload, expectedRequestHash: challenge));
  }

  Future<Response> _attest(Request request) async {
    final verifier = appAttest;
    if (verifier == null) return _json(501, _disabled);
    final body = await _body(request);
    final attestation = body?['attestation'];
    final keyId = body?['keyId'];
    final challenge = body?['challenge'];
    if (attestation is! String || keyId is! String || challenge is! String) {
      return _badRequest;
    }
    if (!challenges.consume(challenge)) return _verdict(_unknownChallenge);
    final Uint8List bytes;
    try {
      bytes = base64.decode(attestation);
    } on FormatException {
      return _badRequest;
    }
    final outcome = verifier.verifyAttestation(
      attestation: bytes,
      keyId: keyId,
      clientDataHash: _clientDataHash(challenge),
    );
    final key = outcome.key;
    if (key != null) {
      if (keys.containsKey(keyId)) {
        return _verdict(
          const VerificationResult.fail(['key_already_attested']),
        );
      }
      keys[keyId] = key;
    }
    return _verdict(outcome.result);
  }

  Future<Response> _assert(Request request) async {
    final verifier = appAttest;
    if (verifier == null) return _json(501, _disabled);
    final body = await _body(request);
    final assertion = body?['assertion'];
    final keyId = body?['keyId'];
    final challenge = body?['challenge'];
    if (assertion is! String || keyId is! String || challenge is! String) {
      return _badRequest;
    }
    if (!challenges.consume(challenge)) return _verdict(_unknownChallenge);
    final key = keys[keyId];
    if (key == null) {
      return _verdict(const VerificationResult.fail(['unknown_key']));
    }
    final Uint8List bytes;
    try {
      bytes = base64.decode(assertion);
    } on FormatException {
      return _badRequest;
    }
    return _verdict(
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

  static const _disabled = {
    'ok': false,
    'failures': ['platform_disabled'],
  };
  static const _unknownChallenge = VerificationResult.fail([
    'unknown_or_expired_challenge',
  ]);
  static Response get _badRequest => _json(400, {
    'ok': false,
    'failures': ['bad_request'],
  });

  static Future<Map<String, Object?>?> _body(Request request) async {
    try {
      final decoded = jsonDecode(await request.readAsString());
      return decoded is Map<String, Object?> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  static Response _verdict(VerificationResult result) =>
      _json(result.ok ? 200 : 403, result.toJson());

  static Response _json(int status, Map<String, Object?> body) => Response(
    status,
    body: jsonEncode(body),
    headers: {'content-type': 'application/json'},
  );
}

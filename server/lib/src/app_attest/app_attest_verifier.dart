import 'dart:convert';
import 'dart:typed_data';

import 'package:cbor/cbor.dart';
import 'package:crypto/crypto.dart';

import '../ecdsa.dart';
import '../verification_result.dart';
import '../x509.dart';
import 'apple_root_ca.dart';

/// App Attest environment, set by the app's entitlement.
enum AppAttestEnvironment {
  /// Sandbox (`development` entitlement, debug builds from Xcode).
  development,

  /// Production (TestFlight, App Store, Enterprise).
  production,
}

/// What the server keeps for an attested key.
final class AppAttestKey {
  /// Creates a key record.
  AppAttestKey({
    required this.keyId,
    required this.publicKey,
    required this.counter,
    required this.receipt,
    required this.environment,
  });

  /// Base64 key id sent by the app.
  final String keyId;

  /// Uncompressed P-256 public key from the credential certificate.
  final Uint8List publicKey;

  /// Last seen sign counter.
  int counter;

  /// Attestation receipt, usable for Apple's fraud risk metric.
  final Uint8List receipt;

  /// Environment the key was attested in.
  final AppAttestEnvironment environment;
}

/// Result of a successful attestation.
final class AttestationOutcome {
  const AttestationOutcome._(this.result, this.key);

  /// Pass or fail with reasons.
  final VerificationResult result;

  /// The key to store, when [result] passed.
  final AppAttestKey? key;
}

/// Verifies App Attest attestations and assertions following Apple's
/// "Validating apps that connect to your server" steps.
///
/// REFERENCE EXAMPLE: review it before using it in production.
final class AppAttestVerifier {
  /// Creates a verifier for the app `teamId.bundleId`.
  AppAttestVerifier({
    required this.teamId,
    required this.bundleId,
    this.environment = AppAttestEnvironment.production,
    String rootCaPem = appleAppAttestationRootCa,
  }) : _root = Certificate.fromPem(rootCaPem);

  /// Apple Developer Team ID.
  final String teamId;

  /// Bundle identifier.
  final String bundleId;

  /// Expected environment.
  final AppAttestEnvironment environment;

  final Certificate _root;

  static const String _nonceExtensionOid = '1.2.840.113635.100.8.2';

  /// Largest accepted attestation object. Real ones are about 5-6 KB.
  static const int maxAttestationBytes = 16 * 1024;

  /// Largest accepted assertion object.
  static const int maxAssertionBytes = 1024;
  static final List<int> _aaguidProduction = [
    ...utf8.encode('appattest'),
    ...List.filled(7, 0),
  ];
  // Apple documents "appattestdevelop"; one page mentions
  // "appattestsandbox". Both are accepted for development.
  static final List<List<int>> _aaguidDevelopment = [
    utf8.encode('appattestdevelop'),
    utf8.encode('appattestsandbox'),
  ];

  /// SHA-256 of `teamId.bundleId`.
  List<int> get appIdHash =>
      sha256.convert(utf8.encode('$teamId.$bundleId')).bytes;

  /// Verifies an attestation object.
  ///
  /// [clientDataHash] is the hash the app passed to `attestKey`. With
  /// compliance_integrity it is `SHA-256(UTF-8(challenge))`.
  AttestationOutcome verifyAttestation({
    required Uint8List attestation,
    required String keyId,
    required List<int> clientDataHash,
    DateTime? now,
  }) {
    final failures = <String>[];
    if (attestation.length > maxAttestationBytes) return _fail('too_large');
    try {
      final object = cborDecode(attestation);
      if (object is! CborMap) return _fail('not_a_cbor_map');
      if (_string(object, 'fmt') != 'apple-appattest') {
        return _fail('unexpected_format');
      }
      final statement = object[CborString('attStmt')];
      final authData = _bytes(object, 'authData');
      if (statement is! CborMap || authData == null) {
        return _fail('missing_fields');
      }
      final x5c = statement[CborString('x5c')];
      final receipt = _bytes(statement, 'receipt') ?? Uint8List(0);
      if (x5c is! CborList || x5c.length != 2) return _fail('missing_x5c');
      final chain = [
        for (final c in x5c)
          Certificate.fromDer(Uint8List.fromList((c as CborBytes).bytes)),
      ];
      final leaf = chain.first;

      // 1. Certificate chain to the pinned Apple root.
      if (!verifyChain(chain, _root, (now ?? DateTime.now()).toUtc())) {
        failures.add('certificate_chain');
      }

      // 2. nonce = SHA256(authData || clientDataHash) must equal the value
      //    in the credential certificate extension.
      final nonce = sha256.convert([...authData, ...clientDataHash]).bytes;
      final extension = leaf.extensions[_nonceExtensionOid];
      if (extension == null ||
          !bytesEqual(_nonceFromExtension(extension), nonce)) {
        failures.add('nonce');
      }

      // 3. SHA256(public key) must equal the key id.
      final keyIdBytes = base64.decode(keyId);
      if (!bytesEqual(sha256.convert(leaf.publicKey).bytes, keyIdBytes)) {
        failures.add('key_id');
      }

      final parsed = _AuthData.parse(authData, withCredential: true);
      // 4. RP ID hash.
      if (!bytesEqual(parsed.rpIdHash, appIdHash)) failures.add('app_id');
      // 5. Counter is zero.
      if (parsed.counter != 0) failures.add('counter');
      // 6. Environment (aaguid).
      final aaguidOk = environment == AppAttestEnvironment.production
          ? bytesEqual(parsed.aaguid!, _aaguidProduction)
          : _aaguidDevelopment.any((a) => bytesEqual(parsed.aaguid!, a));
      if (!aaguidOk) failures.add('environment');
      // 7. Credential id equals the key id.
      if (!bytesEqual(parsed.credentialId!, keyIdBytes)) {
        failures.add('credential_id');
      }

      if (failures.isNotEmpty) {
        return AttestationOutcome._(VerificationResult.fail(failures), null);
      }
      return AttestationOutcome._(
        const VerificationResult.pass(),
        AppAttestKey(
          keyId: keyId,
          publicKey: leaf.publicKey,
          counter: 0,
          receipt: receipt,
          environment: environment,
        ),
      );
    } on Object {
      return _fail('malformed_attestation');
    }
  }

  /// Verifies an assertion made with [key] and updates its counter.
  ///
  /// [clientDataHash] is the hash the app passed to `generateAssertion`.
  VerificationResult verifyAssertion({
    required Uint8List assertion,
    required AppAttestKey key,
    required List<int> clientDataHash,
  }) {
    if (assertion.length > maxAssertionBytes) {
      return const VerificationResult.fail(['too_large']);
    }
    try {
      final object = cborDecode(assertion);
      if (object is! CborMap) {
        return const VerificationResult.fail(['not_a_cbor_map']);
      }
      final signature = _bytes(object, 'signature');
      final authenticatorData = _bytes(object, 'authenticatorData');
      if (signature == null || authenticatorData == null) {
        return const VerificationResult.fail(['missing_fields']);
      }
      final failures = <String>[];
      final nonce = Uint8List.fromList(
        sha256.convert([...authenticatorData, ...clientDataHash]).bytes,
      );
      if (!verifyEcdsa(
        curveOid: oidP256,
        publicKey: key.publicKey,
        signatureAlgorithmOid: oidEcdsaSha256,
        message: nonce,
        signature: signature,
      )) {
        failures.add('signature');
      }
      final parsed = _AuthData.parse(authenticatorData, withCredential: false);
      if (!bytesEqual(parsed.rpIdHash, appIdHash)) failures.add('app_id');
      if (parsed.counter <= key.counter) failures.add('counter');
      if (failures.isNotEmpty) return VerificationResult.fail(failures);
      key.counter = parsed.counter;
      return const VerificationResult.pass();
    } on Object {
      return const VerificationResult.fail(['malformed_assertion']);
    }
  }

  static AttestationOutcome _fail(String reason) =>
      AttestationOutcome._(VerificationResult.fail([reason]), null);

  static String? _string(CborMap map, String key) {
    final value = map[CborString(key)];
    return value is CborString ? value.toString() : null;
  }

  static Uint8List? _bytes(CborMap map, String key) {
    final value = map[CborString(key)];
    return value is CborBytes ? Uint8List.fromList(value.bytes) : null;
  }

  /// The extension holds SEQUENCE { [1] EXPLICIT OCTET STRING nonce }.
  static List<int> _nonceFromExtension(Uint8List value) {
    // 30 L A1 L 04 20 <32 bytes>
    final sequence = _tlv(value, 0, 0x30);
    final tagged = _tlv(value, sequence.$1, 0xA1);
    final octets = _tlv(value, tagged.$1, 0x04);
    return value.sublist(octets.$1, octets.$2);
  }

  /// Returns (valueStart, valueEnd) of the short-form TLV at [offset].
  static (int, int) _tlv(Uint8List b, int offset, int tag) {
    if (b[offset] != tag || b[offset + 1] & 0x80 != 0) {
      throw const FormatException('unexpected nonce extension layout');
    }
    final start = offset + 2;
    return (start, start + b[offset + 1]);
  }
}

/// Authenticator data layout (WebAuthn): rpIdHash(32) flags(1) counter(4)
/// and, for attestations, aaguid(16) credIdLen(2) credId.
final class _AuthData {
  _AuthData(this.rpIdHash, this.counter, this.aaguid, this.credentialId);

  factory _AuthData.parse(Uint8List data, {required bool withCredential}) {
    if (data.length < 37) throw const FormatException('authData too short');
    final counter = ByteData.sublistView(data, 33, 37).getUint32(0);
    if (!withCredential) {
      return _AuthData(data.sublist(0, 32), counter, null, null);
    }
    if (data.length < 55) throw const FormatException('authData too short');
    final length = ByteData.sublistView(data, 53, 55).getUint16(0);
    if (data.length < 55 + length) {
      throw const FormatException('credential id truncated');
    }
    return _AuthData(
      data.sublist(0, 32),
      counter,
      data.sublist(37, 53),
      data.sublist(55, 55 + length),
    );
  }

  final List<int> rpIdHash;
  final int counter;
  final List<int>? aaguid;
  final List<int>? credentialId;
}

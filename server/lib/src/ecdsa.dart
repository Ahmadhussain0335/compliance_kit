import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'der.dart';

/// OID of the P-256 curve.
const String oidP256 = '1.2.840.10045.3.1.7';

/// OID of the P-384 curve.
const String oidP384 = '1.3.132.0.34';

/// OID of ecdsa-with-SHA256.
const String oidEcdsaSha256 = '1.2.840.10045.4.3.2';

/// OID of ecdsa-with-SHA384.
const String oidEcdsaSha384 = '1.2.840.10045.4.3.3';

/// Verifies a DER-encoded ECDSA [signature] over [message].
///
/// [publicKey] is an uncompressed point (`0x04 || X || Y`) on [curveOid].
/// [signatureAlgorithmOid] selects the digest. Returns `false` for any
/// malformed input.
bool verifyEcdsa({
  required String curveOid,
  required Uint8List publicKey,
  required String signatureAlgorithmOid,
  required Uint8List message,
  required Uint8List signature,
}) {
  try {
    final ECDomainParameters domain = switch (curveOid) {
      oidP256 => ECCurve_secp256r1(),
      oidP384 => ECCurve_secp384r1(),
      _ => throw const FormatException('unsupported curve'),
    };
    final Digest digest = switch (signatureAlgorithmOid) {
      oidEcdsaSha256 => SHA256Digest(),
      oidEcdsaSha384 => SHA384Digest(),
      _ => throw const FormatException('unsupported signature algorithm'),
    };
    // Only uncompressed points of the exact size; reject the point at
    // infinity and points that are not on the curve.
    final size = (domain.curve.fieldSize + 7) ~/ 8;
    if (publicKey.length != 1 + 2 * size || publicKey[0] != 0x04) return false;
    final point = domain.curve.decodePoint(publicKey);
    final prime = curveOid == oidP256 ? _p256Prime : _p384Prime;
    if (point == null || point.isInfinity || !_onCurve(point, domain, prime)) {
      return false;
    }
    final parts = Der.parseAll(signature).expect(Der.sequence).children;
    if (parts.length != 2) return false;
    final signer = ECDSASigner(
      digest,
    )..init(false, PublicKeyParameter<ECPublicKey>(ECPublicKey(point, domain)));
    return signer.verifySignature(
      message,
      ECSignature(parts[0].unsignedInteger, parts[1].unsignedInteger),
    );
  } on Object {
    return false;
  }
}

// Field primes from SEC 2:
// p256 = 2^256 - 2^224 + 2^192 + 2^96 - 1
// p384 = 2^384 - 2^128 - 2^96 + 2^32 - 1
final BigInt _two = BigInt.two;
final BigInt _p256Prime =
    _two.pow(256) - _two.pow(224) + _two.pow(192) + _two.pow(96) - BigInt.one;
final BigInt _p384Prime =
    _two.pow(384) - _two.pow(128) - _two.pow(96) + _two.pow(32) - BigInt.one;

/// Checks y^2 = x^3 + ax + b (mod p).
bool _onCurve(ECPoint point, ECDomainParameters domain, BigInt p) {
  final x = point.x!.toBigInteger()!;
  final y = point.y!.toBigInteger()!;
  final curve = domain.curve;
  final a = curve.a!.toBigInteger()!;
  final b = curve.b!.toBigInteger()!;
  return (y * y - (x * x * x + a * x + b)) % p == BigInt.zero;
}

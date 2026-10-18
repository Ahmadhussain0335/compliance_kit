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
    final point = domain.curve.decodePoint(publicKey);
    if (point == null) return false;
    final parts = Der.parse(signature).expect(Der.sequence).children;
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

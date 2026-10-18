import 'dart:convert';
import 'dart:typed_data';

import 'der.dart';
import 'ecdsa.dart';

const String _oidEcPublicKey = '1.2.840.10045.2.1';

/// The parts of an X.509 certificate needed for App Attest verification.
///
/// Only EC public keys are supported, which is what Apple uses.
final class Certificate {
  Certificate._({
    required this.tbs,
    required this.signatureAlgorithm,
    required this.signature,
    required this.issuer,
    required this.subject,
    required this.notBefore,
    required this.notAfter,
    required this.curve,
    required this.publicKey,
    required this.extensions,
  });

  /// Parses a DER certificate.
  ///
  /// Throws [FormatException] if it is malformed or not an EC certificate.
  factory Certificate.fromDer(Uint8List der) {
    final cert = Der.parseAll(der).expect(Der.sequence).children;
    if (cert.length != 3) throw const FormatException('X.509: bad structure');
    final tbs = cert[0].expect(Der.sequence);
    final fields = tbs.children;
    var i = 0;
    if (fields[i].tag == 0xA0) i++; // explicit version
    i++; // serialNumber
    final innerAlgorithm = fields[i++].expect(Der.sequence).children.first.oid;
    final issuer = fields[i++].expect(Der.sequence);
    final validity = fields[i++].expect(Der.sequence).children;
    final subject = fields[i++].expect(Der.sequence);
    final spki = fields[i++].expect(Der.sequence).children;
    final algorithm = spki[0].expect(Der.sequence).children;
    if (algorithm[0].oid != _oidEcPublicKey) {
      throw const FormatException('X.509: not an EC public key');
    }
    final extensions = <String, Uint8List>{};
    for (; i < fields.length; i++) {
      if (fields[i].tag != 0xA3) continue;
      final list = fields[i].children.single.expect(Der.sequence).children;
      for (final ext in list) {
        final parts = ext.expect(Der.sequence).children;
        final oid = parts.first.oid;
        if (extensions.containsKey(oid)) {
          throw const FormatException('X.509: duplicate extension');
        }
        extensions[oid] = parts.last.expect(Der.octetString).value;
      }
    }
    final outerAlgorithm = cert[1].expect(Der.sequence).children.first.oid;
    if (outerAlgorithm != innerAlgorithm) {
      throw const FormatException('X.509: signature algorithm mismatch');
    }
    return Certificate._(
      tbs: tbs.encoded,
      signatureAlgorithm: outerAlgorithm,
      signature: cert[2].bitStringBytes,
      issuer: issuer.encoded,
      subject: subject.encoded,
      notBefore: validity[0].time,
      notAfter: validity[1].time,
      curve: algorithm[1].oid,
      publicKey: spki[1].bitStringBytes,
      extensions: extensions,
    );
  }

  /// Parses a PEM certificate.
  factory Certificate.fromPem(String pem) {
    final body = pem
        .replaceAll('-----BEGIN CERTIFICATE-----', '')
        .replaceAll('-----END CERTIFICATE-----', '')
        .replaceAll(RegExp(r'\s'), '');
    return Certificate.fromDer(base64.decode(body));
  }

  /// The signed part of the certificate.
  final Uint8List tbs;

  /// OID of the algorithm the issuer used to sign [tbs].
  final String signatureAlgorithm;

  /// DER-encoded ECDSA signature over [tbs].
  final Uint8List signature;

  /// DER-encoded issuer name.
  final Uint8List issuer;

  /// DER-encoded subject name.
  final Uint8List subject;

  /// Start of validity, UTC.
  final DateTime notBefore;

  /// End of validity, UTC.
  final DateTime notAfter;

  /// OID of the curve of [publicKey].
  final String curve;

  /// Uncompressed EC point.
  final Uint8List publicKey;

  /// Extension values (the inner bytes of `extnValue`) by OID.
  final Map<String, Uint8List> extensions;

  /// Whether this certificate was signed by [issuerCert] and names it as
  /// issuer.
  bool isIssuedBy(Certificate issuerCert) =>
      _equal(issuer, issuerCert.subject) &&
      verifyEcdsa(
        curveOid: issuerCert.curve,
        publicKey: issuerCert.publicKey,
        signatureAlgorithmOid: signatureAlgorithm,
        message: tbs,
        signature: signature,
      );

  /// Whether basicConstraints marks this certificate as a CA.
  bool get isCa {
    final value = extensions['2.5.29.19'];
    if (value == null) return false;
    final fields = Der.parseAll(value).expect(Der.sequence).children;
    return fields.isNotEmpty &&
        fields.first.tag == 0x01 &&
        fields.first.value.length == 1 &&
        fields.first.value[0] == 0xFF;
  }

  /// Whether keyUsage allows certificate signing (or is absent).
  bool get mayIssueCertificates {
    final value = extensions['2.5.29.15'];
    if (value == null) return true;
    final bits = Der.parseAll(value).value;
    // bits[0] is the unused-bit count; keyCertSign is bit 5 (0x04).
    return bits.length >= 2 && bits[1] & 0x04 != 0;
  }

  /// Whether [time] is inside the validity period.
  bool isValidAt(DateTime time) =>
      !time.isBefore(notBefore) && !time.isAfter(notAfter);
}

/// Verifies that [chain] (leaf first) leads to [root] and that every
/// certificate is valid at [now]. The root is pinned: it is never taken
/// from the chain. Issuers must be CAs allowed to sign certificates, and
/// the leaf must not be a CA.
bool verifyChain(List<Certificate> chain, Certificate root, DateTime now) {
  try {
    if (chain.isEmpty || chain.first.isCa) return false;
    for (var i = 0; i < chain.length; i++) {
      final issuer = i + 1 < chain.length ? chain[i + 1] : root;
      if (!issuer.isCa || !issuer.mayIssueCertificates) return false;
      if (!chain[i].isValidAt(now) || !chain[i].isIssuedBy(issuer)) {
        return false;
      }
    }
    return root.isValidAt(now);
  } on FormatException {
    return false;
  }
}

bool _equal(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

/// Constant-time comparison of two byte lists.
bool bytesEqual(List<int> a, List<int> b) => _equal(a, b);

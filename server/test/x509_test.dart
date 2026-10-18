import 'dart:io';
import 'dart:typed_data';

import 'package:compliance_integrity_server/compliance_integrity_server.dart';
import 'package:compliance_integrity_server/src/ecdsa.dart';
import 'package:test/test.dart';

// Test PKI generated with OpenSSL (P-256): root -> intermediate (CA) ->
// leaf, and root -> non_ca_issuer (CA:FALSE) -> leaf_under_non_ca.
Certificate _load(String name) =>
    Certificate.fromPem(File('test/fixtures/pki/$name.pem').readAsStringSync());

void main() {
  final now = DateTime.now().toUtc();
  final root = _load('root');

  test('a valid chain passes', () {
    expect(verifyChain([_load('leaf'), _load('inter')], root, now), isTrue);
  });

  test('a non-CA certificate cannot act as an issuer', () {
    expect(
      verifyChain(
        [_load('leaf_under_non_ca'), _load('non_ca_issuer')],
        root,
        now,
      ),
      isFalse,
    );
  });

  test('a CA certificate cannot be the leaf', () {
    expect(verifyChain([_load('inter')], root, now), isFalse);
    expect(verifyChain([_load('inter'), _load('inter')], root, now), isFalse);
  });

  test('wrong order, expiry and empty chains fail', () {
    expect(verifyChain([_load('inter'), _load('leaf')], root, now), isFalse);
    expect(
      verifyChain([_load('leaf'), _load('inter')], root, DateTime.utc(2000)),
      isFalse,
    );
    expect(verifyChain([], root, now), isFalse);
  });

  test('CA flags', () {
    expect(root.isCa, isTrue);
    expect(root.mayIssueCertificates, isTrue);
    expect(_load('leaf').isCa, isFalse);
    expect(_load('leaf').mayIssueCertificates, isFalse);
  });

  test('ECDSA rejects malformed and degenerate public keys', () {
    final leaf = _load('leaf');
    final inter = _load('inter');
    bool verify(Uint8List key) => verifyEcdsa(
      curveOid: oidP256,
      publicKey: key,
      signatureAlgorithmOid: leaf.signatureAlgorithm,
      message: leaf.tbs,
      signature: leaf.signature,
    );
    expect(verify(inter.publicKey), isTrue);
    expect(verify(Uint8List.fromList([0])), isFalse); // point at infinity
    final offCurve = Uint8List.fromList(inter.publicKey)..[64] ^= 0x01;
    expect(verify(offCurve), isFalse);
    final compressed = Uint8List.fromList(inter.publicKey)..[0] = 0x06;
    expect(verify(compressed), isFalse);
    expect(
      verifyEcdsa(
        curveOid: '1.2.3',
        publicKey: inter.publicKey,
        signatureAlgorithmOid: leaf.signatureAlgorithm,
        message: leaf.tbs,
        signature: leaf.signature,
      ),
      isFalse,
    );
  });

  test('malformed certificates are rejected', () {
    expect(
      () => Certificate.fromDer(Uint8List.fromList([0x30, 0x00, 0x00])),
      throwsFormatException,
    );
  });
}

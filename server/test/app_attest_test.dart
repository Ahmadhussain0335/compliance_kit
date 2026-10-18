import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cbor/cbor.dart';
import 'package:compliance_integrity_server/compliance_integrity_server.dart';
import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart' hide Digest;
import 'package:test/test.dart';

// Apple's published sample from "Attestation Object Validation Guide":
// team 1234567890, bundle com.example.myapp, challenge
// "example_server_challenge", production environment. The sample uses the
// raw challenge bytes as clientDataHash.
const _sampleKeyId = 'zgSY9YSD+7TaDXssY6WlOPVS1K3Lmk+pFhlcSWE+ZV0=';
final _sampleTime = DateTime.utc(2026, 4, 21);

Uint8List _sampleAttestation() => base64.decode(
  File('test/fixtures/apple_sample_attestation.txt').readAsStringSync().trim(),
);

AppAttestVerifier _verifier({
  AppAttestEnvironment environment = AppAttestEnvironment.production,
  String teamId = '1234567890',
}) => AppAttestVerifier(
  teamId: teamId,
  bundleId: 'com.example.myapp',
  environment: environment,
);

void main() {
  group('attestation (Apple sample)', () {
    test('passes every check', () {
      final outcome = _verifier().verifyAttestation(
        attestation: _sampleAttestation(),
        keyId: _sampleKeyId,
        clientDataHash: utf8.encode('example_server_challenge'),
        now: _sampleTime,
      );
      expect(outcome.result.failures, isEmpty);
      expect(outcome.result.ok, isTrue);
      expect(outcome.key!.counter, 0);
      expect(outcome.key!.publicKey, hasLength(65));
      expect(outcome.key!.receipt, isNotEmpty);
    });

    test('fails on a different challenge', () {
      final outcome = _verifier().verifyAttestation(
        attestation: _sampleAttestation(),
        keyId: _sampleKeyId,
        clientDataHash: utf8.encode('another_challenge'),
        now: _sampleTime,
      );
      expect(outcome.result.failures, ['nonce']);
      expect(outcome.key, isNull);
    });

    test('fails outside the certificate validity', () {
      final outcome = _verifier().verifyAttestation(
        attestation: _sampleAttestation(),
        keyId: _sampleKeyId,
        clientDataHash: utf8.encode('example_server_challenge'),
        now: DateTime.utc(2026, 10, 18),
      );
      expect(outcome.result.failures, ['certificate_chain']);
    });

    test('fails for another app, key id or environment', () {
      final wrongApp = _verifier(teamId: 'ABCDE12345').verifyAttestation(
        attestation: _sampleAttestation(),
        keyId: _sampleKeyId,
        clientDataHash: utf8.encode('example_server_challenge'),
        now: _sampleTime,
      );
      expect(wrongApp.result.failures, ['app_id']);

      final wrongKey = _verifier().verifyAttestation(
        attestation: _sampleAttestation(),
        keyId: base64.encode(List.filled(32, 1)),
        clientDataHash: utf8.encode('example_server_challenge'),
        now: _sampleTime,
      );
      expect(wrongKey.result.failures, ['key_id', 'credential_id']);

      final wrongEnv = _verifier(environment: AppAttestEnvironment.development)
          .verifyAttestation(
            attestation: _sampleAttestation(),
            keyId: _sampleKeyId,
            clientDataHash: utf8.encode('example_server_challenge'),
            now: _sampleTime,
          );
      expect(wrongEnv.result.failures, ['environment']);
    });

    test('rejects oversized objects before decoding', () {
      expect(
        _verifier()
            .verifyAttestation(
              attestation: Uint8List(AppAttestVerifier.maxAttestationBytes + 1),
              keyId: _sampleKeyId,
              clientDataHash: const [],
            )
            .result
            .failures,
        ['too_large'],
      );
    });

    test('fails on a tampered or malformed object', () {
      final tampered = _sampleAttestation();
      tampered[tampered.length - 40] ^= 0xFF;
      final outcome = _verifier().verifyAttestation(
        attestation: tampered,
        keyId: _sampleKeyId,
        clientDataHash: utf8.encode('example_server_challenge'),
        now: _sampleTime,
      );
      expect(outcome.result.ok, isFalse);

      expect(
        _verifier()
            .verifyAttestation(
              attestation: Uint8List.fromList([1, 2, 3]),
              keyId: _sampleKeyId,
              clientDataHash: const [],
            )
            .result
            .failures,
        isNotEmpty,
      );
    });
  });

  group('assertion', () {
    // A locally generated P-256 key stands in for the attested key.
    late ECPrivateKey privateKey;
    late AppAttestKey key;
    final verifier = _verifier();

    setUp(() {
      final random = FortunaRandom()
        ..seed(KeyParameter(Uint8List.fromList(List.generate(32, (i) => i))));
      final generator = ECKeyGenerator()
        ..init(
          ParametersWithRandom(
            ECKeyGeneratorParameters(ECCurve_secp256r1()),
            random,
          ),
        );
      final pair = generator.generateKeyPair();
      privateKey = pair.privateKey;
      final publicKey = pair.publicKey;
      key = AppAttestKey(
        keyId: 'test',
        publicKey: publicKey.Q!.getEncoded(false),
        counter: 0,
        receipt: Uint8List(0),
        environment: AppAttestEnvironment.production,
      );
    });

    Uint8List assertion({
      required int counter,
      required List<int> clientDataHash,
      List<int>? rpIdHash,
    }) {
      final authData = Uint8List.fromList([
        ...rpIdHash ?? verifier.appIdHash,
        0x00,
        ...(ByteData(4)..setUint32(0, counter)).buffer.asUint8List(),
      ]);
      final nonce = sha256.convert([...authData, ...clientDataHash]).bytes;
      final signer = ECDSASigner(SHA256Digest())
        ..init(
          true,
          ParametersWithRandom(
            PrivateKeyParameter<ECPrivateKey>(privateKey),
            FortunaRandom()..seed(
              KeyParameter(
                Uint8List.fromList(
                  List.generate(32, (_) => Random.secure().nextInt(256)),
                ),
              ),
            ),
          ),
        );
      final sig =
          signer.generateSignature(Uint8List.fromList(nonce)) as ECSignature;
      final der = _derSignature(sig.r, sig.s);
      return Uint8List.fromList(
        cbor.encode(
          CborMap({
            CborString('signature'): CborBytes(der),
            CborString('authenticatorData'): CborBytes(authData),
          }),
        ),
      );
    }

    test('valid assertion passes and advances the counter', () {
      final hash = sha256.convert(utf8.encode('challenge-1')).bytes;
      final result = verifier.verifyAssertion(
        assertion: assertion(counter: 1, clientDataHash: hash),
        key: key,
        clientDataHash: hash,
      );
      expect(result.ok, isTrue);
      expect(key.counter, 1);
    });

    test('replayed counter, wrong challenge, wrong app', () {
      final hash = sha256.convert(utf8.encode('c')).bytes;
      key.counter = 5;
      expect(
        verifier
            .verifyAssertion(
              assertion: assertion(counter: 5, clientDataHash: hash),
              key: key,
              clientDataHash: hash,
            )
            .failures,
        ['counter'],
      );
      expect(
        verifier
            .verifyAssertion(
              assertion: assertion(counter: 6, clientDataHash: hash),
              key: key,
              clientDataHash: sha256.convert(utf8.encode('other')).bytes,
            )
            .failures,
        ['signature'],
      );
      expect(
        verifier
            .verifyAssertion(
              assertion: assertion(
                counter: 7,
                clientDataHash: hash,
                rpIdHash: List.filled(32, 0),
              ),
              key: key,
              clientDataHash: hash,
            )
            .failures,
        ['app_id'],
      );
      expect(key.counter, 5);
    });

    test('oversized assertion', () {
      expect(
        verifier
            .verifyAssertion(
              assertion: Uint8List(AppAttestVerifier.maxAssertionBytes + 1),
              key: key,
              clientDataHash: const [],
            )
            .failures,
        ['too_large'],
      );
    });

    test('malformed assertions', () {
      expect(
        verifier
            .verifyAssertion(
              assertion: Uint8List.fromList(cbor.encode(CborString('x'))),
              key: key,
              clientDataHash: const [],
            )
            .failures,
        ['not_a_cbor_map'],
      );
      expect(
        verifier
            .verifyAssertion(
              assertion: Uint8List.fromList(cbor.encode(CborMap({}))),
              key: key,
              clientDataHash: const [],
            )
            .failures,
        ['missing_fields'],
      );
      expect(
        verifier
            .verifyAssertion(
              assertion: Uint8List.fromList([0xFF]),
              key: key,
              clientDataHash: const [],
            )
            .failures,
        ['malformed_assertion'],
      );
    });
  });
}

Uint8List _derSignature(BigInt r, BigInt s) {
  List<int> integer(BigInt v) {
    var bytes = <int>[];
    var x = v;
    while (x > BigInt.zero) {
      bytes.insert(0, (x & BigInt.from(0xFF)).toInt());
      x >>= 8;
    }
    if (bytes.isEmpty || bytes.first & 0x80 != 0) bytes = [0, ...bytes];
    return [0x02, bytes.length, ...bytes];
  }

  final body = [...integer(r), ...integer(s)];
  return Uint8List.fromList([0x30, body.length, ...body]);
}

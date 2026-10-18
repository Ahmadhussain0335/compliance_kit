import 'dart:convert';

import 'package:compliance_integrity_server/compliance_integrity_server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

class _FakeDecoder implements PlayIntegrityDecoder {
  _FakeDecoder(this.response);

  Map<String, Object?> Function(String token) response;

  @override
  Future<Map<String, Object?>> decode(String token) async => response(token);
}

// Shape of a compact JWE; not a real token.
final _fakeJwe = [for (var i = 0; i < 5; i++) 'QUJD' * 8].join('.');

Future<(int, Map<String, Object?>)> post(
  Handler handler,
  String path,
  Object? body,
) async {
  final response = await handler(
    Request(
      'POST',
      Uri.parse('http://localhost$path'),
      body: body is String ? body : jsonEncode(body),
    ),
  );
  return (
    response.statusCode,
    jsonDecode(await response.readAsString()) as Map<String, Object?>,
  );
}

void main() {
  group('challenges', () {
    test('are single use and expire', () {
      var now = DateTime.utc(2026);
      final store = ChallengeStore(clock: () => now);
      final c = store.issue()!;
      expect(c, hasLength(43));
      expect(store.consume(c), isTrue);
      expect(store.consume(c), isFalse);
      final late = store.issue()!;
      now = now.add(const Duration(minutes: 6));
      expect(store.consume(late), isFalse);
      store.issue();
      expect(store.length, 1);
    });
  });

  group('android route', () {
    test('verifies a decoded token bound to the challenge', () async {
      late String challenge;
      final failures = <(String, List<String>)>[];
      final server = IntegrityServer(
        playDecoder: _FakeDecoder(
          (_) => {
            'requestDetails': {
              'requestPackageName': 'com.example.app',
              'requestHash': challenge,
              'timestampMillis': '${DateTime.now().millisecondsSinceEpoch}',
            },
            'appIntegrity': {
              'appRecognitionVerdict': 'PLAY_RECOGNIZED',
              'packageName': 'com.example.app',
            },
            'deviceIntegrity': {
              'deviceRecognitionVerdict': ['MEETS_DEVICE_INTEGRITY'],
            },
            'accountDetails': {'appLicensingVerdict': 'LICENSED'},
          },
        ),
        playPolicy: const PlayIntegrityPolicy(packageName: 'com.example.app'),
        onFailure: (route, reasons) => failures.add((route, reasons)),
      );
      final handler = server.handler;
      challenge =
          (await post(handler, '/v1/challenge', null)).$2['challenge']!
              as String;

      final ok = await post(handler, '/v1/android/verify', {
        'token': _fakeJwe,
        'challenge': challenge,
      });
      expect(ok.$1, 200);
      expect(ok.$2, {'ok': true});

      final replay = await post(handler, '/v1/android/verify', {
        'token': _fakeJwe,
        'challenge': challenge,
      });
      expect(replay.$1, 403);
      expect(replay.$2, {'ok': false});
      expect(failures.last.$1, 'android');
      expect(failures.last.$2, ['unknown_or_expired_challenge']);
    });

    test('decode errors, bad requests and disabled platforms', () async {
      final server = IntegrityServer(
        playDecoder: _FakeDecoder((_) => throw StateError('google down')),
        playPolicy: const PlayIntegrityPolicy(packageName: 'a'),
        exposeFailureReasons: true,
      );
      final handler = server.handler;
      final failed = await post(handler, '/v1/android/verify', {
        'token': _fakeJwe,
        'challenge': server.challenges.issue(),
      });
      expect(failed.$2['failures'], ['decode_failed']);
      final notJwe = await post(handler, '/v1/android/verify', {
        'token': 'not-a-token',
        'challenge': server.challenges.issue(),
      });
      expect(notJwe.$2['failures'], ['token_format']);
      expect((await post(handler, '/v1/android/verify', 'nope')).$1, 400);
      expect((await post(handler, '/v1/android/verify', [1])).$1, 400);
      expect((await post(handler, '/v1/ios/attest', {})).$1, 501);
      expect((await post(handler, '/v1/ios/assert', {})).$1, 501);
      expect(
        (await post(IntegrityServer().handler, '/v1/android/verify', {})).$1,
        501,
      );
    });
  });

  group('ios routes', () {
    final server = IntegrityServer(
      appAttest: AppAttestVerifier(teamId: 'ABCDE12345', bundleId: 'com.x'),
      exposeFailureReasons: true,
    );
    final handler = server.handler;

    test('invalid attestation is rejected and not stored', () async {
      final c = server.challenges.issue();
      final result = await post(handler, '/v1/ios/attest', {
        'attestation': base64.encode([1, 2, 3]),
        'keyId': base64.encode(List.filled(32, 0)),
        'challenge': c,
      });
      expect(result.$1, 403);
      expect(server.keys, isEmpty);
    });

    test('bad input and unknown keys', () async {
      expect(
        (await post(handler, '/v1/ios/attest', {
          'attestation': '%%%',
          'keyId': 'k',
          'challenge': server.challenges.issue(),
        })).$1,
        400,
      );
      final unknown = await post(handler, '/v1/ios/assert', {
        'assertion': 'AA==',
        'keyId': base64.encode(List.filled(32, 9)),
        'challenge': server.challenges.issue(),
      });
      expect(unknown.$1, 409);
      expect(unknown.$2, {'ok': false, 'action': 'reattest'});
      expect(
        (await post(handler, '/v1/ios/assert', {
          'assertion': 'AA==',
          'keyId': 'unknown',
          'challenge': 'never-issued',
        })).$2['failures'],
        ['unknown_or_expired_challenge'],
      );
      expect((await post(handler, '/v1/ios/assert', {'x': 1})).$1, 400);
      expect(
        (await post(handler, '/v1/ios/attest', {
          'attestation': 'AA==',
          'keyId': 'k',
          'challenge': 'never-issued',
        })).$2['failures'],
        ['unknown_or_expired_challenge'],
      );
    });

    test('malformed assertion for a known key', () async {
      final keyId = base64.encode(List.filled(32, 7));
      server.keys[keyId] = AppAttestKey(
        keyId: keyId,
        publicKey: base64.decode(
          // Uncompressed P-256 generator point, a valid but unrelated key.
          'BGsX0fLhLEJH+Lzm5WOkQPJ3A32BLeszoPShOUXYmMKWT+NC4v4af5uO5+tKfA+eFivOM1drMV7Oy7ZAaDe/UfU=',
        ),
        counter: 0,
        receipt: base64.decode(''),
        environment: AppAttestEnvironment.production,
      );
      final result = await post(handler, '/v1/ios/assert', {
        'assertion': '%%%',
        // URL-safe spelling of the same key id resolves to the same key.
        'keyId': base64Url.encode(List.filled(32, 7)),
        'challenge': server.challenges.issue(),
      });
      expect(result.$1, 400);
      final garbage = await post(handler, '/v1/ios/assert', {
        'assertion': 'AA==',
        'keyId': keyId,
        'challenge': server.challenges.issue(),
      });
      // AA== decodes to the CBOR integer 0.
      expect(garbage.$2['failures'], ['not_a_cbor_map']);
    });
  });

  group('limits', () {
    test('oversized bodies are rejected', () async {
      final server = IntegrityServer(
        appAttest: AppAttestVerifier(teamId: 'ABCDE12345', bundleId: 'com.x'),
      );
      final big = await post(server.handler, '/v1/ios/attest', {
        'attestation': 'A' * (IntegrityServer.maxBodyBytes + 1),
        'keyId': base64.encode(List.filled(32, 0)),
        'challenge': server.challenges.issue(),
      });
      expect(big.$1, 400);
    });

    test('challenge endpoint returns 503 when the store is full', () async {
      final server = IntegrityServer(
        challenges: ChallengeStore(maxOutstanding: 1),
      );
      expect((await post(server.handler, '/v1/challenge', null)).$1, 200);
      expect((await post(server.handler, '/v1/challenge', null)).$1, 503);
    });

    test(
      'failure reasons are hidden by default and logging errors are ignored',
      () async {
        final server = IntegrityServer(
          appAttest: AppAttestVerifier(teamId: 'ABCDE12345', bundleId: 'com.x'),
          onFailure: (_, _) => throw StateError('logger down'),
        );
        final result = await post(server.handler, '/v1/ios/attest', {
          'attestation': base64.encode([1, 2, 3]),
          'keyId': base64.encode(List.filled(32, 0)),
          'challenge': server.challenges.issue(),
        });
        expect(result.$1, 403);
        expect(result.$2, {'ok': false});
      },
    );
  });
}

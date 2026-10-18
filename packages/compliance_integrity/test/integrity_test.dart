import 'package:compliance_core/compliance_core.dart';
import 'package:compliance_integrity/compliance_integrity.dart';
import 'package:compliance_integrity/src/messages.g.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _fakeToken = 'ZmFrZS10b2tlbi1ub3QtcmVhbA';

class _FakePlatform implements IntegrityPlatform {
  bool supported = true;
  Object? error;
  PlatformToken token = const PlatformToken(
    token: _fakeToken,
    kind: IntegrityTokenKind.playIntegrityStandard,
  );
  int? lastProjectNumber;
  String? lastHash;
  int resets = 0;

  @override
  Future<bool> isSupported() async {
    if (error != null) throw error!;
    return supported;
  }

  @override
  Future<void> prepare({int? cloudProjectNumber}) async {
    lastProjectNumber = cloudProjectNumber;
    if (error != null) throw error!;
  }

  @override
  Future<PlatformToken> requestToken({
    required String requestHash,
    int? cloudProjectNumber,
  }) async {
    lastHash = requestHash;
    lastProjectNumber = cloudProjectNumber;
    if (error != null) throw error!;
    return token;
  }

  @override
  Future<void> reset() async {
    resets++;
    if (error != null) throw error!;
  }
}

class _FakeHostApi implements IntegrityHostApi {
  Object? error;
  TokenMessage response = TokenMessage(
    token: _fakeToken,
    kind: TokenKindMessage.appAttestAssertion,
    keyId: 'a2V5LWlk',
  );
  final calls = <String>[];

  Future<T> _run<T>(String name, T value) async {
    calls.add(name);
    if (error != null) throw error!;
    return value;
  }

  @override
  Future<bool> isSupported() => _run('isSupported', true);

  @override
  Future<void> prepare(int? cloudProjectNumber) =>
      _run('prepare:$cloudProjectNumber', null);

  @override
  Future<TokenMessage> requestToken(
    String requestHash,
    int? cloudProjectNumber,
  ) => _run('requestToken:$requestHash:$cloudProjectNumber', response);

  @override
  Future<void> reset() => _run('reset', null);

  @override
  // ignore: non_constant_identifier_names
  BinaryMessenger? get pigeonVar_binaryMessenger => null;

  @override
  // ignore: non_constant_identifier_names
  String get pigeonVar_messageChannelSuffix => '';
}

class _FailingTrail implements AuditTrail {
  @override
  Stream<AuditEvent> get events => const Stream.empty();

  @override
  Future<void> record(AuditEvent event) => Future.error(StateError('down'));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakePlatform platform;
  late InMemoryAuditTrail trail;
  late Integrity integrity;

  setUp(() {
    platform = _FakePlatform();
    trail = InMemoryAuditTrail();
    integrity = Integrity(
      cloudProjectNumber: 123456789012,
      auditTrail: trail,
      platform: platform,
      clock: () => DateTime.utc(2026, 10, 18),
    );
  });

  group('requestToken', () {
    test('returns a typed success and records a passed event', () async {
      final result = await integrity.requestToken('server-hash-1');
      expect(result, isA<IntegritySuccess>());
      final success = result as IntegritySuccess;
      expect(success.token, _fakeToken);
      expect(success.kind, IntegrityTokenKind.playIntegrityStandard);
      expect(success.isSuccess, isTrue);
      expect(platform.lastHash, 'server-hash-1');
      expect(platform.lastProjectNumber, 123456789012);

      final event = trail.history.single;
      expect(event.type, Integrity.checkPassedEvent);
      expect(event.source, 'compliance_integrity');
      expect(event.metadata, {
        'result': 'success',
        'kind': 'playIntegrityStandard',
      });
      expect(event.toJson().toString(), isNot(contains(_fakeToken)));
    });

    test('toString never contains the token', () async {
      final result = await integrity.requestToken('h');
      expect(result.toString(), isNot(contains(_fakeToken)));
    });

    test('passes the iOS key id through', () async {
      platform.token = const PlatformToken(
        token: _fakeToken,
        kind: IntegrityTokenKind.appAttestAttestation,
        keyId: 'a2V5',
      );
      final result = await integrity.requestToken('h') as IntegritySuccess;
      expect(result.kind, IntegrityTokenKind.appAttestAttestation);
      expect(result.keyId, 'a2V5');
    });

    test('rejects empty and too long request hashes without a call', () async {
      for (final hash in ['', 'x' * 501]) {
        platform.lastHash = null;
        final result = await integrity.requestToken(hash);
        expect(result, isA<IntegrityConfigurationError>());
        expect(platform.lastHash, isNull);
      }
      expect(await integrity.requestToken('x' * 500), isA<IntegritySuccess>());
    });

    final cases = <String, Matcher>{
      IntegrityErrorCodes.unsupported: isA<IntegrityUnsupported>(),
      IntegrityErrorCodes.playServicesMissing:
          isA<IntegrityPlayServicesMissing>(),
      IntegrityErrorCodes.network: isA<IntegrityNetworkError>(),
      IntegrityErrorCodes.rateLimited: isA<IntegrityRateLimited>(),
      IntegrityErrorCodes.configuration: isA<IntegrityConfigurationError>(),
      IntegrityErrorCodes.transient: isA<IntegrityPlatformError>(),
      IntegrityErrorCodes.platform: isA<IntegrityPlatformError>(),
      'something_new': isA<IntegrityPlatformError>(),
    };
    cases.forEach((code, matcher) {
      test('maps $code', () async {
        platform.error = IntegrityPlatformException(
          code,
          message: 'detail',
          platformCode: '-7',
        );
        final result = await integrity.requestToken('h');
        expect(result, matcher);
        final failure = result as IntegrityFailure;
        expect(failure.platformCode, '-7');
        expect(failure.message, 'detail');
        expect(failure.isSuccess, isFalse);
        expect(failure.toString(), contains(failure.resultType));
        expect(trail.history.last.type, Integrity.checkFailedEvent);
        expect(trail.history.last.metadata, {
          'result': failure.resultType,
          'platform_code': '-7',
        });
      });
    });

    test('retryable flags', () {
      expect(const IntegrityNetworkError().isRetryable, isTrue);
      expect(const IntegrityRateLimited().isRetryable, isTrue);
      expect(const IntegrityUnsupported().isRetryable, isFalse);
      expect(const IntegrityPlayServicesMissing().isRetryable, isFalse);
      expect(const IntegrityConfigurationError().isRetryable, isFalse);
      expect(const IntegrityPlatformError().isRetryable, isFalse);
      expect(
        Integrity.mapError(
          const IntegrityPlatformException(IntegrityErrorCodes.transient),
        ).isRetryable,
        isTrue,
      );
    });

    test('unexpected errors become a platform error', () async {
      platform.error = StateError('raw');
      final result = await integrity.requestToken('h');
      expect(result, isA<IntegrityPlatformError>());
      expect(result.toString(), isNot(contains('raw')));
    });

    test('long platform codes are truncated in audit metadata', () async {
      platform.error = IntegrityPlatformException(
        IntegrityErrorCodes.platform,
        platformCode: 'c' * 300,
      );
      await integrity.requestToken('h');
      expect(trail.history.last.metadata['platform_code'], hasLength(64));
    });

    test('a failing audit trail does not change the result', () async {
      final result = await Integrity(
        platform: platform,
        auditTrail: _FailingTrail(),
      ).requestToken('h');
      expect(result, isA<IntegritySuccess>());
    });
  });

  group('isSupported, prepare, reset', () {
    test('isSupported never throws', () async {
      expect(await integrity.isSupported(), isTrue);
      platform.supported = false;
      expect(await integrity.isSupported(), isFalse);
      platform.error = StateError('x');
      expect(await integrity.isSupported(), isFalse);
    });

    test('prepare returns null when ready, or the failure', () async {
      expect(await integrity.prepare(), isNull);
      expect(platform.lastProjectNumber, 123456789012);
      platform.error = const IntegrityPlatformException(
        IntegrityErrorCodes.playServicesMissing,
      );
      expect(await integrity.prepare(), isA<IntegrityPlayServicesMissing>());
    });

    test('reset swallows errors', () async {
      await integrity.reset();
      platform.error = StateError('x');
      await integrity.reset();
      expect(platform.resets, 2);
    });
  });

  group('PigeonIntegrityPlatform', () {
    late _FakeHostApi api;
    late PigeonIntegrityPlatform pigeon;

    setUp(() {
      api = _FakeHostApi();
      pigeon = PigeonIntegrityPlatform(api: api);
    });

    test('forwards calls and converts messages', () async {
      expect(await pigeon.isSupported(), isTrue);
      await pigeon.prepare(cloudProjectNumber: 42);
      final token = await pigeon.requestToken(
        requestHash: 'h',
        cloudProjectNumber: 42,
      );
      await pigeon.reset();
      expect(token.kind, IntegrityTokenKind.appAttestAssertion);
      expect(token.keyId, 'a2V5LWlk');
      expect(api.calls, [
        'isSupported',
        'prepare:42',
        'requestToken:h:42',
        'reset',
      ]);
    });

    test('converts every token kind', () async {
      for (final (message, kind) in [
        (
          TokenKindMessage.playIntegrityStandard,
          IntegrityTokenKind.playIntegrityStandard,
        ),
        (
          TokenKindMessage.appAttestAttestation,
          IntegrityTokenKind.appAttestAttestation,
        ),
      ]) {
        api.response = TokenMessage(token: 't', kind: message);
        expect((await pigeon.requestToken(requestHash: 'h')).kind, kind);
      }
    });

    test('converts PlatformException with code and details', () async {
      api.error = PlatformException(
        code: IntegrityErrorCodes.network,
        message: 'offline',
        details: '-3',
      );
      final result = await Integrity(platform: pigeon).requestToken('h');
      expect(result, isA<IntegrityNetworkError>());
      expect((result as IntegrityFailure).platformCode, '-3');
    });

    test('missing plugin means unsupported', () async {
      api.error = MissingPluginException('no implementation');
      expect(
        await Integrity(platform: pigeon).requestToken('h'),
        isA<IntegrityUnsupported>(),
      );
      expect(
        () => pigeon.isSupported(),
        throwsA(isA<IntegrityPlatformException>()),
      );
    });

    test('exception toString', () {
      expect(
        const IntegrityPlatformException('x', platformCode: '1').toString(),
        'IntegrityPlatformException(x, 1)',
      );
    });

    test('default constructor uses the generated host api', () {
      expect(PigeonIntegrityPlatform(), isA<IntegrityPlatform>());
      expect(Integrity(), isA<Integrity>());
    });
  });
}

import 'package:compliance_integrity_server/compliance_integrity_server.dart';
import 'package:test/test.dart';

final _now = DateTime.utc(2026, 10, 18, 12);

Map<String, Object?> payload({
  String package = 'com.example.app',
  String hash = 'challenge-1',
  DateTime? issued,
  String recognition = 'PLAY_RECOGNIZED',
  List<String> digests = const ['ZmFrZS1kaWdlc3Q'],
  List<String> device = const ['MEETS_DEVICE_INTEGRITY'],
  String licensing = 'LICENSED',
}) => {
  'requestDetails': {
    'requestPackageName': package,
    'requestHash': hash,
    'timestampMillis': '${(issued ?? _now).millisecondsSinceEpoch}',
  },
  'appIntegrity': {
    'appRecognitionVerdict': recognition,
    if (recognition != 'UNEVALUATED') ...{
      'packageName': package,
      'certificateSha256Digest': digests,
      'versionCode': '42',
    },
  },
  'deviceIntegrity': {'deviceRecognitionVerdict': device},
  'accountDetails': {'appLicensingVerdict': licensing},
};

void main() {
  const policy = PlayIntegrityPolicy(
    packageName: 'com.example.app',
    certificateSha256Digests: {'ZmFrZS1kaWdlc3Q'},
  );

  VerificationResult check(Map<String, Object?> p) =>
      policy.check(p, expectedRequestHash: 'challenge-1', now: _now);

  test('a good verdict passes', () {
    expect(check(payload()).ok, isTrue);
    expect(check(payload()).toJson(), {'ok': true});
  });

  test('each failed check is reported', () {
    expect(check(payload(package: 'com.evil')).failures, [
      'package_name',
      'app_package_name',
    ]);
    expect(check(payload(hash: 'replayed')).failures, ['request_hash']);
    expect(
      check(
        payload(issued: _now.subtract(const Duration(minutes: 3))),
      ).failures,
      ['timestamp'],
    );
    expect(
      check(payload(issued: _now.add(const Duration(minutes: 5)))).failures,
      ['timestamp'],
    );
    expect(check(payload(recognition: 'UNRECOGNIZED_VERSION')).failures, [
      'app_recognition',
    ]);
    expect(check(payload(recognition: 'UNEVALUATED')).failures, [
      'app_recognition',
    ]);
    expect(check(payload(digests: ['b3RoZXI'])).failures, ['certificate']);
    expect(check(payload(device: [])).failures, ['device_integrity']);
    expect(check(payload(licensing: 'UNLICENSED')).failures, ['licensing']);
  });

  test('an empty or garbled payload fails closed', () {
    final result = check({});
    expect(result.ok, isFalse);
    expect(result.toJson()['failures'], contains('request_hash'));
    expect(
      check({
        'requestDetails': {'timestampMillis': 'nope'},
      }).failures,
      contains('timestamp'),
    );
  });

  test('stricter device and relaxed licensing options', () {
    const strict = PlayIntegrityPolicy(
      packageName: 'com.example.app',
      requiredDeviceVerdict: 'MEETS_STRONG_INTEGRITY',
      requireLicensed: false,
    );
    final result = strict.check(
      payload(licensing: 'UNEVALUATED'),
      expectedRequestHash: 'challenge-1',
      now: _now,
    );
    expect(result.failures, ['device_integrity']);
  });
}

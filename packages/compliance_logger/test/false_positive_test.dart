import 'package:compliance_logger/compliance_logger.dart';
import 'package:test/test.dart';

/// Inputs that look numeric or token-like but contain no personal data or
/// secrets. None of them may be changed by the default rules, and IPv4
/// lookalikes are covered separately because that rule is opt-in.
void main() {
  final redactor = Redactor(
    rules: BuiltInRules.defaults(matchNationalPhoneNumbers: true),
  );

  const unchanged = <String, List<String>>{
    'version numbers': [
      'app version 1.2.3',
      'build 10.0.19045.1234',
      'flutter 3.47.7+hotfix.1',
      'v2026.10.18-rc.1',
      'compliance_logger 0.1.0',
    ],
    'dates and times': [
      'on 2026-10-18',
      'on 18.10.2026',
      'on 10/18/2026',
      'at 2026-10-18T11:44:17.533823Z',
      'at 2026-10-18 11:44:17',
      'at 12:30:45.123',
      'duration 00:12:34',
    ],
    'timestamps': [
      'epoch 1760781857',
      'epoch ms 1760781857533',
      'epoch us 1760781857533823',
      'ts=1760781857533',
    ],
    'order and reference ids': [
      'order ORD-2026-000123',
      'order #100234567',
      'invoice INV/2026/00042',
      'ref 2026101800001234',
      'tracking 1Z999AA10123456784',
    ],
    'uuids and hashes': [
      'id 123e4567-e89b-12d3-a456-426614174000',
      'id 123E4567-E89B-12D3-A456-426614174000',
      'sha 9c56cc51b374c3ba189210d5b6d4bf57790d351c96c47c02190ecf1e430635ab',
      'commit 3d3c42e5aac5ba805825da76410c181273ba90b1',
      'md5 d41d8cd98f00b204e9800998ecf8427e',
    ],
    'code and paths': [
      'at package:compliance_logger/src/redaction/redactor.dart:123:45',
      '#0      Redactor._redactText (package:compliance_logger/src/redactor.dart:210:7)',
      'GET https://api.example.com/v1/users/42/orders?page=2&limit=50',
      'class ComplianceLoggerRedactionRuleTest',
      'file /Users/test/AndroidStudioProjects/ComplianceKit/build/outputs',
    ],
    'numbers and amounts': [
      'total 1234.56 EUR',
      'count 1000000',
      'size 4096 bytes, 16384 blocks',
      'coords 52.520008, 13.404954',
      'port 8080',
    ],
  };

  unchanged.forEach((group, inputs) {
    test('does not redact $group', () {
      for (final input in inputs) {
        expect(redactor.redact(input).text, input, reason: input);
      }
    });
  });

  test('IPv4 rule leaves 3-part versions alone', () {
    final ip = Redactor(rules: [const IpAddressRule()]);
    expect(ip.redact('version 1.2.3').text, 'version 1.2.3');
    expect(ip.redact('version 1.2.3-beta').text, 'version 1.2.3-beta');
  });
}

import 'dart:convert';

import 'package:compliance_logger/compliance_logger.dart';
import 'package:test/test.dart';

// All values below are fake or published test values (card network test
// numbers, documentation IBANs, AWS documentation example keys).

String redact(String input, {List<RedactionRule>? rules}) =>
    Redactor(rules: rules).redact(input).text;

// Fake credentials are assembled at runtime so that secret scanners (pub,
// GitHub push protection) do not see a credential-shaped literal.
String _fake(List<String> parts) => parts.join();

final _awsKeyId = _fake(['AK', 'IA', 'IOSFODNN7EXAMPLE']);

String _fakeJwt() {
  String seg(Map<String, Object?> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  return '${seg({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${seg({'sub': 'user-0000', 'name': 'Test User'})}.'
      'dGVzdC1zaWduYXR1cmUtbm90LXJlYWw';
}

void main() {
  group('email', () {
    test('masks addresses', () {
      expect(
        redact('contact jane.doe+tag@example.co.uk now'),
        'contact [REDACTED:email] now',
      );
      expect(redact('a@b.io,c@d.io'), '[REDACTED:email],[REDACTED:email]');
    });

    test('partial mode', () {
      final rules = [const EmailRule(mode: MaskMode.partial)];
      expect(redact('jane@example.com', rules: rules), 'j***@example.com');
    });

    test('ignores non-addresses', () {
      expect(redact('version package@1.2.3'), 'version package@1.2.3');
      expect(redact('@mention and foo@bar'), '@mention and foo@bar');
    });
  });

  group('phone', () {
    for (final phone in [
      '+49 176 1234 5678',
      '+44 20 7946 0958',
      '+1 (555) 123-4567',
      '+92 300 0000000',
      '+33.1.23.45.67.89',
      '0044 20 7946 0958',
      '+4917612345678',
    ]) {
      test('masks $phone', () {
        expect(redact('call $phone today'), 'call [REDACTED:phone] today');
      });
    }

    test('does not swallow a following date', () {
      expect(
        redact('+49 176 12345678 2026-10-18'),
        '[REDACTED:phone] 2026-10-18',
      );
    });

    test('national formats only when enabled', () {
      const input = 'call 030 1234567 or (555) 123-4567';
      expect(redact(input), input);
      expect(
        redact(input, rules: [const PhoneRule(matchNational: true)]),
        'call [REDACTED:phone] or [REDACTED:phone]',
      );
    });

    test('partial mode keeps 3 leading and 2 trailing characters', () {
      final rules = [const PhoneRule(mode: MaskMode.partial)];
      expect(redact('+49 176 1234 5678', rules: rules), '+49*********78');
      expect(const PhoneRule().partialMask('12'), '[REDACTED:phone]');
    });

    test('rejects unbalanced parentheses', () {
      expect(redact('+1 ((555 123 4567'), '+1 ((555 123 4567');
    });
  });

  group('jwt', () {
    test('masks tokens', () {
      final jwt = _fakeJwt();
      expect(redact('token $jwt end'), 'token [REDACTED:jwt] end');
    });

    test('partial keeps header', () {
      final jwt = _fakeJwt();
      final out = redact(jwt, rules: [const JwtRule(mode: MaskMode.partial)]);
      expect(out, '${jwt.split('.').first}.[REDACTED:jwt]');
    });
  });

  group('bearer and authorization', () {
    test('masks Authorization header including scheme', () {
      expect(
        redact('Authorization: Bearer abc123def456ghi'),
        'Authorization: [REDACTED:bearer_token]',
      );
      expect(
        redact('{"authorization": "Token xyz-123"}'),
        '{"authorization": "[REDACTED:bearer_token]"}',
      );
    });

    test('masks bearer tokens in prose', () {
      expect(
        redact('sent bearer abcd1234efgh to api'),
        'sent bearer [REDACTED:bearer_token] to api',
      );
    });

    test('masks basic credentials only when they decode to user:pass', () {
      final creds = base64.encode(utf8.encode('testuser:not-a-real-pass'));
      expect(
        redact('using Basic $creds'),
        'using Basic [REDACTED:bearer_token]',
      );
      expect(
        redact('Basic authentication failed'),
        'Basic authentication failed',
      );
      expect(redact('Basic Zm9vYmFy'), 'Basic Zm9vYmFy');
      expect(redact('Basic Zm9v!!'), 'Basic Zm9v!!');
    });

    test('ignores prose', () {
      expect(
        redact('Bearer authentication required'),
        'Bearer authentication required',
      );
      expect(
        redact('Authorization header missing'),
        'Authorization header missing',
      );
    });
  });

  group('api keys', () {
    test('masks known formats', () {
      final cases = {
        _awsKeyId: 'aws',
        _fake(['AI', 'za', 'SyA-fake_key_0123456789abcdefghijkl']): 'google',
        _fake(['gh', 'p_', 'a1B2' * 9]): 'github',
        _fake(['github', '_pat_', 'Ab1_' * 6]): 'github fine-grained',
        _fake(['sk', '_live_', 'FAKEfake0000FAKEfake']): 'stripe',
        _fake(['xo', 'xb-', '0000000000-fake-token']): 'slack',
        _fake(['sk', '-proj-', 'abcDEF123_' * 3]): 'sk- prefixed',
      };
      cases.forEach((key, label) {
        expect(redact('key=$key'), isNot(contains(key)), reason: label);
        expect(
          redact('value $key here'),
          'value [REDACTED:api_key] here',
          reason: label,
        );
      });
    });

    test('masks PEM private keys', () {
      final pem = _fake([
        '-----BEGIN PRIVATE',
        ' KEY-----\nFAKEFAKEFAKE\n',
        '-----END PRIVATE',
        ' KEY-----',
      ]);
      expect(redact('key: $pem'), 'key: [REDACTED:api_key]');
      expect(
        redact(pem, rules: [const ApiKeyRule(mode: MaskMode.partial)]),
        '[REDACTED:api_key]',
      );
    });

    test('masks generic high-entropy keys', () {
      final secret = _fake(['wJalrXUtnFEMI/K7MDENG', '/bPxRfiCYEXAMPLEKEY']);
      expect(redact('aws secret $secret'), 'aws secret [REDACTED:api_key]');
    });

    test('partial keeps 4 characters', () {
      expect(
        redact(_awsKeyId, rules: [const ApiKeyRule(mode: MaskMode.partial)]),
        'AKIA****',
      );
    });

    test('entropy helper', () {
      expect(ApiKeyRule.shannonEntropy(''), 0);
      expect(ApiKeyRule.shannonEntropy('aaaa'), 0);
      expect(ApiKeyRule.shannonEntropy('abcd'), closeTo(2, 1e-9));
    });
  });

  group('credit card', () {
    for (final card in [
      '4111 1111 1111 1111',
      '4111-1111-1111-1111',
      '4111111111111111',
      '5555555555554444',
      '378282246310005',
      '6011111111111117',
      '3530111333300000',
    ]) {
      test('masks $card', () {
        expect(redact('card $card ok'), 'card [REDACTED:credit_card] ok');
      });
    }

    test('rejects invalid Luhn, mixed separators and unknown prefixes', () {
      expect(redact('4111 1111 1111 1112'), '4111 1111 1111 1112');
      expect(redact('4111 1111-1111 1111'), '4111 1111-1111 1111');
      expect(redact('9111111111111111'), '9111111111111111');
    });

    test('partial keeps last 4 digits', () {
      expect(
        redact(
          '4111 1111 1111 1111',
          rules: [const CreditCardRule(mode: MaskMode.partial)],
        ),
        '****1111',
      );
    });

    test('helpers', () {
      expect(CreditCardRule.luhnValid('79927398713'), isTrue);
      expect(CreditCardRule.luhnValid('79927398710'), isFalse);
      expect(CreditCardRule.isCardNumber('4111'), isFalse);
    });
  });

  group('iban', () {
    for (final iban in [
      'DE89 3704 0044 0532 0130 00',
      'DE89370400440532013000',
      'GB82 WEST 1234 5698 7654 32',
      'NL91ABNA0417164300',
      'FR14 2004 1010 0505 0001 3M02 606',
    ]) {
      test('masks $iban', () {
        expect(redact('pay to $iban EUR'), 'pay to [REDACTED:iban] EUR');
      });
    }

    test('rejects bad checksum, wrong length and unknown country', () {
      expect(
        redact('DE88 3704 0044 0532 0130 00'),
        'DE88 3704 0044 0532 0130 00',
      );
      expect(redact('DE89 3704 0044 0532 0130'), 'DE89 3704 0044 0532 0130');
      expect(redact('ZZ89370400440532013000'), 'ZZ89370400440532013000');
      expect(redact('DE89370400440532013000X'), 'DE89370400440532013000X');
    });

    test('partial keeps country and last 4', () {
      expect(
        redact(
          'DE89 3704 0044 0532 0130 00',
          rules: [const IbanRule(mode: MaskMode.partial)],
        ),
        'DE****3000',
      );
    });

    test('validator', () {
      expect(IbanRule.isValidIban('de89370400440532013000'), isTrue);
      expect(IbanRule.isValidIban('DE8'), isFalse);
      expect(IbanRule.isValidIban('DE89-70400440532013000'), isFalse);
    });
  });

  group('ip address', () {
    test('is off by default', () {
      expect(redact('from 192.168.1.20'), 'from 192.168.1.20');
    });

    final rules = [const IpAddressRule()];
    test('masks IPv4 and IPv6 when enabled', () {
      expect(
        redact('from 192.168.1.20.', rules: rules),
        'from [REDACTED:ip_address].',
      );
      expect(
        redact('from 2001:db8::8a2e:370:7334', rules: rules),
        'from [REDACTED:ip_address]',
      );
      expect(redact('from ::1', rules: rules), 'from [REDACTED:ip_address]');
      expect(redact('at 12:30:45', rules: rules), 'at 12:30:45');
      expect(redact('bad 999.1.1.1', rules: rules), 'bad 999.1.1.1');
    });

    test('partial', () {
      final partial = [const IpAddressRule(mode: MaskMode.partial)];
      expect(redact('192.168.1.20', rules: partial), '192.168.*.*');
      expect(redact('2001:db8::1', rules: partial), '2001:db8:*');
    });
  });

  group('sensitive fields', () {
    test('key=value, query string and colon forms', () {
      expect(redact('password=hunter2'), 'password=[REDACTED:sensitive_field]');
      expect(
        redact('GET /login?user=test&password=hunter2&x=1'),
        'GET /login?user=test&password=[REDACTED:sensitive_field]&x=1',
      );
      expect(
        redact('client_secret: abc'),
        'client_secret: [REDACTED:sensitive_field]',
      );
      expect(redact('API-KEY = abc'), 'API-KEY = [REDACTED:sensitive_field]');
    });

    test('JSON and quoted forms', () {
      expect(
        redact('{"user":"test","password":"hun ter\\"2","pin": 1234}'),
        '{"user":"test","password":"[REDACTED:sensitive_field]",'
        '"pin": [REDACTED:sensitive_field]}',
      );
      expect(redact("pwd='a b'"), "pwd='[REDACTED:sensitive_field]'");
    });

    test('ignores non-sensitive keys and empty values', () {
      expect(redact('shipping=express'), 'shipping=express');
      expect(redact('password=""'), 'password=""');
      expect(redact('status: ok'), 'status: ok');
    });

    test('custom keys', () {
      final rules = [
        SensitiveFieldRule(
          keys: SensitiveKeys.defaults.withAdditional(exact: ['employee_no']),
        ),
      ];
      expect(
        redact('employee_no=12', rules: rules),
        'employee_no=[REDACTED:sensitive_field]',
      );
    });
  });

  group('SensitiveKeys', () {
    test('normalises and matches', () {
      final keys = SensitiveKeys.defaults;
      expect(keys.matches('API_KEY'), isTrue);
      expect(keys.matches('userPassword'), isTrue);
      expect(keys.matches('x-auth-token'), isTrue);
      expect(keys.matches('PIN'), isTrue);
      expect(keys.matches('shipping'), isFalse);
      expect(keys.matches('---'), isFalse);
      expect(SensitiveKeys.normalize('Api-Key_1'), 'apikey1');
    });
  });
}

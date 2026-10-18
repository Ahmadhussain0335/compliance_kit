import 'redaction_rule.dart';
import 'rules/api_key_rule.dart';
import 'rules/bearer_token_rule.dart';
import 'rules/credit_card_rule.dart';
import 'rules/email_rule.dart';
import 'rules/iban_rule.dart';
import 'rules/ip_address_rule.dart';
import 'rules/jwt_rule.dart';
import 'rules/phone_rule.dart';
import 'rules/sensitive_field_rule.dart';
import 'sensitive_keys.dart';

/// Factory for the built-in rule set.
abstract final class BuiltInRules {
  /// Returns the built-in rules in the order they run.
  ///
  /// Every rule is enabled with [MaskMode.full] except [IpAddressRule],
  /// which is disabled. Pass [RuleSettings] to change a rule, for example:
  ///
  /// ```dart
  /// BuiltInRules.defaults(
  ///   email: const RuleSettings(mode: MaskMode.partial),
  ///   ipAddress: const RuleSettings(),
  ///   phone: RuleSettings.disabled,
  /// );
  /// ```
  ///
  /// Order matters: context rules (authorization headers, sensitive fields)
  /// run first so they can mask a whole value before a narrower rule masks
  /// only part of it.
  static List<RedactionRule> defaults({
    RuleSettings bearerToken = const RuleSettings(),
    RuleSettings sensitiveField = const RuleSettings(),
    RuleSettings jwt = const RuleSettings(),
    RuleSettings apiKey = const RuleSettings(),
    RuleSettings iban = const RuleSettings(),
    RuleSettings creditCard = const RuleSettings(),
    RuleSettings email = const RuleSettings(),
    RuleSettings phone = const RuleSettings(),
    RuleSettings ipAddress = RuleSettings.disabled,
    SensitiveKeys? sensitiveKeys,
    bool matchNationalPhoneNumbers = false,
  }) => [
    BearerTokenRule(enabled: bearerToken.enabled, mode: bearerToken.mode),
    SensitiveFieldRule(
      keys: sensitiveKeys,
      enabled: sensitiveField.enabled,
      mode: sensitiveField.mode,
    ),
    JwtRule(enabled: jwt.enabled, mode: jwt.mode),
    ApiKeyRule(enabled: apiKey.enabled, mode: apiKey.mode),
    IbanRule(enabled: iban.enabled, mode: iban.mode),
    CreditCardRule(enabled: creditCard.enabled, mode: creditCard.mode),
    EmailRule(enabled: email.enabled, mode: email.mode),
    PhoneRule(
      enabled: phone.enabled,
      mode: phone.mode,
      matchNational: matchNationalPhoneNumbers,
    ),
    IpAddressRule(enabled: ipAddress.enabled, mode: ipAddress.mode),
  ];
}

/// A PII-redacting logger for Dart and Flutter.
///
/// `ComplianceLogger` passes every message, error, stack trace and
/// structured field through a `Redactor` before any `LogSink` receives it.
/// See `BuiltInRules.defaults` for the built-in rules.
library;

export 'src/compliance_logger.dart';
export 'src/log_level.dart';
export 'src/log_record.dart';
export 'src/redaction/built_in_rules.dart';
export 'src/redaction/masker.dart';
export 'src/redaction/redaction_rule.dart';
export 'src/redaction/redactor.dart';
export 'src/redaction/rules/api_key_rule.dart';
export 'src/redaction/rules/bearer_token_rule.dart';
export 'src/redaction/rules/credit_card_rule.dart';
export 'src/redaction/rules/email_rule.dart';
export 'src/redaction/rules/iban_rule.dart';
export 'src/redaction/rules/ip_address_rule.dart';
export 'src/redaction/rules/jwt_rule.dart';
export 'src/redaction/rules/phone_rule.dart';
export 'src/redaction/rules/sensitive_field_rule.dart';
export 'src/redaction/sensitive_keys.dart';
export 'src/sinks.dart';

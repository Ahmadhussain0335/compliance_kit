import 'package:compliance_core/compliance_core.dart';

final RegExp _idPattern = RegExp(r'^[a-z][a-z0-9_]*$');

/// A reason for processing personal data that the user can consent to, for
/// example `analytics` or `marketing`.
final class ConsentPurpose {
  /// Creates a purpose.
  ///
  /// [id] must be a lowercase identifier (`[a-z][a-z0-9_]*`, at most 48
  /// characters). It is stored with consent records and in audit events.
  /// [title] and [description] are shown to the user; pass localized text.
  ///
  /// Set [required] only for purposes that are strictly necessary for the
  /// service the user asked for. Required purposes are always active, are
  /// not based on consent, and cannot be switched off.
  ///
  /// Throws [InvalidConfigurationException] for an invalid [id].
  ConsentPurpose({
    required this.id,
    required this.title,
    required this.description,
    this.required = false,
  }) {
    if (!_idPattern.hasMatch(id) || id.length > 48) {
      throw InvalidConfigurationException(
        'Purpose id "$id" must match [a-z][a-z0-9_]* and be at most 48 '
        'characters.',
      );
    }
  }

  /// Stable identifier, for example `analytics`.
  final String id;

  /// Short user-facing name.
  final String title;

  /// User-facing explanation of what the data is used for.
  final String description;

  /// Whether the purpose is strictly necessary and always active.
  final bool required;
}

/// The set of purposes the app asks consent for, with a version.
///
/// Change [version] whenever the purposes or their descriptions change in a
/// way that requires asking the user again. Consent given under an older
/// version is not treated as valid for the current one.
final class ConsentPolicy {
  /// Creates a policy.
  ///
  /// Throws [InvalidConfigurationException] if [version] is empty or longer
  /// than 64 characters, or if purpose ids are not unique.
  ConsentPolicy({required this.version, required List<ConsentPurpose> purposes})
    : purposes = List.unmodifiable(purposes) {
    if (version.isEmpty || version.length > 64) {
      throw const InvalidConfigurationException(
        'Policy version must be 1-64 characters.',
      );
    }
    final ids = <String>{};
    for (final purpose in purposes) {
      if (!ids.add(purpose.id)) {
        throw InvalidConfigurationException(
          'Duplicate purpose id "${purpose.id}".',
        );
      }
    }
  }

  /// Policy version, for example `2026-10` or `3`.
  final String version;

  /// All purposes in display order.
  final List<ConsentPurpose> purposes;

  /// Purposes the user can grant or deny.
  List<ConsentPurpose> get optionalPurposes => [
    for (final p in purposes)
      if (!p.required) p,
  ];

  /// Returns the purpose with [id], or `null`.
  ConsentPurpose? purpose(String id) {
    for (final p in purposes) {
      if (p.id == id) return p;
    }
    return null;
  }
}

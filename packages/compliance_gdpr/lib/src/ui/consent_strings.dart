/// Every user-facing string in the consent UI.
///
/// The defaults are English. Pass translated values from your app's
/// localization to support other languages. Purpose titles and descriptions
/// come from `ConsentPurpose` and should be localized there.
final class ConsentStrings {
  /// Creates strings, defaulting to English.
  const ConsentStrings({
    this.promptTitle = 'Your privacy choices',
    this.promptBody =
        'We would like to use your data for the purposes below. You can '
        'accept or reject them all, or choose individually. You can change '
        'your choices at any time in the privacy settings.',
    this.acceptAll = 'Accept all',
    this.rejectAll = 'Reject all',
    this.customize = 'Choose individually',
    this.settingsTitle = 'Privacy settings',
    this.settingsIntro =
        'Turn each purpose on or off. Changes apply immediately.',
    this.alwaysActive = 'Always active',
    this.requiredSectionTitle = 'Strictly necessary',
    this.optionalSectionTitle = 'Optional',
    this.confirmChoices = 'Confirm choices',
    this.policyChangedNotice =
        'Our privacy policy has changed. Please review your choices.',
  });

  /// Title of the consent prompt.
  final String promptTitle;

  /// Body text of the consent prompt.
  final String promptBody;

  /// Label of the button that grants every optional purpose.
  final String acceptAll;

  /// Label of the button that denies every optional purpose.
  final String rejectAll;

  /// Label of the button that opens the per-purpose settings.
  final String customize;

  /// Title of the privacy settings screen.
  final String settingsTitle;

  /// Introductory text on the privacy settings screen.
  final String settingsIntro;

  /// Shown instead of a switch for required purposes.
  final String alwaysActive;

  /// Heading above required purposes.
  final String requiredSectionTitle;

  /// Heading above optional purposes.
  final String optionalSectionTitle;

  /// Button on the settings screen that stores the current switch positions
  /// while consent is still needed.
  final String confirmChoices;

  /// Notice shown when the policy version changed.
  final String policyChangedNotice;

  /// Returns a copy with the given values replaced.
  ConsentStrings copyWith({
    String? promptTitle,
    String? promptBody,
    String? acceptAll,
    String? rejectAll,
    String? customize,
    String? settingsTitle,
    String? settingsIntro,
    String? alwaysActive,
    String? requiredSectionTitle,
    String? optionalSectionTitle,
    String? confirmChoices,
    String? policyChangedNotice,
  }) => ConsentStrings(
    promptTitle: promptTitle ?? this.promptTitle,
    promptBody: promptBody ?? this.promptBody,
    acceptAll: acceptAll ?? this.acceptAll,
    rejectAll: rejectAll ?? this.rejectAll,
    customize: customize ?? this.customize,
    settingsTitle: settingsTitle ?? this.settingsTitle,
    settingsIntro: settingsIntro ?? this.settingsIntro,
    alwaysActive: alwaysActive ?? this.alwaysActive,
    requiredSectionTitle: requiredSectionTitle ?? this.requiredSectionTitle,
    optionalSectionTitle: optionalSectionTitle ?? this.optionalSectionTitle,
    confirmChoices: confirmChoices ?? this.confirmChoices,
    policyChangedNotice: policyChangedNotice ?? this.policyChangedNotice,
  );
}

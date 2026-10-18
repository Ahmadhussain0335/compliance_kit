import 'package:compliance_gdpr/compliance_gdpr.dart';

ConsentPolicy testPolicy({String version = '1'}) => ConsentPolicy(
  version: version,
  purposes: [
    ConsentPurpose(
      id: 'essential',
      title: 'Essential',
      description: 'Needed to run the app.',
      required: true,
    ),
    ConsentPurpose(
      id: 'analytics',
      title: 'Analytics',
      description: 'Helps us improve the app.',
    ),
    ConsentPurpose(
      id: 'marketing',
      title: 'Marketing',
      description: 'Personalised offers.',
    ),
  ],
);

/// A clock that advances one second per call, starting at a fixed time.
DateTime Function() steppingClock() {
  var t = DateTime.utc(2026, 10, 18, 12);
  return () => t = t.add(const Duration(seconds: 1));
}

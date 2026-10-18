// ignore_for_file: avoid_print

import 'package:compliance_core/compliance_core.dart';

Future<void> main() async {
  final trail = InMemoryAuditTrail(maxEvents: 1000);

  final subscription = trail.events.listen(
    (event) => print('audit: ${event.type} from ${event.source}'),
  );

  // Record what happened, never who it happened to.
  await trail.record(
    AuditEvent(
      type: 'consent_granted',
      source: 'example_app',
      metadata: const {'purpose': 'analytics', 'policy_version': 3},
    ),
  );

  try {
    AuditEvent(
      type: 'profile_updated',
      source: 'example_app',
      // Nested objects are rejected so they cannot be dumped by accident.
      metadata: const {
        'user': {'email': 'jane.doe@example.com'},
      },
    );
  } on InvalidAuditEventException catch (e) {
    print('rejected: ${e.message}');
  }

  for (final event in trail.history) {
    print(event.toJson());
  }

  await subscription.cancel();
  await trail.dispose();
}

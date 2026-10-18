import 'package:compliance_core/compliance_core.dart';
import 'package:compliance_gdpr/compliance_gdpr.dart';
import 'package:compliance_gdpr_example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows the consent dialog on first launch and reacts to it', (
    tester,
  ) async {
    final audit = InMemoryAuditTrail();
    final consent = ConsentManager(
      policy: ConsentPolicy(
        version: '1',
        purposes: [
          ConsentPurpose(id: 'analytics', title: 'Analytics', description: 'd'),
        ],
      ),
      auditTrail: audit,
    );
    await consent.initialize();

    await tester.pumpWidget(
      ExampleApp(
        consent: consent,
        exporter: DataExporter(appId: 'test'),
        deletion: DataDeletionManager(),
        audit: audit,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('Stopped'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('consent_accept_all')));
    await tester.pumpAndSettle();
    expect(find.text('Running'), findsOneWidget);
  });
}

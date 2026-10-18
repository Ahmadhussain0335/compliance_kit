import 'package:compliance_kit/compliance_kit.dart';
import 'package:compliance_kit_example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeIntegrity implements IntegrityPlatform {
  @override
  Future<bool> isSupported() async => true;

  @override
  Future<void> prepare({int? cloudProjectNumber}) async {}

  @override
  Future<PlatformToken> requestToken({
    required String requestHash,
    int? cloudProjectNumber,
  }) async => const PlatformToken(
    token: 'ZmFrZQ',
    kind: IntegrityTokenKind.playIntegrityStandard,
  );

  @override
  Future<void> reset() async {}
}

void main() {
  testWidgets('consent prompt, integrity check and audit trail', (
    tester,
  ) async {
    final kit = await createKit(integrityPlatform: _FakeIntegrity());
    await tester.pumpWidget(ExampleApp(kit: kit));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('consent_reject_all')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Integrity check'));
    await tester.pumpAndSettle();
    expect(find.text('Integrity: success'), findsOneWidget);

    await tester.tap(find.text('Show audit trail'));
    await tester.pumpAndSettle();
    expect(find.textContaining('integrity_check_passed'), findsOneWidget);
    expect(find.textContaining('consent_denied'), findsWidgets);
  });
}

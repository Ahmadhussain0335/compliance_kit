import 'package:compliance_integrity/compliance_integrity.dart';
import 'package:compliance_integrity_example/main.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakePlatform implements IntegrityPlatform {
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
  testWidgets('shows the token kind after a request', (tester) async {
    await tester.pumpWidget(
      ExampleApp(integrity: Integrity(platform: _FakePlatform())),
    );
    await tester.tap(find.text('Request integrity token'));
    await tester.pumpAndSettle();
    expect(find.textContaining('playIntegrityStandard'), findsOneWidget);
  });
}

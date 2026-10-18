import 'package:compliance_gdpr/compliance_gdpr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

Future<ConsentManager> _manager({
  String version = '1',
  List<ConsentRecord> history = const [],
}) async {
  final manager = ConsentManager(
    policy: testPolicy(version: version),
    store: InMemoryConsentStore(history),
    clock: steppingClock(),
  );
  await manager.initialize();
  return manager;
}

/// Hosts a button that opens the consent prompt with [open].
Widget _host(
  Future<void> Function(BuildContext context) open, {
  double textScale = 1,
}) => MaterialApp(
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => open(context),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  group('consent dialog', () {
    testWidgets('accept all grants every optional purpose and closes', (
      tester,
    ) async {
      final manager = await _manager();
      await tester.pumpWidget(
        _host((c) => showConsentDialog(c, manager: manager)),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Your privacy choices'), findsOneWidget);
      expect(find.text('Analytics'), findsOneWidget);
      expect(find.text('Essential'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('consent_accept_all')));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsNothing);
      expect(manager.isGranted('analytics'), isTrue);
      expect(manager.isGranted('marketing'), isTrue);
      expect(manager.state.needsConsent, isFalse);
    });

    testWidgets('reject all is one tap and denies everything optional', (
      tester,
    ) async {
      final manager = await _manager();
      await tester.pumpWidget(
        _host((c) => showConsentDialog(c, manager: manager)),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('consent_reject_all')));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsNothing);
      expect(manager.state.grantedPurposeIds, {'essential'});
      expect(manager.state.needsConsent, isFalse);
    });

    testWidgets('dialog cannot be dismissed without a choice', (tester) async {
      final manager = await _manager();
      await tester.pumpWidget(
        _host((c) => showConsentDialog(c, manager: manager)),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
    });

    testWidgets('accept and reject have equal visual weight', (tester) async {
      final manager = await _manager();
      await tester.pumpWidget(
        _host((c) => showConsentDialog(c, manager: manager)),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final accept = find.byKey(const ValueKey('consent_accept_all'));
      final reject = find.byKey(const ValueKey('consent_reject_all'));
      expect(
        tester.widget(accept).runtimeType,
        tester.widget(reject).runtimeType,
      );
      expect(tester.getSize(accept), tester.getSize(reject));
      final acceptStyle = (tester.widget(accept) as ButtonStyleButton).style;
      final rejectStyle = (tester.widget(reject) as ButtonStyleButton).style;
      expect(acceptStyle, rejectStyle);
    });

    testWidgets('custom strings and a shared button style are used', (
      tester,
    ) async {
      final manager = await _manager();
      final style = FilledButton.styleFrom(minimumSize: const Size(10, 60));
      await tester.pumpWidget(
        _host(
          (c) => showConsentDialog(
            c,
            manager: manager,
            buttonStyle: style,
            strings: const ConsentStrings().copyWith(
              promptTitle: 'Datenschutz',
              acceptAll: 'Alle akzeptieren',
              rejectAll: 'Alle ablehnen',
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Datenschutz'), findsOneWidget);
      expect(find.text('Alle akzeptieren'), findsOneWidget);
      expect(find.text('Alle ablehnen'), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const ValueKey('consent_accept_all'))).height,
        60,
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('consent_reject_all'))).height,
        60,
      );
    });

    testWidgets('choose individually, then confirm', (tester) async {
      final manager = await _manager();
      await tester.pumpWidget(
        _host((c) => showConsentDialog(c, manager: manager)),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('consent_customize')));
      await tester.pumpAndSettle();

      expect(find.text('Privacy settings'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('consent_switch_analytics')));
      await tester.pumpAndSettle();
      expect(manager.isGranted('analytics'), isTrue);
      expect(manager.state.needsConsent, isTrue);

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('consent_confirm_choices')),
        100,
      );
      await tester.tap(find.byKey(const ValueKey('consent_confirm_choices')));
      await tester.pumpAndSettle();

      expect(find.text('Privacy settings'), findsNothing);
      expect(find.byType(Dialog), findsNothing);
      expect(manager.isGranted('analytics'), isTrue);
      expect(manager.isGranted('marketing'), isFalse);
      expect(manager.state.hasDecided('marketing'), isTrue);
      expect(manager.state.needsConsent, isFalse);
    });

    testWidgets('going back from settings without confirming keeps prompt', (
      tester,
    ) async {
      final manager = await _manager();
      await tester.pumpWidget(
        _host((c) => showConsentDialog(c, manager: manager)),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('consent_customize')));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
    });

    testWidgets('shows a notice when the policy changed', (tester) async {
      final manager = await _manager(
        version: '2',
        history: [
          ConsentRecord(
            purposeId: 'analytics',
            granted: true,
            timestamp: DateTime.utc(2026),
            policyVersion: '1',
          ),
        ],
      );
      await tester.pumpWidget(
        _host((c) => showConsentDialog(c, manager: manager)),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(
        find.text(const ConsentStrings().policyChangedNotice),
        findsOneWidget,
      );
    });
  });

  group('bottom sheet', () {
    testWidgets('reject from the bottom sheet', (tester) async {
      final manager = await _manager();
      await tester.pumpWidget(
        _host((c) => showConsentBottomSheet(c, manager: manager)),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('consent_reject_all')));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(manager.state.needsConsent, isFalse);
    });
  });

  group('privacy settings screen', () {
    testWidgets('withdrawing is a single toggle and applies immediately', (
      tester,
    ) async {
      final manager = await _manager();
      await manager.acceptAll();
      await tester.pumpWidget(
        MaterialApp(home: PrivacySettingsScreen(manager: manager)),
      );
      expect(
        find.byKey(const ValueKey('consent_confirm_choices')),
        findsNothing,
      );

      final analytics = find.byKey(const ValueKey('consent_switch_analytics'));
      expect(tester.widget<SwitchListTile>(analytics).value, isTrue);
      await tester.tap(analytics);
      await tester.pumpAndSettle();

      expect(manager.isGranted('analytics'), isFalse);
      expect(tester.widget<SwitchListTile>(analytics).value, isFalse);
      final history = await manager.history();
      expect(history.last.granted, isFalse);
    });

    testWidgets('required purposes are always active without a switch', (
      tester,
    ) async {
      final manager = await _manager();
      await tester.pumpWidget(
        MaterialApp(home: PrivacySettingsScreen(manager: manager)),
      );
      expect(
        find.byKey(const ValueKey('consent_required_essential')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('consent_switch_essential')),
        findsNothing,
      );
      expect(find.text('Always active'), findsOneWidget);
    });

    testWidgets('switches expose the purpose title to screen readers', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final manager = await _manager();
      await tester.pumpWidget(
        MaterialApp(home: PrivacySettingsScreen(manager: manager)),
      );
      final node = tester.getSemantics(
        find.byKey(const ValueKey('consent_switch_analytics')),
      );
      expect(node.label, contains('Analytics'));
      expect(node.flagsCollection.isToggled, isNotNull);
      expect(
        find.bySemanticsLabel(RegExp('Strictly necessary')),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  group('large text and narrow screens', () {
    testWidgets('buttons stack and nothing overflows at 2x text', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final manager = await _manager();
      await tester.pumpWidget(
        _host((c) => showConsentDialog(c, manager: manager), textScale: 2),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final accept = tester.getRect(
        find.byKey(const ValueKey('consent_accept_all')),
      );
      final reject = tester.getRect(
        find.byKey(const ValueKey('consent_reject_all')),
      );
      expect(accept.top, greaterThan(reject.top));
      expect(accept.width, reject.width);

      await tester.ensureVisible(
        find.byKey(const ValueKey('consent_reject_all')),
      );
      await tester.tap(find.byKey(const ValueKey('consent_reject_all')));
      await tester.pumpAndSettle();
      expect(manager.state.needsConsent, isFalse);
    });

    testWidgets('buttons sit side by side on wide screens', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final manager = await _manager();
      await tester.pumpWidget(
        _host((c) => showConsentDialog(c, manager: manager)),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final accept = tester.getRect(
        find.byKey(const ValueKey('consent_accept_all')),
      );
      final reject = tester.getRect(
        find.byKey(const ValueKey('consent_reject_all')),
      );
      expect(accept.top, reject.top);
      expect(accept.left, greaterThan(reject.left));
    });

    testWidgets('disabled while busy when callbacks are null', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ConsentChoiceButtons(
              acceptLabel: 'a',
              rejectLabel: 'r',
              onAccept: null,
              onReject: null,
            ),
          ),
        ),
      );
      final accept = tester.widget<ButtonStyleButton>(
        find.byKey(const ValueKey('consent_accept_all')),
      );
      expect(accept.onPressed, isNull);
    });
  });
}

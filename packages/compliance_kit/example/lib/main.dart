import 'dart:convert';
import 'dart:math';

import 'package:compliance_kit/compliance_kit.dart';
import 'package:flutter/material.dart';

const int _cloudProjectNumber = int.fromEnvironment('CLOUD_PROJECT_NUMBER');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final kit = await createKit();
  runApp(ExampleApp(kit: kit));
}

/// Builds the kit. All data in this example is fake and kept in memory.
Future<ComplianceKit> createKit({IntegrityPlatform? integrityPlatform}) async {
  final forwarded = <String>[];
  final kit = await ComplianceKit.init(
    appId: 'compliance_kit_example',
    consentPolicy: ConsentPolicy(
      version: '2026-10',
      purposes: [
        ConsentPurpose(
          id: 'essential',
          title: 'Essential',
          description: 'Sign-in and security. Required to use the app.',
          required: true,
        ),
        ConsentPurpose(
          id: 'crash_reporting',
          title: 'Crash reports',
          description: 'Send redacted error logs so we can fix bugs.',
        ),
        ConsentPurpose(
          id: 'analytics',
          title: 'Analytics',
          description: 'Usage statistics to improve the app.',
        ),
      ],
    ),
    // Stand-in for a crash reporter. Only receives redacted records, and
    // only while crash_reporting consent is granted.
    forwardLogs: (record) => forwarded.add(record.message),
    forwardLogsPurpose: 'crash_reporting',
    serverDeletion: () async => ErasureStatus.deleted,
    eraseConsentOnDeletion: true,
    cloudProjectNumber: _cloudProjectNumber == 0 ? null : _cloudProjectNumber,
    integrityPlatform: integrityPlatform,
  );
  final profile = <String, Object?>{
    'display_name': 'Test User',
    'email': 'test.user@example.com',
  };
  kit.exporter.register(CallbackDataSource('profile', () async => profile));
  kit.deletion.register(
    CallbackDataEraser('profile', () async {
      if (profile.isEmpty) return ErasureStatus.skipped;
      profile.clear();
      return ErasureStatus.deleted;
    }),
  );
  return kit;
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({required this.kit, super.key});

  final ComplianceKit kit;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'compliance_kit example',
    theme: ThemeData(colorSchemeSeed: Colors.blueGrey),
    home: HomeScreen(kit: kit),
  );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({required this.kit, super.key});

  final ComplianceKit kit;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _output = '';

  ComplianceKit get kit => widget.kit;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final consent = kit.consent!;
      if (mounted && consent.state.needsConsent) {
        await showConsentDialog(context, manager: consent);
      }
    });
  }

  void _show(String text) {
    if (mounted) setState(() => _output = text);
  }

  void _log() {
    kit.logger.error(
      'Payment failed for test.user@example.com, card 4111 1111 1111 1111',
      fields: {'password': 'not-a-real-password', 'attempt': 2},
    );
    _show('Logged an error. Check the console: values are redacted.');
  }

  Future<void> _integrity() async {
    // DEMO ONLY: the request hash must come from your server.
    final random = Random.secure();
    final hash = base64Url
        .encode(List<int>.generate(32, (_) => random.nextInt(256)))
        .replaceAll('=', '');
    final result = await kit.integrity.requestToken(hash);
    _show('Integrity: ${result.resultType}');
  }

  Future<void> _export() async {
    final export = await kit.exporter.export();
    _show(export.toJsonString());
  }

  Future<void> _delete() async {
    final report = await kit.deletion.deleteAll(
      confirm: () async =>
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Delete account?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Delete'),
                ),
              ],
            ),
          ) ??
          false,
    );
    _show(
      report.cancelled
          ? 'Cancelled'
          : [
              for (final s in report.steps) '${s.id}: ${s.status.name}',
            ].join('\n'),
    );
  }

  void _audit() {
    final trail = kit.auditTrail as InMemoryAuditTrail;
    _show(
      [
        for (final e in trail.history)
          '${e.timestamp.toIso8601String()} ${e.source} ${e.type} ${e.metadata}',
      ].join('\n'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final actions = <(String, VoidCallback)>[
      ('Log an error with PII', _log),
      (
        'Privacy settings',
        () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => PrivacySettingsScreen(manager: kit.consent!),
          ),
        ),
      ),
      ('Integrity check', _integrity),
      ('Export my data', _export),
      ('Delete my account', _delete),
      ('Show audit trail', _audit),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('compliance_kit example')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final (label, action) in actions) ...[
            FilledButton.tonal(onPressed: action, child: Text(label)),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 8),
          SelectableText(_output, key: const ValueKey('output')),
        ],
      ),
    );
  }
}

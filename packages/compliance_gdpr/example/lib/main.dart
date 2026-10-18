import 'dart:async';

import 'package:compliance_core/compliance_core.dart';
import 'package:compliance_gdpr/compliance_gdpr.dart';
import 'package:compliance_logger/compliance_logger.dart';
import 'package:flutter/material.dart';

/// Fake in-memory "database" for the demo. All values are fake.
class DemoDatabase {
  Map<String, Object?>? profile = {
    'display_name': 'Test User',
    'email': 'test.user@example.com',
    'created_at': '2026-01-01T00:00:00Z',
  };
  List<String>? notes = [
    'Buy milk',
    'Call support about order ORD-2026-000123',
  ];
  List<String> supportLog = [
    'Ticket assigned to agent other.agent@example.com',
    'Customer asked to be called on +44 20 7946 0958',
  ];

  Future<ErasureStatus> wipeProfile() async {
    if (profile == null) return ErasureStatus.skipped;
    profile = null;
    return ErasureStatus.deleted;
  }

  Future<ErasureStatus> wipeNotes() async {
    if (notes == null) return ErasureStatus.skipped;
    notes = null;
    return ErasureStatus.deleted;
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final audit = InMemoryAuditTrail(maxEvents: 500);
  final db = DemoDatabase();

  final consent = ConsentManager(
    policy: ConsentPolicy(
      version: '2026-10',
      purposes: [
        ConsentPurpose(
          id: 'essential',
          title: 'Essential',
          description: 'Sign-in and security. Required to use the app.',
          required: true,
        ),
        ConsentPurpose(
          id: 'analytics',
          title: 'Analytics',
          description: 'Anonymous usage statistics to improve the app.',
        ),
        ConsentPurpose(
          id: 'crash_reporting',
          title: 'Crash reports',
          description: 'Send crash details so we can fix bugs.',
        ),
        ConsentPurpose(
          id: 'marketing',
          title: 'Marketing',
          description: 'Personalised offers and newsletters.',
        ),
      ],
    ),
    // Replace with a persistent ConsentStore in a real app.
    store: InMemoryConsentStore(),
    auditTrail: audit,
  );
  await consent.initialize();

  final exporter =
      DataExporter(appId: 'compliance_gdpr_example', auditTrail: audit)
        ..register(CallbackDataSource('profile', () async => db.profile))
        ..register(CallbackDataSource('notes', () async => db.notes))
        ..register(
          // The support log mentions other people; redact them before export.
          RedactingDataSource(
            CallbackDataSource('support_log', () async => db.supportLog),
            Redactor(),
          ),
        );

  final deletion =
      DataDeletionManager(
          // Replace with a call to your backend's account deletion endpoint.
          // Return skipped when the account is already gone (404/401).
          serverDeletion: () => Future.delayed(
            const Duration(milliseconds: 500),
            () => ErasureStatus.deleted,
          ),
          auditTrail: audit,
        )
        ..register(CallbackDataEraser('profile', db.wipeProfile))
        ..register(CallbackDataEraser('notes', db.wipeNotes))
        // Whether consent records must be kept as proof of consent after an
        // erasure request is a legal decision; this demo deletes them.
        ..register(
          CallbackDataEraser('consent_records', () async {
            await consent.reset();
            return ErasureStatus.deleted;
          }),
        );

  runApp(
    ExampleApp(
      consent: consent,
      exporter: exporter,
      deletion: deletion,
      audit: audit,
    ),
  );
}

/// Root widget of the example.
class ExampleApp extends StatelessWidget {
  /// Creates the app.
  const ExampleApp({
    required this.consent,
    required this.exporter,
    required this.deletion,
    required this.audit,
    super.key,
  });

  /// Consent manager.
  final ConsentManager consent;

  /// Data exporter.
  final DataExporter exporter;

  /// Deletion manager.
  final DataDeletionManager deletion;

  /// Shared audit trail.
  final InMemoryAuditTrail audit;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'compliance_gdpr example',
    theme: ThemeData(colorSchemeSeed: Colors.indigo),
    home: HomeScreen(
      consent: consent,
      exporter: exporter,
      deletion: deletion,
      audit: audit,
    ),
  );
}

/// Shows consent status and the export and deletion actions.
class HomeScreen extends StatefulWidget {
  /// Creates the screen.
  const HomeScreen({
    required this.consent,
    required this.exporter,
    required this.deletion,
    required this.audit,
    super.key,
  });

  /// Consent manager.
  final ConsentManager consent;

  /// Data exporter.
  final DataExporter exporter;

  /// Deletion manager.
  final DataDeletionManager deletion;

  /// Shared audit trail.
  final InMemoryAuditTrail audit;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  StreamSubscription<bool>? _analytics;
  bool _analyticsRunning = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    // Start or stop analytics as soon as consent changes.
    _analytics = widget.consent.watch('analytics').listen((granted) {
      if (mounted) setState(() => _analyticsRunning = granted);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted && widget.consent.state.needsConsent) {
        await showConsentDialog(context, manager: widget.consent);
      }
    });
  }

  @override
  void dispose() {
    unawaited(_analytics?.cancel());
    super.dispose();
  }

  Future<void> _export() async {
    final export = await widget.exporter.export(
      onProgress: (p) {
        if (mounted) {
          setState(() => _status = 'Exporting ${p.completed}/${p.total}...');
        }
      },
    );
    if (!mounted) return;
    setState(
      () => _status = export.isComplete
          ? 'Export complete: ${export.suggestedFileName}'
          : 'Export finished with ${export.failures.length} failed source(s)',
    );
    // A real app would write the file and open the share sheet.
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            _TextScreen(title: 'Exported data', text: export.toJsonString()),
      ),
    );
  }

  Future<void> _delete() async {
    final report = await widget.deletion.deleteAll(
      confirm: () async =>
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Delete account?'),
              content: const Text(
                'This deletes your account and all data on this device. '
                'It cannot be undone.',
              ),
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
    if (!mounted) return;
    setState(() {
      _status = report.cancelled
          ? 'Deletion cancelled'
          : [
              for (final step in report.steps)
                '${step.id}: ${step.status.name}'
                    '${step.reason == null ? '' : ' (${step.reason})'}',
            ].join('\n');
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('compliance_gdpr example')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            title: const Text('Analytics'),
            subtitle: Text(_analyticsRunning ? 'Running' : 'Stopped'),
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.tonal(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => PrivacySettingsScreen(manager: widget.consent),
            ),
          ),
          child: const Text('Privacy settings'),
        ),
        const SizedBox(height: 8),
        FilledButton.tonal(
          onPressed: _export,
          child: const Text('Export my data'),
        ),
        const SizedBox(height: 8),
        FilledButton.tonal(
          onPressed: _delete,
          child: const Text('Delete my account'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => _TextScreen(
                title: 'Audit trail',
                text: [
                  for (final e in widget.audit.history)
                    '${e.timestamp.toIso8601String()} ${e.type} ${e.metadata}',
                ].join('\n'),
              ),
            ),
          ),
          child: const Text('Show audit trail'),
        ),
        if (_status != null) ...[const SizedBox(height: 16), Text(_status!)],
      ],
    ),
  );
}

class _TextScreen extends StatelessWidget {
  const _TextScreen({required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: SelectableText(
        text.isEmpty ? '(empty)' : text,
        style: const TextStyle(fontFamily: 'monospace'),
      ),
    ),
  );
}

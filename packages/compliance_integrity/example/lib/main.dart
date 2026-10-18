import 'dart:convert';
import 'dart:math';

import 'package:compliance_core/compliance_core.dart';
import 'package:compliance_integrity/compliance_integrity.dart';
import 'package:flutter/material.dart';

/// Google Cloud project number, passed at build time:
/// flutter run --dart-define=CLOUD_PROJECT_NUMBER=123456789012
const int _cloudProjectNumber = int.fromEnvironment('CLOUD_PROJECT_NUMBER');

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key, this.integrity});

  /// Injected in tests.
  final Integrity? integrity;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'compliance_integrity example',
    theme: ThemeData(colorSchemeSeed: Colors.teal),
    home: IntegrityScreen(integrity: integrity),
  );
}

class IntegrityScreen extends StatefulWidget {
  const IntegrityScreen({super.key, this.integrity});

  final Integrity? integrity;

  @override
  State<IntegrityScreen> createState() => _IntegrityScreenState();
}

class _IntegrityScreenState extends State<IntegrityScreen> {
  final _audit = InMemoryAuditTrail(maxEvents: 100);
  late final Integrity _integrity =
      widget.integrity ??
      Integrity(
        cloudProjectNumber: _cloudProjectNumber == 0
            ? null
            : _cloudProjectNumber,
        auditTrail: _audit,
      );
  String _status = 'Not checked yet';

  /// DEMO ONLY: a real app must get the request hash from its server, so
  /// the server can check that the token belongs to this exact request.
  String _demoRequestHash() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  Future<void> _check() async {
    setState(() => _status = 'Checking...');
    final supported = await _integrity.isSupported();
    final result = await _integrity.requestToken(_demoRequestHash());
    if (!mounted) return;
    setState(() {
      _status = switch (result) {
        IntegritySuccess(:final kind, :final token) =>
          'Token received (${kind.name}, ${token.length} chars).\n'
              'Send it to your server for verification.',
        IntegrityUnsupported() => 'Not supported on this device.',
        IntegrityPlayServicesMissing() =>
          'Google Play services or Play Store missing or outdated.',
        IntegrityNetworkError() => 'Network problem. Try again later.',
        IntegrityRateLimited() => 'Rate limited. Try again later.',
        IntegrityConfigurationError(:final message) =>
          'Configuration problem: $message',
        IntegrityPlatformError(:final platformCode, :final message) =>
          'Platform error $platformCode: $message',
      };
      _status = 'isSupported: $supported\n$_status';
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('compliance_integrity example')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        FilledButton(
          onPressed: _check,
          child: const Text('Request integrity token'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () async {
            await _integrity.reset();
            if (mounted) setState(() => _status = 'Key and provider reset.');
          },
          child: const Text('Reset'),
        ),
        const SizedBox(height: 16),
        Text(_status, key: const ValueKey('status')),
        const SizedBox(height: 16),
        Text('Audit events', style: Theme.of(context).textTheme.titleMedium),
        StreamBuilder<AuditEvent>(
          stream: _audit.events,
          builder: (context, _) => Text(
            [
              for (final e in _audit.history) '${e.type} ${e.metadata}',
            ].join('\n'),
          ),
        ),
      ],
    ),
  );
}

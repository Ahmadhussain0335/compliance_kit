import 'package:compliance_core/compliance_core.dart';
import 'package:compliance_gdpr/compliance_gdpr.dart';
import 'package:compliance_integrity/compliance_integrity.dart';
import 'package:compliance_logger/compliance_logger.dart';

/// All Compliance Kit modules wired to one shared [AuditTrail].
///
/// ```dart
/// final kit = await ComplianceKit.init(
///   appId: 'com.example.app',
///   consentPolicy: policy,
///   consentStore: myConsentStore,
///   forwardLogs: (record) => crashReporter.log(record.message),
///   forwardLogsPurpose: 'crash_reporting',
///   cloudProjectNumber: 123456789012,
/// );
/// kit.logger.info('Started');
/// if (kit.consent!.state.needsConsent) { /* show the consent prompt */ }
/// ```
///
/// Every module can also be used on its own; this class only saves the
/// wiring.
final class ComplianceKit {
  ComplianceKit._({
    required this.auditTrail,
    required this.logger,
    required this.consent,
    required this.exporter,
    required this.deletion,
    required this.integrity,
  });

  /// Creates and initializes every module.
  ///
  /// * [appId]: identifies the app in data exports.
  /// * [auditTrail]: shared trail; an [InMemoryAuditTrail] holding the last
  ///   10,000 events if omitted. Use a persistent trail if you need the
  ///   events as evidence.
  /// * Logger: [loggerName], [minLogLevel], [redactor], [logSinks]
  ///   (a [ConsoleSink] if omitted).
  /// * [forwardLogs]: forwards redacted records at [forwardMinLevel] or
  ///   above, for example to a crash reporter. If [forwardLogsPurpose] is
  ///   set, records are only forwarded while the user has granted that
  ///   consent purpose.
  /// * GDPR: [consentPolicy] enables the [ConsentManager]; [consentStore]
  ///   persists it. [serverDeletion] and [eraseLocalWhenServerFails]
  ///   configure [DataDeletionManager]. When [exportConsentHistory] is
  ///   `true` (the default), the consent history is registered as the
  ///   `consent_history` export source, because it is the user's personal
  ///   data. When [eraseConsentOnDeletion] is `true`, consent records are
  ///   deleted with the account; whether to keep them as proof of consent
  ///   is a legal decision, so the default is `false`.
  /// * Integrity: [cloudProjectNumber] (Android), [integrityPlatform] for
  ///   tests.
  /// * [onAuditError]: called when an audit event could not be recorded.
  ///
  /// Throws [InvalidConfigurationException] if [forwardLogsPurpose] is set
  /// without a [consentPolicy] containing that purpose.
  static Future<ComplianceKit> init({
    required String appId,
    AuditTrail? auditTrail,
    String loggerName = 'app',
    LogLevel minLogLevel = LogLevel.info,
    Redactor? redactor,
    List<LogSink>? logSinks,
    void Function(LogRecord record)? forwardLogs,
    String? forwardLogsPurpose,
    LogLevel forwardMinLevel = LogLevel.warning,
    ConsentPolicy? consentPolicy,
    ConsentStore? consentStore,
    bool exportConsentHistory = true,
    bool eraseConsentOnDeletion = false,
    ServerDeletionCallback? serverDeletion,
    bool eraseLocalWhenServerFails = false,
    int? cloudProjectNumber,
    IntegrityPlatform? integrityPlatform,
    void Function(Object error)? onAuditError,
  }) async {
    if (forwardLogsPurpose != null &&
        consentPolicy?.purpose(forwardLogsPurpose) == null) {
      throw InvalidConfigurationException(
        'forwardLogsPurpose "$forwardLogsPurpose" must be a purpose of '
        'consentPolicy.',
      );
    }
    final trail = auditTrail ?? InMemoryAuditTrail(maxEvents: 10000);

    ConsentManager? consent;
    if (consentPolicy != null) {
      consent = ConsentManager(
        policy: consentPolicy,
        store: consentStore,
        auditTrail: trail,
        onAuditError: onAuditError,
      );
      await consent.initialize();
    }

    final sinks = <LogSink>[
      ...logSinks ?? const [ConsoleSink()],
    ];
    if (forwardLogs != null) {
      sinks.add(
        CallbackSink((record) {
          if (!record.level.isAtLeast(forwardMinLevel)) return;
          if (forwardLogsPurpose != null &&
              !(consent?.isGranted(forwardLogsPurpose) ?? false)) {
            return;
          }
          forwardLogs(record);
        }),
      );
    }
    final logger = ComplianceLogger(
      name: loggerName,
      minLevel: minLogLevel,
      sinks: sinks,
      redactor: redactor,
      auditTrail: trail,
    );

    final exporter = DataExporter(
      appId: appId,
      auditTrail: trail,
      onAuditError: onAuditError,
    );
    if (consent != null && exportConsentHistory) {
      final manager = consent;
      exporter.register(
        CallbackDataSource('consent_history', () async {
          final history = await manager.history();
          return [for (final record in history) record.toJson()];
        }),
      );
    }

    final deletion = DataDeletionManager(
      serverDeletion: serverDeletion,
      eraseLocalWhenServerFails: eraseLocalWhenServerFails,
      auditTrail: trail,
      onAuditError: onAuditError,
    );
    if (consent != null && eraseConsentOnDeletion) {
      final manager = consent;
      deletion.register(
        CallbackDataEraser('consent_records', () async {
          await manager.reset();
          return ErasureStatus.deleted;
        }),
      );
    }

    final integrity = Integrity(
      cloudProjectNumber: cloudProjectNumber,
      auditTrail: trail,
      platform: integrityPlatform,
    );

    return ComplianceKit._(
      auditTrail: trail,
      logger: logger,
      consent: consent,
      exporter: exporter,
      deletion: deletion,
      integrity: integrity,
    );
  }

  /// The shared audit trail.
  final AuditTrail auditTrail;

  /// The redacting logger.
  final ComplianceLogger logger;

  /// Consent management, or `null` if no consent policy was given.
  final ConsentManager? consent;

  /// Data export. Register your [DataSource]s here.
  final DataExporter exporter;

  /// Account deletion. Register your [DataEraser]s here.
  final DataDeletionManager deletion;

  /// Integrity checks.
  final Integrity integrity;

  /// Closes the logger's sinks and the consent manager.
  Future<void> dispose() async {
    await logger.close();
    await consent?.dispose();
  }
}

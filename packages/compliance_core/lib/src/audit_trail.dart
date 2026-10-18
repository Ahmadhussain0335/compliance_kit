import 'dart:async';
import 'dart:collection';

import 'audit_event.dart';
import 'exceptions.dart';

/// Receives and publishes [AuditEvent]s.
///
/// Compliance Kit packages record events through this interface. Apps decide
/// where events end up by choosing an implementation: [InMemoryAuditTrail]
/// for tests and short-lived sessions, or a custom implementation that writes
/// to a database, file or backend.
///
/// Implementations must not throw from [record] for valid events in normal
/// operation; a failing audit trail should not break the feature that
/// recorded the event.
abstract interface class AuditTrail {
  /// Records [event] and publishes it on [events].
  Future<void> record(AuditEvent event);

  /// A broadcast stream of events recorded after the listener subscribed.
  Stream<AuditEvent> get events;
}

/// An [AuditTrail] that discards every event.
///
/// Useful as a default when an app does not need an audit trail.
final class NoopAuditTrail implements AuditTrail {
  /// Creates a [NoopAuditTrail].
  const NoopAuditTrail();

  @override
  Future<void> record(AuditEvent event) async {}

  @override
  Stream<AuditEvent> get events => const Stream.empty();
}

/// An [AuditTrail] that keeps events in memory.
///
/// Events are lost when the process ends. Use it in tests, examples, or as a
/// buffer that the app periodically persists itself.
///
/// If [maxEvents] is set, the oldest events are dropped once the limit is
/// reached, so memory use stays bounded in long-running apps.
final class InMemoryAuditTrail implements AuditTrail {
  /// Creates an in-memory audit trail.
  ///
  /// Throws [InvalidConfigurationException] if [maxEvents] is not positive.
  InMemoryAuditTrail({this.maxEvents}) {
    final max = maxEvents;
    if (max != null && max <= 0) {
      throw const InvalidConfigurationException(
        'maxEvents must be greater than zero.',
      );
    }
  }

  /// The maximum number of events kept in [history], or `null` for no limit.
  final int? maxEvents;

  final ListQueue<AuditEvent> _history = ListQueue<AuditEvent>();
  final StreamController<AuditEvent> _controller =
      StreamController<AuditEvent>.broadcast();
  bool _disposed = false;

  /// The recorded events, oldest first. Unmodifiable snapshot.
  List<AuditEvent> get history => List.unmodifiable(_history);

  /// Whether [dispose] has been called.
  bool get isDisposed => _disposed;

  @override
  Stream<AuditEvent> get events => _controller.stream;

  /// Records [event].
  ///
  /// Throws [ComplianceStateException] if the trail has been disposed.
  @override
  Future<void> record(AuditEvent event) async {
    if (_disposed) {
      throw const ComplianceStateException(
        'Cannot record an event after the audit trail was disposed.',
      );
    }
    _history.addLast(event);
    final max = maxEvents;
    if (max != null) {
      while (_history.length > max) {
        _history.removeFirst();
      }
    }
    _controller.add(event);
  }

  /// Removes all events from [history]. Does not affect [events] listeners.
  void clear() => _history.clear();

  /// Closes the [events] stream. Further calls to [record] throw.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _controller.close();
  }
}

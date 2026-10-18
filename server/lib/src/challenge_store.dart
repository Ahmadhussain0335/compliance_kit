import 'dart:convert';
import 'dart:math';

/// Issues single-use challenges with a short lifetime.
///
/// In-memory reference implementation. Use a shared store (database, Redis)
/// when running more than one server instance.
final class ChallengeStore {
  /// Creates a store.
  ChallengeStore({
    this.lifetime = const Duration(minutes: 5),
    this.maxOutstanding = 10000,
    DateTime Function()? clock,
    Random? random,
  }) : _clock = clock ?? DateTime.now,
       _random = random ?? Random.secure();

  /// How long a challenge stays valid.
  final Duration lifetime;

  /// Maximum number of unconsumed challenges. [issue] returns `null` when
  /// the store is full; the server answers 503.
  final int maxOutstanding;

  final DateTime Function() _clock;
  final Random _random;
  final Map<String, DateTime> _issued = {};

  /// Returns a new base64url challenge with 256 bits of randomness, or
  /// `null` if [maxOutstanding] challenges are pending.
  String? issue() {
    _purge();
    if (_issued.length >= maxOutstanding) return null;
    final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
    final challenge = base64Url.encode(bytes).replaceAll('=', '');
    _issued[challenge] = _clock().add(lifetime);
    return challenge;
  }

  /// Consumes [challenge]. Returns `true` only once, and only before it
  /// expires.
  bool consume(String challenge) {
    final expiry = _issued.remove(challenge);
    return expiry != null && _clock().isBefore(expiry);
  }

  /// Number of outstanding challenges.
  int get length => _issued.length;

  /// Lifetimes are fixed, so insertion order is expiry order and only the
  /// oldest entries need checking.
  void _purge() {
    final now = _clock();
    while (_issued.isNotEmpty && !now.isBefore(_issued.values.first)) {
      _issued.remove(_issued.keys.first);
    }
  }
}

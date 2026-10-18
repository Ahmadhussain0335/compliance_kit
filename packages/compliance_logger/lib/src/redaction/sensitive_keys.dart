/// Decides which map keys and `key=value` names hold secrets.
///
/// Keys are normalised before matching: lowercased, with every character
/// that is not a letter or digit removed. So `API_KEY`, `api-key` and
/// `apiKey` all normalise to `apikey`.
///
/// A key is sensitive if its normalised form contains any of [containing],
/// or equals any of [exact]. Short, ambiguous terms such as `pin` belong in
/// [exact] so that `shipping` is not treated as sensitive.
///
/// Matching errs on the side of redaction: `max_tokens` contains `token` and
/// is treated as sensitive.
final class SensitiveKeys {
  /// Creates a key matcher. Terms are normalised the same way as keys.
  SensitiveKeys({
    Iterable<String> containing = const [],
    Iterable<String> exact = const [],
  }) : containing = Set.unmodifiable(containing.map(normalize)),
       exact = Set.unmodifiable(exact.map(normalize));

  /// The default terms.
  static final SensitiveKeys defaults = SensitiveKeys(
    containing: const [
      'password',
      'passwd',
      'passphrase',
      'secret',
      'token',
      'apikey',
      'privatekey',
      'accesskey',
      'authorization',
      'credential',
      'cookie',
      'sessionid',
      'signature',
    ],
    exact: const [
      'pwd',
      'pin',
      'otp',
      'auth',
      'session',
      'sid',
      'cvv',
      'cvc',
      'ssn',
    ],
  );

  /// Normalised terms that match anywhere in a key.
  final Set<String> containing;

  /// Normalised terms that must equal the whole key.
  final Set<String> exact;

  /// Returns a copy with additional terms.
  SensitiveKeys withAdditional({
    Iterable<String> containing = const [],
    Iterable<String> exact = const [],
  }) => SensitiveKeys(
    containing: [...this.containing, ...containing],
    exact: [...this.exact, ...exact],
  );

  /// Whether [key] names a sensitive value.
  bool matches(String key) {
    final normalized = normalize(key);
    if (normalized.isEmpty) return false;
    if (exact.contains(normalized)) return true;
    for (final term in containing) {
      if (normalized.contains(term)) return true;
    }
    return false;
  }

  static final RegExp _nonAlphanumeric = RegExp('[^a-z0-9]');

  /// Lowercases [key] and removes everything except letters and digits.
  static String normalize(String key) =>
      key.toLowerCase().replaceAll(_nonAlphanumeric, '');
}

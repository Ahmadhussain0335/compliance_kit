import 'package:flutter/services.dart';

import 'integrity_platform.dart';
import 'integrity_result.dart';
import 'messages.g.dart';

/// [IntegrityPlatform] backed by the Pigeon-generated platform channel.
final class PigeonIntegrityPlatform implements IntegrityPlatform {
  /// Creates the platform. [api] is replaceable for tests.
  PigeonIntegrityPlatform({IntegrityHostApi? api})
    : _api = api ?? IntegrityHostApi();

  final IntegrityHostApi _api;

  @override
  Future<bool> isSupported() => _guard(_api.isSupported);

  @override
  Future<void> prepare({int? cloudProjectNumber}) =>
      _guard(() => _api.prepare(cloudProjectNumber));

  @override
  Future<PlatformToken> requestToken({
    required String requestHash,
    int? cloudProjectNumber,
  }) => _guard(() async {
    final message = await _api.requestToken(requestHash, cloudProjectNumber);
    return PlatformToken(
      token: message.token,
      kind: switch (message.kind) {
        TokenKindMessage.playIntegrityStandard =>
          IntegrityTokenKind.playIntegrityStandard,
        TokenKindMessage.appAttestAttestation =>
          IntegrityTokenKind.appAttestAttestation,
        TokenKindMessage.appAttestAssertion =>
          IntegrityTokenKind.appAttestAssertion,
      },
      keyId: message.keyId,
    );
  });

  @override
  Future<void> reset() => _guard(_api.reset);

  /// Converts channel errors into [IntegrityPlatformException].
  static Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on PlatformException catch (e) {
      throw IntegrityPlatformException(
        e.code,
        message: e.message,
        platformCode: e.details?.toString(),
      );
    } on MissingPluginException catch (e) {
      // No native implementation, for example on web or desktop.
      throw IntegrityPlatformException(
        IntegrityErrorCodes.unsupported,
        message: e.message,
      );
    }
  }
}

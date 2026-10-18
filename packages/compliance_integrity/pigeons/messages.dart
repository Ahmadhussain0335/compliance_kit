// Pigeon definition for the compliance_integrity platform channel.
// Regenerate with: dart run pigeon --input pigeons/messages.dart
import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/messages.g.dart',
    dartOptions: DartOptions(),
    kotlinOut:
        'android/src/main/kotlin/io/github/ahmadhussain0335/compliance_integrity/Messages.g.kt',
    kotlinOptions: KotlinOptions(
      package: 'io.github.ahmadhussain0335.compliance_integrity',
    ),
    swiftOut:
        'ios/compliance_integrity/Sources/compliance_integrity/Messages.g.swift',
    swiftOptions: SwiftOptions(),
    dartPackageName: 'compliance_integrity',
  ),
)
/// Kind of token returned by the host.
enum TokenKindMessage {
  playIntegrityStandard,
  appAttestAttestation,
  appAttestAssertion,
}

/// Token returned by the host.
class TokenMessage {
  TokenMessage({required this.token, required this.kind, this.keyId});

  String token;
  TokenKindMessage kind;
  String? keyId;
}

/// Host API implemented in Kotlin and Swift. Failures are reported as
/// FlutterError with one of the IntegrityErrorCodes as code and the native
/// error code in details.
@HostApi()
abstract class IntegrityHostApi {
  @async
  bool isSupported();

  @async
  void prepare(int? cloudProjectNumber);

  @async
  TokenMessage requestToken(String requestHash, int? cloudProjectNumber);

  @async
  void reset();
}

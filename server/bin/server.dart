// Reference server for compliance_integrity. NOT PRODUCTION-READY.
//
// Configuration (environment variables):
//   PORT                          default 8080
//   ANDROID_PACKAGE_NAME          enables Play Integrity verification
//   ANDROID_CERT_SHA256           optional, comma-separated base64url digests
//   GOOGLE_APPLICATION_CREDENTIALS path to the service account key (never commit it)
//   IOS_TEAM_ID, IOS_BUNDLE_ID    enable App Attest verification
//   IOS_APP_ATTEST_ENV            development | production (default production)
//
// Run behind TLS (a reverse proxy or load balancer); never expose it over
// plain HTTP.
import 'dart:io';

import 'package:compliance_integrity_server/compliance_integrity_server.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;

Future<void> main() async {
  final env = Platform.environment;
  final packageName = env['ANDROID_PACKAGE_NAME'];
  final teamId = env['IOS_TEAM_ID'];
  final bundleId = env['IOS_BUNDLE_ID'];

  final server = IntegrityServer(
    playDecoder: packageName == null
        ? null
        : await GooglePlayIntegrityDecoder.create(packageName),
    playPolicy: packageName == null
        ? null
        : PlayIntegrityPolicy(
            packageName: packageName,
            certificateSha256Digests: {
              ...?env['ANDROID_CERT_SHA256']
                  ?.split(',')
                  .map((d) => d.trim())
                  .where((d) => d.isNotEmpty),
            },
          ),
    appAttest: teamId == null || bundleId == null
        ? null
        : AppAttestVerifier(
            teamId: teamId,
            bundleId: bundleId,
            environment: env['IOS_APP_ATTEST_ENV'] == 'development'
                ? AppAttestEnvironment.development
                : AppAttestEnvironment.production,
          ),
  );

  final port = int.tryParse(env['PORT'] ?? '') ?? 8080;
  // Request logging is left out on purpose: request bodies carry tokens.
  final handler = const Pipeline().addHandler(server.handler);
  final http = await io.serve(handler, InternetAddress.loopbackIPv4, port);
  stdout.writeln(
    'compliance_integrity reference server on http://${http.address.host}:${http.port} '
    '(android: ${packageName != null}, ios: ${teamId != null && bundleId != null})',
  );
}

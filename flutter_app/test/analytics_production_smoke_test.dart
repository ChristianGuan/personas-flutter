// Explicit opt-in. Synthetic events only; always delete the test installation.
// Host HTTP check, not a replacement for testing the Android binary.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:personas_flutter/analytics/event.dart';
import 'package:personas_flutter/analytics/transport.dart';

void main() {
  const enabled = bool.fromEnvironment('PERSONAS_PRODUCTION_SMOKE');
  const url = String.fromEnvironment('ANALYTICS_API_URL');
  test(
    'production synthetic registration, deduplication and revocation',
    () async {
      expect(url, 'https://halladin.cloud');
      final client = HttpAnalyticsTransport(url);
      final id = randomUuid(), token = randomToken(), eventId = randomUuid();
      final events = <Map<String, Object?>>[
        {
          'eventId': eventId,
          'installationId': id,
          'type': 'session_started',
          'schemaVersion': 1,
          'createdAt': DateTime.now().toUtc().toIso8601String(),
          'payload': <String, Object?>{},
        },
      ];
      // Keep the random credentials in a private local recovery file until cleanup.
      final recovery = File('.env.production-smoke-recovery');
      if (await recovery.exists()) {
        throw StateError(
          'Complete the previous synthetic installation cleanup first',
        );
      }
      await recovery.create();
      final permissions = await Process.run('chmod', ['600', recovery.path]);
      if (permissions.exitCode != 0) {
        throw StateError('Private recovery file permissions unavailable');
      }
      await recovery.writeAsString('$id\n$token\n');
      try {
        await client.register(id, token);
        expect(await client.send(id, token, events), {eventId});
        expect(await client.send(id, token, events), {eventId});
        await client.delete(id, token);
        await expectLater(
          client.send(id, token, events),
          throwsA(isA<HttpException>()),
        );
      } finally {
        try {
          for (var attempt = 0; ; attempt++) {
            try {
              await client.delete(id, token);
              break;
            } catch (_) {
              if (attempt == 2) rethrow;
              await Future<void>.delayed(const Duration(seconds: 1));
            }
          }
          await recovery.delete();
        } finally {
          client.cancel();
        }
      }
    },
    skip: !enabled,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

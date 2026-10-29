import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:personas_flutter/analytics/event.dart';
import 'package:personas_flutter/analytics/store.dart';
import 'package:personas_flutter/analytics/sync.dart';
import 'package:personas_flutter/analytics/transport.dart';

class _Vault implements TokenVault {
  final String token = randomToken();
  @override
  Future<String?> read() async => token;
  @override
  Future<void> write(String value) async {}
  @override
  Future<void> clear() async {}
}

void main() {
  sqfliteFfiInit();
  late HttpServer server;
  late HttpAnalyticsTransport transport;
  late AnalyticsStore store;
  late Directory directory;
  late _Vault vault;
  late String installation;
  late List<Map<String, Object?>> requests;
  late Object reply;
  late int status;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    transport = HttpAnalyticsTransport('http://127.0.0.1:${server.port}/');
    directory = await Directory.systemTemp.createTemp('analytics-http-');
    store = await AnalyticsStore.open(
      factory: databaseFactoryFfi,
      path: '${directory.path}/queue.db',
    );
    vault = _Vault();
    installation = randomUuid();
    requests = [];
    reply = {
      'acceptedEventIds': <String>[],
      'rejectedIndices': [0],
    };
    status = HttpStatus.ok;
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      requests.add({
        'method': request.method,
        'path': request.uri.path,
        'authorization': request.headers.value('authorization'),
        'contentType': request.headers.contentType?.mimeType,
        'body': body.isEmpty ? null : jsonDecode(body),
      });
      request.response.statusCode = status;
      request.response.headers.contentType = ContentType.json;
      final Object response = request.method == 'DELETE'
          ? {'deleted': true}
          : request.uri.path.endsWith('/installations')
          ? {'registered': true}
          : reply;
      request.response.write(jsonEncode(response));
      await request.response.close();
    });
  });

  tearDown(() async {
    transport.cancel();
    await server.close(force: true);
    await store.close();
    await directory.delete(recursive: true);
  });

  test('production origin resolves each route once and rejects prefixes', () {
    for (final base in ['https://halladin.cloud', 'https://halladin.cloud/']) {
      final client = HttpAnalyticsTransport(base);
      expect(
        client.base.resolve('/v1/analytics/events/batch').toString(),
        'https://halladin.cloud/v1/analytics/events/batch',
      );
    }
    for (final base in [
      'https://halladin.cloud/v1',
      'https://halladin.cloud/docs-json',
      'http://halladin.cloud',
      'https://halladin.cloud?token=secret',
    ]) {
      expect(() => HttpAnalyticsTransport(base), throwsArgumentError);
    }
    expect(
      randomUuid(),
      matches(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      ),
    );
    expect(vault.token, matches(r'^[0-9a-f]{64}$'));
  });

  test(
    'HTTP registration, partial ACK retry and revocation use installation auth',
    () async {
      final sync = AnalyticsSync(store, vault, transport);
      await sync.flush();
      expect(requests, isEmpty);
      await store.enable(installation);
      await store.add('session_started', {});
      await store.add('search_started', {});
      final rows = await store.due();
      final first = rows.first['event_id'];
      final second = rows.last['event_id'];
      reply = {
        'acceptedEventIds': [first],
        'rejectedIndices': [1],
      };
      await sync.flush();
      expect(requests.map((r) => r['path']), [
        '/v1/analytics/installations',
        '/v1/analytics/events/batch',
      ]);
      expect(requests.first['body'], {'installationId': installation});
      final pending = await store.db.query('analytics_outbox');
      expect(pending, hasLength(1));
      expect(pending.single['event_id'], second);
      expect(pending.single['attempts'], 1);
      // Retry immediately in this test; production keeps its exponential backoff.
      await store.db.update('analytics_outbox', {'next_attempt': 0});
      reply = {
        'acceptedEventIds': [second],
        'rejectedIndices': <int>[],
      };
      await sync.flush();
      final sent = requests.last['body'] as Map;
      expect(sent['installationId'], installation);
      expect((sent['events'] as List).single['eventId'], second);
      expect(await store.db.query('analytics_outbox'), isEmpty);
      await store.revoke();
      await sync.flush();
      expect(requests.last['method'], 'DELETE');
      expect(
        requests.last['path'],
        '/v1/analytics/installations/$installation',
      );
      expect((await store.state()).installationId, isNull);
      for (final request in requests) {
        expect(request['authorization'], 'Bearer ${vault.token}');
        expect(request['contentType'], 'application/json');
      }
    },
  );

  test('API errors and malformed ACKs preserve events for retry', () async {
    await store.enable(installation);
    await store.add('session_started', {});
    final event = (await store.due()).single['event_id'];
    for (final code in [401, 429, 500, 200]) {
      status = code;
      reply = {'acceptedEventIds': 'invalid'};
      await store.db.update('analytics_outbox', {'next_attempt': 0});
      await AnalyticsSync(store, vault, transport).flush();
      final pending = await store.db.query('analytics_outbox');
      expect(pending.single['event_id'], event);
      expect(pending.single['attempts'], greaterThan(0));
    }
  });
}

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:personas_flutter/analytics/event.dart';
import 'package:personas_flutter/analytics/store.dart';
import 'package:personas_flutter/analytics/sync.dart';
import 'package:personas_flutter/analytics/transport.dart';

class Vault implements TokenVault {
  String? token = 'a' * 64;
  @override
  Future<String?> read() async => token;
  @override
  Future<void> write(String value) async {
    token = value;
  }

  @override
  Future<void> clear() async {
    token = null;
  }
}

class Transport implements AnalyticsTransport {
  bool offline = false, deleted = false;
  int calls = 0;
  bool partial = false;
  @override
  Future<void> register(String id, String token) async {
    if (offline) throw const SocketException('offline');
  }

  @override
  Future<Set<String>> send(
    String id,
    String token,
    List<Map<String, Object?>> events,
  ) async {
    calls++;
    return events
        .take(partial ? 1 : events.length)
        .map((e) => e['eventId'] as String)
        .toSet();
  }

  @override
  Future<void> delete(String id, String token) async {
    if (offline) throw const SocketException('offline');
    deleted = true;
  }

  @override
  void cancel() {}
}

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late AnalyticsStore store;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('analytics-test-');
    store = await AnalyticsStore.open(
      factory: databaseFactoryFfi,
      path: '${directory.path}/outbox.db',
    );
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });
  test(
    'no consent, durable offline queue and authenticated revocation',
    () async {
      expect((await store.state()).installationId, isNull);
      expect(await store.add('search_started', {}), false);
      final id = randomUuid();
      await store.enable(id);
      await store.add('search_started', {});
      final t = Transport()..offline = true;
      final sync = AnalyticsSync(store, Vault(), t);
      await sync.flush();
      expect(
        (await store.due(
          now: DateTime.now()
              .add(const Duration(days: 1))
              .millisecondsSinceEpoch,
        )).length,
        1,
      );
      await store.close();
      store = await AnalyticsStore.open(
        factory: databaseFactoryFfi,
        path: '${directory.path}/outbox.db',
      );
      expect((await store.state()).installationId, id);
      expect((await store.db.query('analytics_outbox')).length, 1);
      await store.revoke();
      expect((await store.db.query('analytics_outbox')), isEmpty);
      expect(await store.add('session_started', {}), false);
      expect((await store.state()).deletionPending, true);
      final newSync = AnalyticsSync(store, Vault(), t);
      await newSync.flush();
      expect((await store.state()).deletionPending, true);
      t.offline = false;
      await store.retryDeletion();
      await newSync.flush();
      expect(t.deleted, true);
      expect((await store.state()).installationId, isNull);
    },
  );
  test('v2 migration preserves consent identity and pending events', () async {
    final id = randomUuid();
    await store.enable(id);
    await store.add('session_started', {});
    await store.db.execute(
      'ALTER TABLE analytics_state DROP COLUMN reenable_requested',
    );
    await store.db.setVersion(2);
    await store.close();
    store = await AnalyticsStore.open(
      factory: databaseFactoryFfi,
      path: '${directory.path}/outbox.db',
    );
    final state = await store.state();
    expect(state.enabled, true);
    expect(state.installationId, id);
    expect(state.consentVersion, 2);
    expect(state.reenableRequested, false);
    expect(await store.db.query('analytics_outbox'), hasLength(1));
  });
  test('partial acknowledgements preserve other rows and back off', () async {
    await store.enable(randomUuid());
    await store.add('session_started', {});
    await store.add('search_started', {});
    final t = Transport()..partial = true;
    await AnalyticsSync(store, Vault(), t).flush();
    final rows = await store.db.query('analytics_outbox');
    expect(rows.length, 1);
    expect(rows.single['attempts'], 1);
    expect(await store.due(), isEmpty);
    await store.db.update('analytics_outbox', {'next_attempt': 0});
    t.partial = false;
    await AnalyticsSync(store, Vault(), t).flush();
    expect(await store.db.query('analytics_outbox'), isEmpty);
  });
  test('outbox rejects arbitrary fields and removes expired rows', () async {
    await store.enable(randomUuid());
    expect(
      () => store.add('search_completed', {
        'durationMs': 1,
        'photoRange': '1-25',
        'matchRange': '0',
        'photoId': 'secret',
      }),
      throwsArgumentError,
    );
    await store.add('session_started', {});
    await store.db.update('analytics_outbox', {
      'created_at': DateTime.now()
          .subtract(const Duration(days: 31))
          .millisecondsSinceEpoch,
    });
    await store.prune();
    expect(await store.db.query('analytics_outbox'), isEmpty);
    expect(validPayload('results_rated', {'stars': 0}), false);
    expect(
      validPayload('results_reviewed', {'confirmed': 0, 'rejected': 0}),
      false,
    );
    for (var i = 0; i < 10; i++) {
      expect(AnalyticsSync.delayMs(i), inInclusiveRange(3750, 21600000));
    }
  });
  test('ack for foreign IDs never removes an unacknowledged event', () async {
    await store.enable(randomUuid());
    await store.add('search_started', {});
    await store.acknowledge(await store.due(), {
      randomUuid(),
    }, AnalyticsSync.delayMs);
    expect((await store.db.query('analytics_outbox')).length, 1);
  });
  test('queue capacity is bounded and newest events survive', () async {
    final id = randomUuid();
    await store.enable(id);
    await store.db.transaction((tx) async {
      final batch = tx.batch();
      for (var i = 0; i < AnalyticsStore.maxEvents + 2; i++) {
        batch.insert('analytics_outbox', {
          'event_id': randomUuid(),
          'installation_id': id,
          'type': 'search_started',
          'schema_version': 1,
          'created_at': DateTime.now().millisecondsSinceEpoch,
          'payload': '{}',
        });
      }
      await batch.commit(noResult: true);
    });
    await store.prune();
    expect(
      (await store.db.rawQuery(
        'SELECT count(*) n FROM analytics_outbox',
      )).single['n'],
      AnalyticsStore.maxEvents,
    );
  });
}

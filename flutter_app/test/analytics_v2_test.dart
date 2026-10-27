import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:personas_flutter/analytics/event.dart';
import 'package:personas_flutter/analytics/store.dart';

void main() {
  sqfliteFfiInit();
  test(
    'v1 upgrade preserves pending rows, requires renewed consent and persists v2 deduplication',
    () async {
      final temp = await Directory.systemTemp.createTemp('analytics-v2-');
      final path = '${temp.path}/queue.db',
          id = randomUuid(),
          sessionId = randomUuid(),
          searchId = randomUuid();
      AnalyticsStore? store;
      try {
        final old = await databaseFactoryFfi.openDatabase(
          path,
          options: OpenDatabaseOptions(
            version: 1,
            onCreate: (db, _) async {
              await db.execute(
                'CREATE TABLE analytics_state(id INTEGER PRIMARY KEY,enabled INTEGER,installation_id TEXT,deletion_pending INTEGER DEFAULT 0,deletion_attempts INTEGER DEFAULT 0,deletion_next_attempt INTEGER DEFAULT 0)',
              );
              await db.execute(
                "CREATE TABLE analytics_outbox(event_id TEXT PRIMARY KEY,installation_id TEXT,type TEXT,schema_version INTEGER CHECK(schema_version=1),created_at INTEGER,payload TEXT,state TEXT DEFAULT 'pending',attempts INTEGER DEFAULT 0,next_attempt INTEGER DEFAULT 0)",
              );
              await db.execute(
                'CREATE INDEX analytics_due ON analytics_outbox(next_attempt,created_at)',
              );
            },
          ),
        );
        await old.insert('analytics_state', {
          'id': 1,
          'enabled': 1,
          'installation_id': id,
        });
        await old.insert('analytics_outbox', {
          'event_id': randomUuid(),
          'installation_id': id,
          'type': 'session_started',
          'schema_version': 1,
          'created_at': DateTime.now().millisecondsSinceEpoch,
          'payload': '{}',
        });
        await old.close();
        store = await AnalyticsStore.open(
          factory: databaseFactoryFfi,
          path: path,
        );
        expect((await store.state()).consentVersion, 1);
        expect((await store.state()).installationId, id);
        expect((await store.due()).single['schema_version'], 1);
        Future<bool> add(String type, Payload p) => store!.add(
          type,
          p,
          schemaVersion: 2,
          platform: 'ios',
          appVersion: '0.9.0+13',
        );
        final start = <String, Object>{
          'sessionId': sessionId,
          'searchId': searchId,
          'photosPlanned': 20,
        };
        expect(await add('search_started', start), false);
        await store.enable(id);
        expect(await add('search_started', start), true);
        final done = <String, Object>{
          ...start,
          'photosProcessed': 20,
          'unreadableCount': 2,
          'matchesShown': 5,
          'timingSource': 'live',
          'durationMs': 1200,
          'setupMs': 200,
          'processingMs': 1000,
        };
        expect(await add('search_completed', done), true);
        expect(await add('search_cancelled', done), false);
        expect(
          await add('results_rated', {
            'sessionId': sessionId,
            'searchId': searchId,
            'stars': 5,
          }),
          true,
        );
        await store.close();
        store = await AnalyticsStore.open(
          factory: databaseFactoryFfi,
          path: path,
        );
        expect(
          await add('results_rated', {
            'sessionId': sessionId,
            'searchId': searchId,
            'stars': 1,
          }),
          false,
        );
        final rows = await store.due();
        final event = AnalyticsStore.event(
          rows.firstWhere((r) => r['schema_version'] == 2),
        );
        expect(event['platform'], 'ios');
        expect(event['appVersion'], '0.9.0+13');
        expect(event['deliveryAttempts'], 0);
        final pending = randomUuid();
        await add('search_started', {
          'sessionId': sessionId,
          'searchId': pending,
          'photosPlanned': 3,
        });
        await store.recoverInterrupted(pending);
        expect(
          (await store.db.query(
            'analytics_outbox',
            where: 'type=?',
            whereArgs: ['search_interrupted'],
          )),
          isEmpty,
        );
        await store.recoverInterrupted(null);
        await store.recoverInterrupted(null);
        expect(
          (await store.db.query(
            'analytics_outbox',
            where: 'type=?',
            whereArgs: ['search_interrupted'],
          )).length,
          1,
        );
        await store.revoke();
        for (final table in [
          'analytics_outbox',
          'analytics_runs',
          'analytics_marks',
        ]) {
          expect(await store.db.query(table), isEmpty);
        }
      } finally {
        await store?.close();
        await temp.delete(recursive: true);
      }
    },
  );
  test('v2 restored timing stays unknown and forbidden data is rejected', () {
    final p = <String, Object>{
      'sessionId': randomUuid(),
      'searchId': randomUuid(),
      'photosPlanned': 2,
      'photosProcessed': 2,
      'unreadableCount': 0,
      'matchesShown': 1,
      'timingSource': 'unavailable',
    };
    expect(validPayload('search_completed', p, schemaVersion: 2), true);
    expect(
      validPayload('search_completed', {
        ...p,
        'durationMs': 0,
      }, schemaVersion: 2),
      false,
    );
    expect(
      validPayload('search_completed', {
        ...p,
        'photoUri': 'private',
      }, schemaVersion: 2),
      false,
    );
  });
}

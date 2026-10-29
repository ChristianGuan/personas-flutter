import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'event.dart';

class AnalyticsState {
  final bool enabled, deletionPending, reenableRequested;
  final String? installationId;
  final int deletionAttempts, deletionNextAttempt, consentVersion;
  const AnalyticsState(
    this.enabled,
    this.installationId,
    this.deletionPending,
    this.deletionAttempts,
    this.deletionNextAttempt,
    this.consentVersion,
    this.reenableRequested,
  );
}

class AnalyticsStore {
  final Database db;
  static const maxEvents = 5000;
  static const retention = Duration(days: 30);
  AnalyticsStore(this.db);
  static Future<AnalyticsStore> open({
    DatabaseFactory? factory,
    String? path,
  }) async {
    final f = factory ?? databaseFactory;
    final root =
        path ??
        (Platform.isIOS
            ? (await const MethodChannel(
                'co.local.personas/analytics-storage',
              ).invokeMethod<String>('path'))!
            : '${await f.getDatabasesPath()}/personas_analytics.db');
    final db = await f.openDatabase(
      root,
      options: OpenDatabaseOptions(
        version: 3,
        onUpgrade: (db, old, version) async {
          if (old < 2) await _upgradeV2(db);
          if (old < 3) await _upgradeV3(db);
        },
        singleInstance: false,
        onConfigure: (db) async {
          await db.rawQuery('PRAGMA busy_timeout=5000');
          await db.rawQuery('PRAGMA journal_mode=WAL');
        },
        onCreate: (db, version) async {
          // Migration v1; sqflite wraps onCreate/onUpgrade in a transaction.
          await db.execute(
            'CREATE TABLE analytics_state (id INTEGER PRIMARY KEY CHECK(id=1), enabled INTEGER NOT NULL DEFAULT 0, installation_id TEXT, deletion_pending INTEGER NOT NULL DEFAULT 0, deletion_attempts INTEGER NOT NULL DEFAULT 0, deletion_next_attempt INTEGER NOT NULL DEFAULT 0)',
          );
          await db.execute('INSERT INTO analytics_state(id) VALUES(1)');
          await db.execute(
            'CREATE TABLE analytics_outbox (event_id TEXT PRIMARY KEY, installation_id TEXT NOT NULL, type TEXT NOT NULL, schema_version INTEGER NOT NULL CHECK(schema_version=1), created_at INTEGER NOT NULL, payload TEXT NOT NULL, state TEXT NOT NULL DEFAULT \'pending\' CHECK(state=\'pending\'), attempts INTEGER NOT NULL DEFAULT 0, next_attempt INTEGER NOT NULL DEFAULT 0)',
          );
          await db.execute(
            'CREATE INDEX analytics_due ON analytics_outbox(next_attempt,created_at)',
          );
          await _upgradeV2(db);
          await _upgradeV3(db);
        },
      ),
    );
    final store = AnalyticsStore(db);
    await store.prune();
    return store;
  }

  static Future<void> _upgradeV2(DatabaseExecutor db) async {
    await db.execute(
      'ALTER TABLE analytics_state ADD COLUMN consent_version INTEGER NOT NULL DEFAULT 1',
    );
    await db.execute(
      'ALTER TABLE analytics_outbox RENAME TO analytics_outbox_v1',
    );
    await db.execute(
      "CREATE TABLE analytics_outbox (event_id TEXT PRIMARY KEY, installation_id TEXT NOT NULL, type TEXT NOT NULL, schema_version INTEGER NOT NULL CHECK(schema_version IN(1,2)), created_at INTEGER NOT NULL, payload TEXT NOT NULL, state TEXT NOT NULL DEFAULT 'pending' CHECK(state='pending'), attempts INTEGER NOT NULL DEFAULT 0, next_attempt INTEGER NOT NULL DEFAULT 0, platform TEXT, app_version TEXT)",
    );
    await db.execute(
      'INSERT INTO analytics_outbox(event_id,installation_id,type,schema_version,created_at,payload,state,attempts,next_attempt) SELECT event_id,installation_id,type,schema_version,created_at,payload,state,attempts,next_attempt FROM analytics_outbox_v1',
    );
    await db.execute('DROP TABLE analytics_outbox_v1');
    await db.execute(
      'CREATE INDEX analytics_due ON analytics_outbox(next_attempt,created_at)',
    );
    await db.execute(
      'CREATE TABLE analytics_runs (search_id TEXT PRIMARY KEY, created_at INTEGER NOT NULL, payload TEXT NOT NULL, platform TEXT NOT NULL, app_version TEXT NOT NULL, terminal INTEGER NOT NULL DEFAULT 0)',
    );
    await db.execute(
      'CREATE TABLE analytics_marks (entity_id TEXT NOT NULL, kind TEXT NOT NULL, created_at INTEGER NOT NULL, PRIMARY KEY(entity_id,kind))',
    );
  }

  static Future<void> _upgradeV3(DatabaseExecutor db) => db.execute(
    'ALTER TABLE analytics_state ADD COLUMN reenable_requested INTEGER NOT NULL DEFAULT 0',
  );

  Future<void> requestReenable() => db
      .update('analytics_state', {'reenable_requested': 1}, where: 'id=1')
      .then((_) {});

  Future<AnalyticsState> state([DatabaseExecutor? tx]) async {
    final row = (await (tx ?? db).query(
      'analytics_state',
      where: 'id=1',
    )).single;
    return AnalyticsState(
      row['enabled'] == 1,
      row['installation_id'] as String?,
      row['deletion_pending'] == 1,
      row['deletion_attempts'] as int,
      row['deletion_next_attempt'] as int,
      row['consent_version'] as int,
      row['reenable_requested'] == 1,
    );
  }

  Future<void> enable(String id) => db.transaction((tx) async {
    final current = await state(tx);
    if (current.deletionPending) throw StateError('Deletion pending');
    await tx.update('analytics_state', {
      'enabled': 1,
      'consent_version': 2,
      'reenable_requested': 0,
      'installation_id': id,
    }, where: 'id=1');
  });
  Future<void> revoke() => db.transaction((tx) async {
    final current = await state(tx);
    await tx.update('analytics_state', {
      'enabled': 0,
      'reenable_requested': 0,
      'deletion_pending': current.installationId == null ? 0 : 1,
    }, where: 'id=1');
    await tx.delete('analytics_outbox');
    await tx.delete('analytics_runs');
    await tx.delete('analytics_marks');
  });
  Future<void> deleted(String id) => db.transaction((tx) async {
    await tx.update(
      'analytics_state',
      {
        'installation_id': null,
        'deletion_pending': 0,
        'deletion_attempts': 0,
        'deletion_next_attempt': 0,
      },
      where: 'id=1 AND enabled=0 AND installation_id=?',
      whereArgs: [id],
    );
  });
  Future<void> deletionFailed(String id, int Function(int) delayMs) =>
      db.transaction((tx) async {
        final current = await state(tx);
        if (!current.deletionPending || current.installationId != id) return;
        final attempt = current.deletionAttempts + 1;
        await tx.update('analytics_state', {
          'deletion_attempts': attempt,
          'deletion_next_attempt':
              DateTime.now().millisecondsSinceEpoch + delayMs(attempt),
        }, where: 'id=1');
      });
  Future<void> retryDeletion() => db.transaction((tx) async {
    await tx.update('analytics_state', {
      'deletion_next_attempt': 0,
    }, where: 'id=1 AND deletion_pending=1');
  });

  Future<void> prune([int? now]) async => db.transaction(
    (tx) => _prune(tx, now ?? DateTime.now().millisecondsSinceEpoch),
  );
  Future<void> _prune(DatabaseExecutor tx, int now) async {
    for (final table in ['analytics_runs', 'analytics_marks']) {
      await tx.delete(
        table,
        where: 'created_at < ?',
        whereArgs: [now - retention.inMilliseconds],
      );
      await tx.rawDelete(
        'DELETE FROM $table WHERE rowid IN (SELECT rowid FROM $table ORDER BY created_at DESC,rowid DESC LIMIT -1 OFFSET 10000)',
      );
    }
    await tx.delete(
      'analytics_outbox',
      where: 'created_at < ?',
      whereArgs: [now - retention.inMilliseconds],
    );
    await tx.rawDelete(
      'DELETE FROM analytics_outbox WHERE event_id IN (SELECT event_id FROM analytics_outbox ORDER BY created_at DESC, rowid DESC LIMIT -1 OFFSET ?)',
      [maxEvents],
    );
  }

  Future<bool> add(
    String type,
    Payload payload, {
    int schemaVersion = 1,
    String? platform,
    String? appVersion,
  }) async {
    if (!validPayload(type, payload, schemaVersion: schemaVersion) ||
        schemaVersion == 2 &&
            (!{'android', 'ios'}.contains(platform) ||
                appVersion == null ||
                !RegExp(
                  r'^\d{1,4}\.\d{1,4}\.\d{1,4}\+\d{1,10}$',
                ).hasMatch(appVersion)))
      throw ArgumentError('Invalid analytics payload');
    return db.transaction((tx) async {
      final current = await state(tx);
      if (!current.enabled ||
          current.installationId == null ||
          current.deletionPending ||
          schemaVersion == 2 && current.consentVersion < 2)
        return false;
      final now = DateTime.now().millisecondsSinceEpoch;
      final precision = schemaVersion == 2
          ? const Duration(minutes: 1)
          : const Duration(hours: 1);
      final hour = now - now % precision.inMilliseconds;
      if (schemaVersion == 2) {
        if (payload.containsKey('searchId') &&
            type != 'search_started' &&
            (await tx.query(
              'analytics_runs',
              where: 'search_id=?',
              whereArgs: [payload['searchId']],
            )).isEmpty)
          return false;
        final terminal = {
          'search_completed',
          'search_cancelled',
          'search_failed',
          'search_interrupted',
        }.contains(type);
        final entity = (payload['searchId'] ?? payload['sessionId']) as String;
        final kind = terminal ? 'terminal' : type;
        if ((await tx.query(
          'analytics_marks',
          where: 'entity_id=? AND kind=?',
          whereArgs: [entity, kind],
        )).isNotEmpty)
          return false;
        await tx.insert('analytics_marks', {
          'entity_id': entity,
          'kind': kind,
          'created_at': now,
        });
        if (type == 'search_started')
          await tx.insert('analytics_runs', {
            'search_id': entity,
            'created_at': now,
            'payload': jsonEncode(payload),
            'platform': platform,
            'app_version': appVersion,
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        if (terminal)
          await tx.update(
            'analytics_runs',
            {'terminal': 1},
            where: 'search_id=?',
            whereArgs: [entity],
          );
      }
      await tx.insert('analytics_outbox', {
        'event_id': randomUuid(),
        'installation_id': current.installationId,
        'type': type,
        'schema_version': schemaVersion,
        'platform': platform,
        'app_version': appVersion,
        'created_at': hour,
        'payload': jsonEncode(payload),
      });
      await _prune(tx, now);
      return true;
    });
  }

  Future<List<Map<String, Object?>>> due({int? now}) async => db.query(
    'analytics_outbox',
    where: 'state=? AND next_attempt<=?',
    whereArgs: ['pending', now ?? DateTime.now().millisecondsSinceEpoch],
    orderBy: 'created_at,rowid',
    limit: 50,
  );
  static Map<String, Object?> event(Map<String, Object?> row) => {
    'eventId': row['event_id'],
    'installationId': row['installation_id'],
    'type': row['type'],
    'schemaVersion': row['schema_version'],
    'createdAt': DateTime.fromMillisecondsSinceEpoch(
      row['created_at'] as int,
      isUtc: true,
    ).toIso8601String(),
    'payload': jsonDecode(row['payload'] as String),
    if (row['schema_version'] == 2) 'platform': row['platform'],
    if (row['schema_version'] == 2) 'appVersion': row['app_version'],
    'deliveryAttempts': row['attempts'],
  };
  Future<void> recoverInterrupted(String? activeSearchId) async {
    final current = await state();
    if (!current.enabled || current.consentVersion < 2) return;
    final runs = await db.query('analytics_runs', where: 'terminal=0');
    for (final run in runs) {
      if (run['search_id'] == activeSearchId) continue;
      final payload = Map<String, Object>.from(
        jsonDecode(run['payload'] as String) as Map,
      );
      await add(
        'search_interrupted',
        {...payload, 'errorCategory': 'process_interrupted'},
        schemaVersion: 2,
        platform: run['platform'] as String,
        appVersion: run['app_version'] as String,
      );
    }
  }

  Future<void> acknowledge(
    List<Map<String, Object?>> batch,
    Set<String> accepted,
    int Function(int) delayMs,
  ) => db.transaction((tx) async {
    for (final row in batch) {
      final id = row['event_id'] as String;
      if (accepted.contains(id)) {
        await tx.delete(
          'analytics_outbox',
          where: 'event_id=?',
          whereArgs: [id],
        );
      } else {
        final attempt = (row['attempts'] as int) + 1;
        await tx.update(
          'analytics_outbox',
          {
            'attempts': attempt,
            'next_attempt':
                DateTime.now().millisecondsSinceEpoch + delayMs(attempt),
          },
          where: 'event_id=?',
          whereArgs: [id],
        );
      }
    }
  });
  Future<void> close() => db.close();
}

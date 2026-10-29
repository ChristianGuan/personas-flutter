// QA-only: explicit emulator flag, isolated endpoint and private public-image fixtures.
// Never imported from lib/main.dart; never enable on a physical user device.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:sqflite/sqflite.dart';
import 'package:personas_flutter/main.dart';
import 'package:personas_flutter/native_bridge.dart';
import 'package:personas_flutter/search_controller.dart';
import 'package:personas_flutter/analytics/service.dart';
import 'package:personas_flutter/analytics/store.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const allowed = bool.fromEnvironment('PERSONAS_QA_EMULATOR');
  final qemu = await Process.run('/system/bin/getprop', ['ro.kernel.qemu']);
  if (!allowed ||
      qemu.stdout.toString().trim() != '1' ||
      analyticsApi != 'http://10.0.2.2:3100') {
    throw StateError(
      'QA requires an explicitly enabled emulator and isolated endpoint.',
    );
  }
  final a = AnalyticsService();
  final c = SearchController(NativePhotoBridge(), analytics: a);
  runApp(PersonasApp(controller: c));
  unawaited(probe(c, a));
}

Future<void> probe(SearchController c, AnalyticsService a) async {
  final folder = Directory('/data/user/0/co.local.personas/cache/qa-readiness');
  await folder.create(recursive: true);
  final report = File('${folder.path}/report.json');
  final previous = report.existsSync()
      ? jsonDecode(report.readAsStringSync()) as Map<String, dynamic>
      : <String, dynamic>{};
  final checks = Map<String, dynamic>.from(previous['checks'] as Map? ?? {});
  final state = Map<String, dynamic>.from(previous['state'] as Map? ?? {});
  void emit(String phase) => report.writeAsStringSync(
    jsonEncode({'phase': phase, 'checks': checks, 'state': state}),
  );
  void need(bool condition, String message) {
    if (!condition) throw StateError(message);
  }

  Future<void> until(bool Function() ready, {int seconds = 240}) async {
    final limit = DateTime.now().add(Duration(seconds: seconds));
    while (!ready()) {
      need(DateTime.now().isBefore(limit), 'QA timeout');
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  Future<void> gate(String name) async {
    final f = File('${folder.path}/gate-$name');
    await until(f.existsSync);
    await f.delete();
  }

  try {
    await until(() => File('${folder.path}/ready').existsSync());
    await a.initialize();
    need(a.ready, 'Analytics initialization failed');
    await c.initialize();
    await Future<void>.delayed(const Duration(seconds: 1));
    final store = AnalyticsStore(
      await openDatabase(
        '${await getDatabasesPath()}/personas_analytics.db',
        singleInstance: false,
      ),
    );
    Future<List<Map<String, Object?>>> queue() =>
        store.db.query('analytics_outbox');
    Future<void> drain() async {
      final deadline = DateTime.now().add(const Duration(seconds: 90));
      while ((await queue()).isNotEmpty) {
        need(DateTime.now().isBefore(deadline), 'Outbox did not drain');
        await store.db.update('analytics_outbox', {'next_attempt': 0});
        await a.flush();
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
    }

    final phase = previous['phase'];
    if (phase == 'before_process_restart') {
      need(
        c.processed == state['restoredProcessed'] &&
            c.cancelled &&
            c.page == StepPage.results,
        'Snapshot not restored',
      );
      checks['process_death_restores_results'] = true;
    } else if (phase == 'offline_queued') {
      need(
        (await queue()).length >= (state['offlineCount'] as int),
        'Offline queue lost after restart',
      );
      need(
        (await store.state()).installationId == state['installationId'],
        'Installation identity changed',
      );
      checks['offline_queue_survives_restart'] = true;
    } else if (phase == 'offline_revoked') {
      final s = await store.state();
      need(
        !s.enabled && s.deletionPending && (await queue()).isEmpty,
        'Revocation not durable',
      );
      checks['offline_revocation_survives_restart'] = true;
    } else {
      need(
        !a.enabled &&
            (await store.state()).installationId == null &&
            (await queue()).isEmpty,
        'Fresh emulator app required',
      );
      await c.clear();
      c.notificationsAsked = true;
      final base = '${folder.path}/fixtures/';
      await c.useReference(Uri.file('${base}reference.jpg').toString());
      need(c.chosen != null, 'Reference did not load');
      c.addPhotos(
        [
          'reference.jpg',
          'same-person.jpg',
          'same-person.heic',
          'other-person.jpg',
          'no-face.png',
          'broken.jpg',
        ].map((n) => Uri.file('$base$n').toString()).toList(),
      );
      await c.search();
      await until(() => !c.busy);
      need(
        c.processed == 6 && c.skipped == 1 && c.results.length == 3,
        'No-consent search failed',
      );
      need(
        (await queue()).isEmpty && (await store.state()).installationId == null,
        'Captured without consent',
      );
      checks['search_without_consent_no_queue_or_identity'] = true;
      List<String> batch(String prefix) =>
          Directory(base)
              .listSync()
              .whereType<File>()
              .where((f) => f.uri.pathSegments.last.startsWith(prefix))
              .map((f) => f.uri.toString())
              .toList()
            ..sort();
      final bg = batch('background-');
      need(bg.length >= 40, 'Missing public background fixtures');
      c.addPhotos(bg);
      await c.search();
      emit('background_running');
      await until(() => !c.busy);
      need(c.processed == c.photos.length, 'Background batch incomplete');
      state['backgroundProcessed'] = c.processed;
      checks['background_search_completed'] = true;
      emit('background_finished');
      await gate('foreground');
      await c.resume();
      need(
        c.processed == state['backgroundProcessed'],
        'Foreground results changed',
      );
      checks['foreground_keeps_results'] = true;
      await c.search();
      await c.cancel();
      await until(() => !c.busy);
      need(c.cancelled && c.canSearch, 'In-app cancel failed');
      checks['in_app_cancel'] = true;
      final cold = batch('notification-');
      need(cold.length >= 80, 'Missing notification fixtures');
      c.addPhotos(cold);
      emit('notification_permission');
      await gate('notifications');
      await c.resume();
      await c.search();
      emit('notification_running');
      await until(() => !c.busy);
      need(c.cancelled, 'Notification cancel failed');
      checks['notification_cancel'] = true;
      state['restoredProcessed'] = c.processed;
      emit('before_process_restart');
      return;
    }
    if (phase == 'before_process_restart') {
      final http = HttpClient();
      try {
        final res = await (await http.getUrl(
          Uri.parse('$analyticsApi/v1/analytics/history'),
        )).close();
        need(res.statusCode == 401, 'QA API preflight failed');
        await res.drain<void>();
      } finally {
        http.close(force: true);
      }
      emit('privacy_wait_offline');
      await gate('offline');
      await a.setConsent(true);
      a.record('session_ended', {'durationMs': 1234});
      await Future<void>.delayed(const Duration(seconds: 2));
      need((await queue()).isNotEmpty, 'Offline events not queued');
      state['offlineCount'] = (await queue()).length;
      state['installationId'] = (await store.state()).installationId;
      checks['offline_events_durable'] = true;
      emit('offline_queued');
      return;
    }
    if (phase == 'offline_queued') {
      emit('offline_restart_verified');
      await gate('online');
      await store.db.update('analytics_outbox', {'next_attempt': 0});
      await a.flush();
      await Future<void>.delayed(const Duration(seconds: 2));
      need(
        (await queue()).isNotEmpty &&
            (await queue()).any((r) => (r['attempts'] as int) > 0),
        'Lost ACK not retained',
      );
      checks['lost_ack_keeps_outbox'] = true;
      emit('ack_lost');
      await gate('retry');
      await drain();
      checks['accepted_events_leave_outbox'] = true;
      emit('synced');
      await gate('revoke-offline');
      a.background();
      a.foreground();
      await Future<void>.delayed(const Duration(seconds: 1));
      need((await queue()).isNotEmpty, 'No pending event before revoke');
      await a.setConsent(false);
      a.record('session_started');
      await Future<void>.delayed(const Duration(seconds: 1));
      final s = await store.state();
      need(
        !s.enabled && s.deletionPending && (await queue()).isEmpty,
        'Offline revoke failed',
      );
      for (final t in ['analytics_runs', 'analytics_marks']) {
        need(
          (await store.db.query(t)).isEmpty,
          'Local tracking retained after revoke',
        );
      }
      checks['offline_revoke_clears_queue_and_stops_capture'] = true;
      emit('offline_revoked');
      return;
    }
    if (phase == 'offline_revoked') {
      emit('revocation_restart_verified');
      await gate('delete-online');
      await a.retryDeletion();
      final deadline = DateTime.now().add(const Duration(seconds: 90));
      while ((await store.state()).deletionPending) {
        need(DateTime.now().isBefore(deadline), 'Deletion did not finish');
        await a.retryDeletion();
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
      need(
        !a.enabled && (await queue()).isEmpty,
        'Capture restarted after revoke',
      );
      checks['deletion_after_reconnection'] = true;
      state.remove('installationId');
      emit('complete');
      a.dispose();
      c.dispose();
    }
  } catch (e, st) {
    state['error'] = e.toString();
    state['stack'] = st.toString();
    emit('failed');
  }
}

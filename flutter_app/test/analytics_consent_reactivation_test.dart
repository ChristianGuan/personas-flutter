import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:personas_flutter/analytics/service.dart';
import 'package:personas_flutter/analytics/store.dart';
import 'package:personas_flutter/analytics/privacy_panel.dart';
import 'analytics_test.dart' show Vault, Transport;

class FallibleVault extends Vault {
  bool fail = false;
  int writes = 0;
  @override
  Future<void> write(String value) async {
    writes++;
    if (fail) throw StateError('storage unavailable');
    await super.write(value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Directory directory;
  late AnalyticsStore store;
  late AnalyticsService service;
  late FallibleVault vault;
  late Transport transport;
  Future<void> settleState() async {
    for (var i = 0; i < 12; i++) {
      await service.flush();
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('halladin-consent-');
    PackageInfo.setMockInitialValues(
      appName: 'Halladín',
      packageName: 'co.local.personas',
      version: '1',
      buildNumber: '1',
      buildSignature: '',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
          (_) async => null,
        );
    vault = FallibleVault();
    transport = Transport()..offline = true;
    store = await AnalyticsStore.open(
      factory: databaseFactoryFfi,
      path: '${directory.path}/personas_analytics.db',
    );
    service = AnalyticsService(
      vault: vault,
      transport: transport,
      store: store,
    );
    await service.initialize();
    expect(service.ready, true);
  });
  tearDown(() async {
    await settleState();
    service.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await store.close();
    await directory.delete(recursive: true);
  });
  test(
    'off on persists while offline then restarts with a new identity after deletion',
    () async {
      await service.setConsent(true);
      await settleState();
      final first = (await store.state()).installationId;
      expect(service.enabled, true);
      await service.setConsent(false);
      await settleState();
      expect(service.pendingDeletion, true);
      expect(service.consentRequested, false);
      await service.setConsent(true);
      await settleState();
      expect(service.consentRequested, true);
      expect(service.enabled, false);
      service.record('session_started');
      await settleState();
      expect(await store.db.query('analytics_outbox'), isEmpty);
      expect((await store.state()).reenableRequested, true);
      service.dispose();
      await store.close();
      store = await AnalyticsStore.open(
        factory: databaseFactoryFfi,
        path: '${directory.path}/personas_analytics.db',
      );
      service = AnalyticsService(
        vault: vault,
        transport: transport,
        store: store,
      );
      await service.initialize();
      await settleState();
      expect(service.consentRequested, true);
      expect(service.enabled, false);
      transport.offline = false;
      await service.retryDeletion();
      await settleState();
      expect(service.enabled, true);
      expect(service.pendingDeletion, false);
      expect((await store.state()).reenableRequested, false);
      expect((await store.state()).installationId, isNot(first));
      expect(transport.deleted, true);
    },
  );
  test(
    'a pending restart can be cancelled before deletion is confirmed',
    () async {
      await service.setConsent(true);
      await settleState();
      await service.setConsent(false);
      await settleState();
      await service.setConsent(true);
      await settleState();
      await service.setConsent(false);
      await settleState();
      expect(service.consentRequested, false);
      expect((await store.state()).reenableRequested, false);
      transport.offline = false;
      await service.retryDeletion();
      await settleState();
      expect(service.enabled, false);
      expect((await store.state()).installationId, isNull);
    },
  );
  test(
    'credential failure preserves the restart choice without a tight retry loop',
    () async {
      await service.setConsent(true);
      await settleState();
      await service.setConsent(false);
      await settleState();
      await service.setConsent(true);
      await settleState();
      vault.fail = true;
      transport.offline = false;
      await service.retryDeletion();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(service.enabled, false);
      expect(service.consentRequested, true);
      final writes = vault.writes;
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(vault.writes, writes);
      vault.fail = false;
      await settleState();
      expect(service.enabled, true);
    },
  );
  testWidgets(
    'the real consent switch can be rechecked while deletion is pending',
    (tester) async {
      await tester.runAsync(() async {
        await service.setConsent(true);
        await settleState();
        await service.setConsent(false);
        await settleState();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AnalyticsPrivacyPanel(service: service),
            ),
          ),
        ),
      );
      await tester.ensureVisible(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNotNull);
      await tester.tap(find.byType(Switch));
      await tester.runAsync(settleState);
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(find.byType(Switch)).value, true);
      expect(service.enabled, false);
      expect((await tester.runAsync(store.state))!.reenableRequested, true);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

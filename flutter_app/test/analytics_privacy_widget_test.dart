import 'package:flutter/material.dart' hide SearchController;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:personas_flutter/analytics/privacy_panel.dart';
import 'package:personas_flutter/main.dart';
import 'package:personas_flutter/analytics/service.dart';
import 'package:personas_flutter/search_controller.dart';
import 'search_controller_test.dart' show TestBridge;

class TestAnalytics extends AnalyticsService {
  bool consent = false;
  @override
  bool get ready => true;
  @override
  bool get enabled => consent;
  @override
  Future<void> setConsent(bool value) async {
    consent = value;
    notifyListeners();
  }
}

void main() {
  testWidgets('privacy policy opens without analytics consent', (tester) async {
    final analytics = TestAnalytics();
    final calls = <MethodCall>[];
    const channel = MethodChannel('co.local.personas/photos');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      return null;
    });
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
      analytics.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AnalyticsPrivacyPanel(service: analytics),
          ),
        ),
      ),
    );
    await tester.ensureVisible(find.text('Política de privacidad'));
    await tester.tap(find.text('Política de privacidad'));
    await tester.pumpAndSettle();
    expect(calls.single.method, 'openPrivacyPolicy');
    expect(analytics.enabled, false);
    expect(tester.takeException(), isNull);
  });

  testWidgets('browser failure shows the policy URL without blocking the app', (
    tester,
  ) async {
    final analytics = TestAnalytics();
    const channel = MethodChannel('co.local.personas/photos');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      _,
    ) async {
      throw PlatformException(code: 'browser_unavailable');
    });
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
      analytics.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AnalyticsPrivacyPanel(service: analytics),
          ),
        ),
      ),
    );
    await tester.ensureVisible(find.text('Política de privacidad'));
    await tester.tap(find.text('Política de privacidad'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining(AnalyticsPrivacyPanel.privacyUrl),
      findsOneWidget,
    );
    expect(analytics.enabled, false);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'consent is reachable from results, optional and scrollable on a small screen',
    (tester) async {
      tester.view.physicalSize = const Size(640, 960);
      tester.view.devicePixelRatio = 2;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      final bridge = TestBridge(), analytics = TestAnalytics();
      final c = SearchController(bridge, analytics: analytics)
        ..page = StepPage.results;
      c.reviews.add(const Review('local-photo', 'match', null));
      await tester.pumpWidget(PersonasApp(controller: c));
      await tester.tap(find.widgetWithText(TextButton, 'Analítica'));
      await tester.pumpAndSettle();
      expect(analytics.enabled, false);
      expect(find.text('Ayúdanos a mejorar'), findsOneWidget);
      await Scrollable.ensureVisible(
        tester.element(find.byType(Switch)),
        alignment: 0.5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(analytics.enabled, true);
      await tester.tap(find.text('Cerrar'));
      await tester.pumpAndSettle();
      expect(c.page, StepPage.results);
      expect(c.results, ['local-photo']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      analytics.dispose();
      await bridge.stream.close();
    },
  );

  testWidgets(
    'home disclosures explain the flow and require explicit consent at 200 percent text',
    (tester) async {
      tester.view.physicalSize = const Size(640, 960);
      tester.view.devicePixelRatio = 2;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      Future<void> reveal(Finder target, double delta) async {
        for (
          var i = 0;
          i < 80 && target.hitTestable().evaluate().isEmpty;
          i++
        ) {
          await tester.drag(find.byType(CustomScrollView), Offset(0, delta));
          await tester.pumpAndSettle();
        }
        expect(target.hitTestable(), findsOneWidget);
      }

      final bridge = TestBridge(), analytics = TestAnalytics();
      final c = SearchController(bridge, analytics: analytics);
      await tester.pumpWidget(PersonasApp(controller: c));
      await tester.pumpAndSettle();
      expect(find.byType(Switch), findsNothing);
      await reveal(find.text('Ayúdanos a mejorar'), -180);
      await tester.tap(find.text('Ayúdanos a mejorar'));
      await tester.pumpAndSettle();
      expect(analytics.enabled, false);
      await reveal(find.byType(Switch), -180);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(analytics.enabled, true);
      await reveal(find.text('Ayúdanos a mejorar'), 180);
      await tester.tap(find.text('Ayúdanos a mejorar'));
      await tester.pumpAndSettle();
      expect(find.byType(Switch), findsNothing);
      expect(analytics.enabled, true);
      await reveal(find.text('Así encuentras tus fotos'), 180);
      await tester.tap(find.text('Así encuentras tus fotos'));
      await tester.pumpAndSettle();
      for (final title in [
        'Elige a tu persona',
        'Elige dónde buscar',
        'Reúne tus favoritas',
      ]) {
        await reveal(find.text(title), -180);
        expect(find.text(title), findsOneWidget);
      }
      expect(c.page, StepPage.home);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      analytics.dispose();
      await bridge.stream.close();
    },
  );
}

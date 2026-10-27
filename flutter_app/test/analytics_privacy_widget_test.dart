import 'package:flutter/material.dart' hide SearchController;
import 'package:flutter_test/flutter_test.dart';
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
}

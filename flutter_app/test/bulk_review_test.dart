import 'package:flutter/material.dart' hide SearchController;
import 'package:flutter_test/flutter_test.dart';
import 'package:personas_flutter/main.dart';
import 'package:personas_flutter/search_controller.dart';
import 'search_controller_test.dart' show TestBridge;

void main() {
  test(
    'bulk confirmation only changes pending photos and respects blocked state',
    () async {
      final bridge = TestBridge();
      final c = SearchController(bridge)..page = StepPage.results;
      c.reviews.addAll([
        const Review('a', 'review', 'ka'),
        const Review('b', 'review', 'kb'),
        const Review('c', 'rejected', 'kc'),
      ]);
      c.busy = true;
      c.confirmPending(['a', 'b']);
      expect(c.pending, hasLength(2));
      c.busy = false;
      c.confirmPending(['a', 'c']);
      expect(c.results, ['a']);
      expect(c.pending.single.id, 'b');
      expect(c.reviews.last.outcome, 'rejected');
      expect(c.selected, isEmpty);
      c.confirmPending(['a', 'b']);
      expect(c.results, ['a', 'b']);
      expect(c.confirmedCount, 2);
      c.dispose();
      await bridge.stream.close();
    },
  );

  testWidgets(
    'sections collapse and bulk review selection can be adjusted before confirmation',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final bridge = TestBridge();
      final c = SearchController(bridge)..page = StepPage.results;
      c.reviews.addAll([
        const Review('match', 'match', 'km'),
        const Review('a', 'review', 'ka'),
        const Review('b', 'review', 'kb'),
      ]);
      await tester.pumpWidget(PersonasApp(controller: c));
      await tester.pumpAndSettle();
      if (find.byTooltip('Cerrar acciones').evaluate().isNotEmpty) {
        await tester.tap(find.byTooltip('Cerrar acciones'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('1 coincidencia'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('result:match')), findsNothing);
      await tester.tap(find.text('1 coincidencia'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('result:match')), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Por revisar (2) · Ocultar'),
        300,
      );
      await tester.tap(find.text('Por revisar (2) · Ocultar'));
      await tester.pumpAndSettle();
      expect(find.text('Seleccionar todas por revisar'), findsNothing);
      await tester.tap(find.text('Por revisar (2) · Mostrar'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Seleccionar todas por revisar'),
        200,
      );
      await tester.tap(find.text('Seleccionar todas por revisar'));
      await tester.pumpAndSettle();
      expect(c.pending, hasLength(2));
      await tester.scrollUntilVisible(
        find.text('Pasar a coincidencias (2)'),
        200,
      );
      await tester.tap(find.text('Pasar a coincidencias (2)'));
      await tester.pumpAndSettle();
      expect(c.pending, isEmpty);
      expect(c.results, containsAll(['match', 'a', 'b']));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      await bridge.stream.close();
    },
  );
}

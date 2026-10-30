import 'package:flutter/material.dart' hide SearchController;
import 'package:flutter_test/flutter_test.dart';
import 'package:personas_flutter/main.dart';
import 'package:personas_flutter/search_controller.dart';
import 'search_controller_test.dart' show TestBridge, reference;

void main() {
  testWidgets(
    'repeat menu allows another person while preserving the photo set',
    (tester) async {
      final bridge = TestBridge();
      bridge.handlers['reference'] = (_) async => reference('person', count: 2);
      final c = SearchController(bridge);
      await c.useReference('person');
      c.choose(c.reference!.faces.first);
      c.addPhotos(['a', 'b']);
      final chosen = c.chosen;
      c.page = StepPage.results;
      c.reviews.add(const Review('a', 'match', 'ka'));
      await tester.pumpWidget(PersonasApp(controller: c));
      await tester.pumpAndSettle();
      expect(find.text('Escaneo completo ·'), findsOneWidget);
      expect(find.byTooltip('Cerrar acciones'), findsOneWidget);
      await tester.tap(find.byTooltip('Cerrar acciones'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Cerrar acciones'), findsNothing);
      expect(
        tester.getCenter(find.byTooltip('Acciones de fotos')).dx,
        greaterThan(600),
      );
      await tester.tap(find.byTooltip('Acciones de fotos'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Buscar de nuevo en el mismo álbum'));
      await tester.pumpAndSettle();
      expect(c.page, StepPage.reference);
      expect(c.chosen, same(chosen));
      expect(bridge.calls.where((call) => call.$1 == 'search'), isEmpty);
      c.choose(c.reference!.faces.last);
      expect(c.chosen, isNot(same(chosen)));
      await c.search();
      await tester.pumpAndSettle();
      expect(c.page, StepPage.analysis);
      expect(c.photos, ['a', 'b']);
      expect(bridge.calls.where((call) => call.$1 == 'search'), hasLength(1));
      expect(bridge.calls.where((call) => call.$1 == 'clear'), isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      await bridge.stream.close();
    },
  );
}

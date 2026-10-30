import 'package:flutter/material.dart' hide SearchController;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personas_flutter/main.dart';
import 'package:personas_flutter/search_controller.dart';
import 'search_controller_test.dart' show TestBridge, reference;

void main() {
  late TestBridge bridge;
  late SearchController c;
  setUp(() async {
    bridge = TestBridge();
    c = SearchController(bridge);
    await c.initialize();
    bridge.handlers['reference'] = (a) async => reference(a!['id']);
    await c.useReference('ref');
    c.addPhotos(['a', 'b']);
    await c.search();
  });
  tearDown(() async {
    c.dispose();
    await bridge.stream.close();
  });
  int run() =>
      bridge.calls.lastWhere((call) => call.$1 == 'search').$2!['runId'] as int;
  void firstPhoto() => bridge.event({
    'type': 'photo',
    'runId': run(),
    'id': 'a',
    'outcome': 'match',
  });
  test(
    'cancel acknowledges immediately, suppresses late progress and completes with partial results',
    () async {
      firstPhoto();
      await c.cancel();
      expect(c.cancelling, true);
      expect(c.busy, true);
      await c.cancel();
      expect(bridge.calls.where((call) => call.$1 == 'cancel').length, 1);
      bridge.event({
        'type': 'photo',
        'runId': run(),
        'id': 'b',
        'outcome': 'match',
      });
      expect(c.processed, 1);
      bridge.event({'type': 'done', 'runId': run(), 'cancelled': true});
      expect(c.busy, false);
      expect(c.cancelling, false);
      expect(c.cancelled, true);
      expect(c.results, ['a']);
      expect(c.page, StepPage.results);
      await c.search();
      expect(c.analysing, true);
      expect(c.cancelling, false);
    },
  );
  test(
    'notification cancellation status and transport failure remain recoverable',
    () async {
      bridge.handlers['cancel'] = (_) async =>
          throw PlatformException(code: 'temporary');
      await c.cancel();
      expect(c.cancelling, false);
      expect(c.busy, true);
      bridge.event({'type': 'status', 'runId': run(), 'cancelling': true});
      expect(c.cancelling, true);
      bridge.event({'type': 'done', 'runId': run(), 'cancelled': true});
      expect(c.busy, false);
      expect(c.cancelling, false);
    },
  );
  test(
    'restored cancelled snapshot keeps partials and releases the controls',
    () async {
      final id = run();
      bridge.handlers['searchSnapshot'] = (_) async => {
        'runId': id,
        'active': false,
        'cancelling': true,
        'referencesAvailable': true,
        'context': {
          'photos': ['a', 'b'],
          'reference': reference('ref'),
          'chosen': reference('ref')['faces'][0],
        },
        'events': [
          {'type': 'photo', 'runId': id, 'id': 'a', 'outcome': 'match'},
        ],
        'done': {'type': 'done', 'runId': id, 'cancelled': true},
      };
      await c.resume(openResults: true);
      expect(c.results, ['a']);
      expect(c.cancelled, true);
      expect(c.cancelling, false);
      expect(c.canSearch, true);
    },
  );
  testWidgets('cancel button shows pending state until native completion', (
    tester,
  ) async {
    firstPhoto();
    await tester.pumpWidget(PersonasApp(controller: c));
    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancelar análisis'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Cancelar análisis'));
    await tester.pumpAndSettle();
    final button = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Cancelando…'),
    );
    expect(button.onPressed, isNull);
    expect(find.text('Deteniendo la búsqueda'), findsOneWidget);
    bridge.event({'type': 'done', 'runId': run(), 'cancelled': true});
    await tester.pumpAndSettle();
    expect(c.cancelled, true);
    expect(c.page, StepPage.results);
    await tester.tap(find.byTooltip('Cerrar acciones'));
    await tester.pumpAndSettle();
    expect(find.text('Escaneo cancelado ·'), findsOneWidget);
    expect(c.results, ['a']);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

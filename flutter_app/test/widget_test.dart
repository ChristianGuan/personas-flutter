import 'dart:async';
import 'package:flutter/material.dart' hide SearchController;
import 'package:flutter_test/flutter_test.dart';
import 'package:personas_flutter/main.dart';
import 'package:personas_flutter/native_bridge.dart';
import 'package:personas_flutter/search_controller.dart';
import 'package:personas_flutter/ui_components.dart';
import 'background_controller_test.dart' show snapshot;
import 'search_controller_test.dart' show TestBridge, reference;

void main() {
  testWidgets('step 3 count follows incoming matches, completion and review', (tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(() { tester.view.resetPhysicalSize(); tester.view.resetDevicePixelRatio(); });
    final bridge = TestBridge();
    final c = SearchController(bridge);
    await c.initialize();
    bridge.handlers['reference'] = (a) async => reference(a!['id']);
    await c.useReference('person');
    c.addPhotos(['a', 'b', 'c']);
    await c.search();
    final run = bridge.calls.lastWhere((call) => call.$1 == 'search').$2!['runId'];
    await tester.pumpWidget(PersonasApp(controller: c));
    await tester.pumpAndSettle();
    expect(find.text('0 coincidencias'), findsOneWidget);
    bridge.event({'type':'photo','runId':run,'id':'a','outcome':'match','key':'ka'});
    await tester.pump();
    expect(find.text('1 coincidencia'), findsOneWidget);
    bridge.event({'type':'photo','runId':run,'id':'b','outcome':'match','key':'kb'});
    bridge.event({'type':'photo','runId':run,'id':'c','outcome':'review','key':'kc'});
    await tester.pump();
    expect(find.text('2 coincidencias'), findsOneWidget);
    bridge.event({'type':'done','runId':run,'cancelled':false});
    await tester.pumpAndSettle();
    expect(find.text('2 coincidencias'), findsOneWidget);
    c.confirm('c',true);
    await tester.pump();
    expect(find.text('3 coincidencias'), findsOneWidget);
    c.confirm('a',false);
    await tester.pump();
    expect(find.text('2 coincidencias'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();await bridge.stream.close();
  });

  for (final useBack in [false, true]) {
    testWidgets('stalled iOS reference can be cancelled with back=$useBack', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(640, 960);
      tester.view.devicePixelRatio = 2;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      final bridge = TestBridge();
      final c = SearchController(bridge)..platform = 'ios';
      bridge.handlers['reference'] = (_) async => reference('existing');
      await c.useReference('existing');
      final pending = Completer<Json>();
      bridge.handlers['reference'] = (_) => pending.future;
      final loading = c.useReference('stalled');
      await tester.pumpWidget(PersonasApp(controller: c));
      await tester.pump(const Duration(milliseconds: 200));
      final cancel = find.widgetWithText(OutlinedButton, 'Cancelar carga');
      expect(cancel, findsOneWidget);
      expect(tester.getRect(cancel).bottom, lessThanOrEqualTo(480));
      await tester.tap(useBack ? find.byTooltip('Volver') : cancel);
      await tester.pumpAndSettle();
      expect(c.blocked, isFalse);
      expect(c.page, useBack ? StepPage.home : StepPage.reference);
      expect(c.reference!.image, 'existing');
      expect(find.byType(LinearProgressIndicator), findsNothing);
      pending.complete(reference('stale'));
      await loading;
      await tester.pumpAndSettle();
      expect(c.reference!.image, 'existing');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      await bridge.stream.close();
    });
  }
  for (final available in [false, true]) {
    testWidgets(
      'back arrow from restored iOS results works with references available=$available',
      (tester) async {
        final bridge = TestBridge();
        bridge.handlers['initialize'] = (_) async => {
          'platform': 'ios',
          'access': 'full',
          'search': snapshot(available: available),
        };
        bridge.handlers['albums'] = (_) async => {
          'access': 'full',
          'albums': [],
        };
        final c = SearchController(bridge);
        await c.initialize();
        c.toggle('a');
        await tester.pumpWidget(PersonasApp(controller: c));
        await tester.pumpAndSettle();
        expect(find.text('Tus momentos'), findsOneWidget);

        await tester.tap(find.byTooltip('Volver'));
        await tester.pumpAndSettle();
        expect(c.page, available ? StepPage.albums : StepPage.reference);
        expect(
          find.text(available ? 'Tus fotos' : 'Tu persona'),
          findsOneWidget,
        );
        if (!available) {
          expect(find.text('Elegir foto de referencia'), findsOneWidget);
        }
        expect(c.photos, ['a', 'b', 'bad']);
        expect(c.results, ['a']);
        expect(c.selected, {'a'});
        expect(
          bridge.calls.where((call) => call.$1 == 'albums').length,
          available ? 1 : 0,
        );
        expect(
          bridge.calls.any((call) => call.$1 == 'clear' || call.$1 == 'search'),
          isFalse,
        );

        if (available) {
          await tester.tap(find.byTooltip('Volver'));
          await tester.pumpAndSettle();
          expect(c.page, StepPage.reference);
        }
        await tester.tap(find.byTooltip('Volver'));
        await tester.pumpAndSettle();
        expect(find.text('Encuentra tus mejores momentos'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        c.dispose();
        await bridge.stream.close();
      },
    );
  }
  testWidgets(
    'clearing a scrolled result grid preserves outgoing transition data',
    (tester) async {
      final bridge = TestBridge();
      final session = SearchController(bridge);
      session.page = StepPage.results;
      session.reviews.addAll(
        List.generate(40, (i) => Review('p$i', 'match', 'key$i')),
      );
      await tester.pumpWidget(PersonasApp(controller: session));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
      await tester.pumpAndSettle();
      await session.clear();
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(find.text('Encuentra tus mejores momentos'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
      await bridge.stream.close();
    },
  );
  testWidgets('home explains the flow and the primary action opens reference', (
    tester,
  ) async {
    final bridge = TestBridge();
    final c = SearchController(bridge);
    await tester.pumpWidget(PersonasApp(controller: c));
    expect(find.text('Encuentra tus mejores momentos'), findsOneWidget);
    await tester.tap(find.text('Buscar a una persona'));
    await tester.pumpAndSettle();
    expect(find.text('Elegir foto de referencia'), findsOneWidget);
    expect(find.text('Elegir álbum'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    await bridge.stream.close();
  });
  testWidgets('small screen and 200 percent text keep fixed action reachable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(640, 960);
    tester.view.devicePixelRatio = 2;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    final bridge = TestBridge();
    final c = SearchController(bridge);
    await tester.pumpWidget(PersonasApp(controller: c));
    final button = find.widgetWithText(FilledButton, 'Buscar a una persona');
    expect(tester.getRect(button).bottom, lessThanOrEqualTo(480));
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Elige un rostro para continuar'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    await bridge.stream.close();
  });
  testWidgets('denied albums keep the individual and files alternatives', (
    tester,
  ) async {
    final bridge = TestBridge();
    final c = SearchController(bridge);
    c.page = StepPage.albums;
    await tester.pumpWidget(PersonasApp(controller: c));
    expect(find.text('Elegir fotos'), findsOneWidget);
    expect(find.text('Elegir desde Archivos'), findsOneWidget);
    expect(find.text('Permitir acceso a álbumes'), findsOneWidget);
    expect(find.byType(ScanSpeedNote), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    await bridge.stream.close();
  });
  testWidgets(
    'steps support small dark screens, large text and reduced motion through selection',
    (tester) async {
      tester.view.physicalSize = const Size(640, 960);
      tester.view.devicePixelRatio = 2;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
        tester.platformDispatcher.clearPlatformBrightnessTestValue();
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
      });
      final semantics = tester.ensureSemantics();
      final bridge = TestBridge();
      final c = SearchController(bridge);
      c.backgroundMode = 'iosLimited';
      c.reference = Reference('person', 'person', 1000, 800, [
        const Face('face', .1, .1, .3, .4),
      ]);
      c.chosen = c.reference!.faces.first;
      c.photos = ['one', 'two', 'three', 'four', 'five'];
      c.access = 'full';
      c.albums = [
        const Album('a', 'Tus recuerdos de vacaciones en familia', 'one', 350),
      ];
      c.reviews.add(const Review('one', 'match', 'key'));
      c.processed = 2;
      for (final page in [
        StepPage.reference,
        StepPage.albums,
        StepPage.analysis,
        StepPage.results,
      ]) {
        c.page = page;
        c.busy = page == StepPage.analysis;
        await tester.pumpWidget(
          PersonasApp(key: ValueKey(page), controller: c),
        );
        await tester.pumpAndSettle();

        expect(
          find.bySemanticsLabel(RegExp('Paso [123] de 3:')),
          findsOneWidget,
        );
        if (page == StepPage.analysis) {
          await tester.scrollUntilVisible(find.byType(ScanProgress), 200);
          expect(find.text('Procesadas 2 de 5 fotos'), findsOneWidget);
          expect(
            tester
                .widget<LinearProgressIndicator>(
                  find.byType(LinearProgressIndicator),
                )
                .value,
            .4,
          );
        }
        if (page == StepPage.albums) {
          await tester.scrollUntilVisible(find.byType(ScanSpeedNote), 200);
          expect(find.text(ScanSpeedNote.message), findsOneWidget);
          await tester.drag(
            find.byType(CustomScrollView),
            const Offset(0, -1200),
          );
          await tester.pumpAndSettle();
        }
        if (page == StepPage.results) {
          expect(
            tester.getSize(find.byType(CustomScrollView)).height,
            greaterThan(100),
          );
          // A photo tile is taller than this viewport. Reveal its checkbox with
          // actual scrolling rather than aligning the entire tile to the top.
          for (
            var i = 0;
            i < 20 && find.text('Elegir').hitTestable().evaluate().isEmpty;
            i++
          ) {
            await tester.drag(
              find.byType(CustomScrollView),
              const Offset(0, -160),
            );
            await tester.pumpAndSettle();
          }
          await tester.tap(find.text('Elegir'));
          await tester.pumpAndSettle();
          expect(c.selected, {'one'});
          expect(find.text('1 foto'), findsOneWidget);
          expect(find.bySemanticsLabel('1 foto seleccionada'), findsOneWidget);
          final share = find.widgetWithText(
            FilledButton,
            'Compartir selección',
          );
          expect(tester.widget<FilledButton>(share).onPressed, isNotNull);
          expect(tester.getRect(share).bottom, lessThanOrEqualTo(480));
        }
        expect(tester.takeException(), isNull, reason: page.name);
      }
      await tester.pumpWidget(const SizedBox());
      semantics.dispose();
      c.dispose();
      await bridge.stream.close();
    },
  );
  testWidgets(
    'empty results explain the next action and sharing stays disabled',
    (tester) async {
      final bridge = TestBridge();
      final c = SearchController(bridge);
      c.page = StepPage.results;
      await tester.pumpWidget(PersonasApp(controller: c));
      await tester.pumpAndSettle();
      expect(find.text('No encontramos coincidencias'), findsOneWidget);
      expect(find.text('Cambiar referencia'), findsOneWidget);
      final share = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Compartir selección'),
      );
      expect(share.onPressed, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      await bridge.stream.close();
    },
  );
}

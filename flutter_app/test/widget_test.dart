import 'dart:async';
import 'package:flutter/material.dart' hide SearchController;
import 'package:flutter_test/flutter_test.dart';
import 'package:personas_flutter/main.dart';
import 'package:personas_flutter/native_bridge.dart';
import 'package:personas_flutter/search_controller.dart';
import 'package:personas_flutter/ui_components.dart';
import 'background_controller_test.dart' show snapshot;
import 'search_controller_test.dart' show TestBridge, reference;

Future<void> revealInBody(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 150);
  for (var i = 0; i < 40 && finder.hitTestable().evaluate().isEmpty; i++) {
    final viewport = tester.getRect(find.byType(CustomScrollView));
    final dy = tester.getCenter(finder).dy > viewport.center.dy ? -60.0 : 60.0;
    await tester.drag(find.byType(CustomScrollView), Offset(0, dy));
    await tester.pumpAndSettle();
  }
  expect(finder.hitTestable(), findsOneWidget);
}

Future<void> openPhotoActions(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Acciones de fotos'));
  await tester.pumpAndSettle();
}

void main() {
  for (final hasMatches in [true, false]) {
    testWidgets(
      'new search starts directly from results (matches: $hasMatches)',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          tester.platformDispatcher.clearTextScaleFactorTestValue();
        });
        final bridge = TestBridge();
        final c = SearchController(bridge);
        await c.useReference('old-person');
        c.addPhotos(['old-photo']);
        c.page = StepPage.results;
        if (hasMatches) {
          c.reviews.addAll(
            List.generate(40, (i) => Review('p$i', 'match', 'key$i')),
          );
          c.selected.add('p0');
        }
        await tester.pumpWidget(PersonasApp(controller: c));
        await tester.pumpAndSettle();
        if (find.byTooltip('Cerrar acciones').evaluate().isNotEmpty) {
          await tester.tap(find.byTooltip('Cerrar acciones'));
          await tester.pumpAndSettle();
        }
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
        await tester.pumpAndSettle();
        await openPhotoActions(tester);
        final start = find.widgetWithText(TextButton, 'Nueva búsqueda');
        await tester.scrollUntilVisible(
          start,
          100,
          scrollable: find.byType(Scrollable).last,
        );
        expect(start.hitTestable(), findsOneWidget);
        await tester.tap(start);
        await tester.pumpAndSettle();
        expect(c.page, StepPage.reference);
        expect(c.reference, isNull);
        expect(c.photos, isEmpty);
        expect(c.results, isEmpty);
        expect(c.selected, isEmpty);
        expect(bridge.calls.where((call) => call.$1 == 'clear').length, 1);
        await revealInBody(tester, find.text('Elegir foto de referencia'));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        c.dispose();
        await bridge.stream.close();
      },
    );
  }
  testWidgets(
    'dragging beyond the top does not reveal a blank gap',
    (tester) async {
      final bridge = TestBridge();
      final c = SearchController(bridge);
      c.reviews.addAll(
        List.generate(20, (i) => Review('match-$i', 'match', 'key-$i')),
      );
      await tester.pumpWidget(PersonasApp(controller: c));
      await tester.pumpAndSettle();
      if (find.byTooltip('Cerrar acciones').evaluate().isNotEmpty) {
        await tester.tap(find.byTooltip('Cerrar acciones'));
        await tester.pumpAndSettle();
      }
      for (final page in [
        StepPage.home,
        StepPage.reference,
        StepPage.albums,
        StepPage.results,
      ]) {
        c.page = page;
        c.notifyListeners();
        await tester.pumpAndSettle();
        if (find.byTooltip('Cerrar acciones').evaluate().isNotEmpty) {
          await tester.tap(find.byTooltip('Cerrar acciones'));
          await tester.pumpAndSettle();
        }
        final view = find.byType(CustomScrollView);
        final scrollable = find
            .descendant(of: view, matching: find.byType(Scrollable))
            .first;
        final position = tester.state<ScrollableState>(scrollable).position;
        final gesture = await tester.startGesture(tester.getCenter(view));
        await gesture.moveBy(const Offset(0, 180));
        await tester.pump(const Duration(milliseconds: 300));
        expect(position.pixels, position.minScrollExtent, reason: page.name);
        await gesture.up();
        await tester.pumpAndSettle();
        if (position.maxScrollExtent > 0) {
          await tester.drag(view, const Offset(0, -100));
          await tester.pumpAndSettle();
          expect(position.pixels, greaterThan(position.minScrollExtent));
        }
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      await bridge.stream.close();
    },
    variant: TargetPlatformVariant({
      TargetPlatform.iOS,
      TargetPlatform.android,
    }),
  );
  testWidgets('step 3 count follows incoming matches, completion and review', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final bridge = TestBridge();
    final c = SearchController(bridge);
    await c.initialize();
    bridge.handlers['reference'] = (a) async => reference(a!['id']);
    await c.useReference('person');
    c.addPhotos(['a', 'b', 'c']);
    await c.search();
    final run = bridge.calls
        .lastWhere((call) => call.$1 == 'search')
        .$2!['runId'];
    await tester.pumpWidget(PersonasApp(controller: c));
    await tester.pumpAndSettle();
    if (find.byTooltip('Cerrar acciones').evaluate().isNotEmpty) {
      await tester.tap(find.byTooltip('Cerrar acciones'));
      await tester.pumpAndSettle();
    }
    expect(find.text('0 coincidencias · Ocultar'), findsOneWidget);
    bridge.event({
      'type': 'photo',
      'runId': run,
      'id': 'a',
      'outcome': 'match',
      'key': 'ka',
    });
    await tester.pump();
    expect(find.text('1 coincidencia · Ocultar'), findsOneWidget);
    bridge.event({
      'type': 'photo',
      'runId': run,
      'id': 'b',
      'outcome': 'match',
      'key': 'kb',
    });
    bridge.event({
      'type': 'photo',
      'runId': run,
      'id': 'c',
      'outcome': 'review',
      'key': 'kc',
    });
    await tester.pump();
    expect(find.text('2 coincidencias · Ocultar'), findsOneWidget);
    bridge.event({'type': 'done', 'runId': run, 'cancelled': false});
    await tester.pumpAndSettle();
    expect(find.text('2 coincidencias'), findsOneWidget);
    c.confirm('c', true);
    await tester.pump();
    expect(find.text('3 coincidencias'), findsOneWidget);
    c.confirm('a', false);
    await tester.pump();
    expect(find.text('2 coincidencias'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    await bridge.stream.close();
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
        if (find.byTooltip('Cerrar acciones').evaluate().isNotEmpty) {
          await tester.tap(find.byTooltip('Cerrar acciones'));
          await tester.pumpAndSettle();
        }
        expect(find.bySemanticsLabel('Halladín'), findsOneWidget);
        await tester.tap(find.byTooltip('Opciones de resultados'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Volver'));
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
        expect(find.bySemanticsLabel('Encuentra a tu gente'), findsOneWidget);
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
      await tester.tap(find.byTooltip('Cerrar acciones'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
      await tester.pumpAndSettle();
      await session.clear();
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Encuentra a tu gente'), findsOneWidget);
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
    expect(find.bySemanticsLabel('Encuentra a tu gente'), findsOneWidget);
    await tester.tap(find.text('Nueva búsqueda'));
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
    final button = find.widgetWithText(FilledButton, 'Nueva búsqueda');
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
    await tester.scrollUntilVisible(
      find.text('Permitir acceso a álbumes'),
      150,
    );
    expect(find.text('Permitir acceso a álbumes'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Selecciona una a una'), 150);
    expect(find.text('Selecciona una a una'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Elegir desde Archivos'), 150);
    expect(find.text('Elegir desde Archivos'), findsOneWidget);
    expect(find.text('Tu primer escaneo'), findsNothing);
    expect(find.text('Puedes cambiar de app'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    await bridge.stream.close();
  });
  testWidgets(
    'steps retain the light palette with dark system mode, large text and reduced motion',
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

        if (find.byTooltip('Cerrar acciones').evaluate().isNotEmpty) {
          await tester.tap(find.byTooltip('Cerrar acciones'));
          await tester.pumpAndSettle();
        }
        expect(
          Theme.of(tester.element(find.byType(Scaffold).first)).brightness,
          Brightness.light,
        );
        expect(
          page == StepPage.results
              ? find.bySemanticsLabel('Halladín')
              : find.bySemanticsLabel(RegExp('Paso [123] de 3:')),
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
          expect(find.text('Tu primer escaneo'), findsNothing);
          expect(find.text('Puedes cambiar de app'), findsNothing);
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
            i < 80 &&
                find.byTooltip('Elegir foto').hitTestable().evaluate().isEmpty;
            i++
          ) {
            await tester.drag(
              find.byType(CustomScrollView),
              const Offset(0, -60),
            );
            await tester.pumpAndSettle();
          }
          await tester.tap(find.byTooltip('Elegir foto'));
          await tester.pumpAndSettle();
          expect(c.selected, {'one'});
          await openPhotoActions(tester);
          await tester.scrollUntilVisible(
            find.text('Compartir fotos'),
            120,
            scrollable: find.byType(Scrollable).last,
          );
          expect(find.text('1 seleccionada'), findsOneWidget);
          expect(find.bySemanticsLabel(RegExp('1 foto seleccionada')), findsOneWidget);
          final share = find.widgetWithText(TextButton, 'Compartir fotos');
          expect(tester.widget<TextButton>(share).onPressed, isNotNull);
          expect(share.hitTestable(), findsOneWidget);
          await tester.tap(find.byTooltip('Cerrar acciones'));
          await tester.pumpAndSettle();
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
      if (find.byTooltip('Cerrar acciones').evaluate().isNotEmpty) {
        await tester.tap(find.byTooltip('Cerrar acciones'));
        await tester.pumpAndSettle();
      }
      await tester.scrollUntilVisible(
        find.text('No encontramos coincidencias'),
        150,
      );
      expect(find.text('No encontramos coincidencias'), findsOneWidget);
      expect(find.text('Cambiar referencia'), findsOneWidget);
      await openPhotoActions(tester);
      final share = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Compartir fotos'),
      );
      expect(share.onPressed, isNull);
      await tester.tap(find.byTooltip('Cerrar acciones'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      await bridge.stream.close();
    },
  );
  testWidgets(
    'albums precede manual sources and selected reference keeps its change action',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2800);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final bridge = TestBridge();
      bridge.handlers['albumPhotos'] = (_) async => ['one', 'two'];
      final c = SearchController(bridge)
        ..page = StepPage.albums
        ..access = 'full';
      c.reference = Reference('person', 'person', 1000, 800, [
        const Face('face', .1, .1, .3, .4),
      ]);
      c.chosen = c.reference!.faces.first;
      c.albums = [const Album('a', 'Álbum local de prueba', 'one', 2)];
      await tester.pumpWidget(PersonasApp(controller: c));
      await tester.pumpAndSettle();
      if (find.byTooltip('Cerrar acciones').evaluate().isNotEmpty) {
        await tester.tap(find.byTooltip('Cerrar acciones'));
        await tester.pumpAndSettle();
      }
      expect(
        tester.getTopLeft(find.text('Álbum local de prueba')).dy,
        lessThan(tester.getTopLeft(find.text('Selecciona una a una')).dy),
      );
      await tester.tap(find.text('Álbum local de prueba'));
      await tester.pumpAndSettle();
      expect(c.album?.id, 'a');
      expect(c.photos, ['one', 'two']);
      await tester.tap(find.text('Cambiar foto'));
      await tester.pumpAndSettle();
      expect(c.page, StepPage.reference);
      expect(c.photos, ['one', 'two']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      await bridge.stream.close();
    },
  );
  testWidgets(
    'change album beside repeat search preserves reference and does not start recognition',
    (tester) async {
      tester.view.physicalSize = const Size(640, 960);
      tester.view.devicePixelRatio = 2;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      final bridge = TestBridge();
      bridge.handlers['albums'] = (_) async => {'access': 'full', 'albums': []};
      final c = SearchController(bridge)..page = StepPage.reference;
      c.reference = Reference('person', 'person', 1000, 800, [
        const Face('face', .1, .1, .3, .4),
      ]);
      c.chosen = c.reference!.faces.first;
      c.photos = List.generate(209, (i) => 'photo-$i');
      final chosen = c.chosen, reference = c.reference;
      await tester.pumpWidget(PersonasApp(controller: c));
      await tester.pumpAndSettle();
      if (find.byTooltip('Cerrar acciones').evaluate().isNotEmpty) {
        await tester.tap(find.byTooltip('Cerrar acciones'));
        await tester.pumpAndSettle();
      }
      expect(find.text('Buscar de nuevo en 209 fotos'), findsOneWidget);
      final change = find.widgetWithText(TextButton, 'Cambiar álbum');
      expect(tester.getRect(change).bottom, lessThanOrEqualTo(480));
      await tester.tap(change);
      await tester.pumpAndSettle();
      expect(c.page, StepPage.albums);
      expect(c.reference, same(reference));
      expect(c.chosen, same(chosen));
      expect(c.photos, hasLength(209));
      expect(bridge.calls.any((call) => call.$1 == 'search'), false);
      expect(bridge.calls.any((call) => call.$1 == 'albums'), true);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      await bridge.stream.close();
    },
  );
  testWidgets(
    'bulk selection stays visible with many results and shares only accepted matches',
    (tester) async {
      tester.view.physicalSize = const Size(640, 960);
      tester.view.devicePixelRatio = 2;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      final bridge = TestBridge();
      final c = SearchController(bridge)..page = StepPage.results;
      c.reviews.addAll(
        List.generate(80, (i) => Review('match-$i', 'match', 'key-$i')),
      );
      c.reviews.add(const Review('uncertain', 'review', null));
      c.reviews.add(const Review('excluded', 'rejected', null));
      await tester.pumpWidget(PersonasApp(controller: c));
      await tester.pumpAndSettle();
      if (find.byTooltip('Cerrar acciones').evaluate().isNotEmpty) {
        await tester.tap(find.byTooltip('Cerrar acciones'));
        await tester.pumpAndSettle();
      }
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -700));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Acciones de fotos').hitTestable(), findsOneWidget);
      await openPhotoActions(tester);
      final select = find.byTooltip('Seleccionar todas');
      await tester.scrollUntilVisible(
        select,
        120,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(select);
      await tester.pumpAndSettle();
      expect(c.selected, hasLength(80));
      final clearAll = find.byTooltip('Deseleccionar todas');
      expect(clearAll, findsOneWidget);
      expect(c.selected, containsAll(c.results));
      expect(c.selected, isNot(contains('uncertain')));
      final share = find.widgetWithText(TextButton, 'Compartir fotos');
      await tester.scrollUntilVisible(
        share,
        100,
        scrollable: find.byType(Scrollable).last,
      );
      expect(share.hitTestable(), findsOneWidget);
      await tester.tap(share);
      await tester.pumpAndSettle();
      final ids =
          bridge.calls.lastWhere((call) => call.$1 == 'share').$2!['ids']
              as List;
      expect(ids, hasLength(80));
      expect(ids, isNot(contains('uncertain')));
      expect(ids, isNot(contains('excluded')));
      await tester.scrollUntilVisible(
        find.byTooltip('Deseleccionar todas'),
        -100,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.byTooltip('Deseleccionar todas'));
      await tester.pumpAndSettle();
      expect(c.selected, isEmpty);
      expect(tester.widget<TextButton>(share).onPressed, isNull);
      await tester.tap(find.byTooltip('Cerrar acciones'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      await bridge.stream.close();
    },
  );
}

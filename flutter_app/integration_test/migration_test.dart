import 'dart:io';
import 'package:flutter/material.dart' hide SearchController;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:personas_flutter/main.dart';
import 'package:personas_flutter/native_bridge.dart';
import 'package:personas_flutter/search_controller.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'real HEIC reference, fifty photos, negatives, repeated cache and full image',
    (tester) async {
      const provided = String.fromEnvironment('PERSONAS_QA_DIR');
      final path = provided.isNotEmpty
          ? provided
          : Platform.isIOS
          ? Directory.systemTemp.parent.uri
                .resolve('Library/Caches/PersonasSession/qa-flutter/')
                .toString()
          : 'file:///data/user/0/co.local.personas/cache/qa-flutter/';
      final c = SearchController(NativePhotoBridge());
      await c.initialize();
      await c.clear();
      // Exercise denied/optional notifications without an OS prompt blocking QA.
      c.notificationsAsked = true;
      await tester.pumpWidget(PersonasApp(controller: c));
      // The host copies only public fixtures after this explicit session clear;
      // no fixture API ships in production.
      await tester.runAsync(() async {
        final limit = DateTime.now().add(const Duration(minutes: 2));
        while (!File.fromUri(Uri.parse('${path}ready')).existsSync() &&
            DateTime.now().isBefore(limit)) {
          await Future<void>.delayed(const Duration(milliseconds: 300));
        }
      });
      await tester.runAsync(() => c.useReference('${path}face-10bit.heic'));
      expect(c.reference, isNotNull, reason: c.message);
      expect(c.reference!.faces, isNotEmpty);
      if (c.chosen == null) c.choose(c.reference!.faces.first);
      await binding.convertFlutterSurfaceToImage();
      Future<void> settlePhotos() async {
        await tester.pumpAndSettle();
        for (
          var i = 0;
          i < 80 && find.text('Cargando foto…').evaluate().isNotEmpty;
          i++
        ) {
          await tester.pump(const Duration(milliseconds: 100));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
        }
        await tester.pumpAndSettle();
      }

      await settlePhotos();
      await binding.takeScreenshot('flutter-reference');
      final positives = [
        'face-srgb.HEIC',
        'face-10bit.heic',
        'face-p3.heic',
        'face-p3-10bit.heic',
        'face-rotated-10bit.heic',
        'face-mirrored-10bit.heic',
        ...List.generate(
          40,
          (i) => 'batch-${i.toString().padLeft(2, '0')}.heic',
        ),
      ].map((s) => '$path$s').toList();
      c.addPhotos([
        ...positives,
        '${path}blank.heic',
        '${path}broken.heic',
        '${path}negative-0.jpg',
        '${path}negative-1.jpg',
      ]);
      expect(c.photos.length, 50);
      c.navigate(StepPage.albums);
      await settlePhotos();
      await binding.takeScreenshot('flutter-albums');
      await tester.scrollUntilVisible(find.text('Tu primer escaneo'), 250);
      await tester.pumpAndSettle();
      await binding.takeScreenshot('flutter-scan-note');
      final roundMs = <int>[];
      for (var round = 0; round < 2; round++) {
        final elapsed = Stopwatch()..start();
        await tester.runAsync(c.search);
        final until = DateTime.now().add(const Duration(minutes: 3));
        while (c.busy && DateTime.now().isBefore(until)) {
          await tester.pump(const Duration(milliseconds: 100));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
        }
        expect(c.busy, isFalse);
        expect(c.processed, 50);
        expect(c.skipped, 1);
        expect(c.results, positives);
        expect(
          c.reviews.singleWhere((r) => r.id.endsWith('blank.heic')).outcome,
          'noFace',
        );
        expect(c.results.any((id) => id.contains('negative')), isFalse);
        roundMs.add(elapsed.elapsedMilliseconds);
      }
      binding.reportData = {
        ...?binding.reportData,
        'platform': Platform.operatingSystem,
        'inputs': 50,
        'accepted': 46,
        'unreadable': 1,
        'roundMs': roundMs,
      };
      await tester.pumpAndSettle();
      final tile = find.byKey(ValueKey('result-preview:${positives.first}'));
      await tester.scrollUntilVisible(tile, 250);
      final thumbnail = find.descendant(of: tile, matching: find.byType(Image));
      for (var i = 0; i < 100 && thumbnail.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
      }
      expect(thumbnail, findsOneWidget);
      c.toggleAll();
      expect(c.selected.length, 46);
      await tester.pumpAndSettle();
      for (
        var i = 0;
        i < 60 && find.text('Cargando foto…').evaluate().isNotEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
      }
      await binding.takeScreenshot('flutter-heic-results');
      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(find.text('Revisar fotografía'), findsOneWidget);
      final until = DateTime.now().add(const Duration(seconds: 30));
      while (find.byType(Image).evaluate().isEmpty &&
          DateTime.now().isBefore(until)) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
      }
      expect(find.byType(Image), findsWidgets);
      await binding.takeScreenshot('flutter-heic-preview');
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.runAsync(() => c.useReference('${path}blank.heic'));
      expect(c.reference!.faces, isEmpty);
      await tester.pumpAndSettle();
      await binding.takeScreenshot('flutter-no-face');
      await tester.runAsync(c.clear);
      await tester.pumpAndSettle();
      await binding.takeScreenshot('flutter-home');
      tester.view.physicalSize = const Size(960, 1440);
      tester.view.devicePixelRatio = 3;
      tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await binding.takeScreenshot('flutter-large-text-home');
      tester.binding.platformDispatcher.clearTextScaleFactorTestValue();
      tester.binding.platformDispatcher.platformBrightnessTestValue =
          Brightness.dark;
      await tester.pumpAndSettle();
      await binding.takeScreenshot('flutter-dark-home');
      tester.binding.platformDispatcher.clearPlatformBrightnessTestValue();
      tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
}

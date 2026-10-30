import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personas_flutter/app_theme.dart';
import 'package:personas_flutter/ui_components.dart';

void main() {
  test(
    'remaining estimate waits for samples and follows measured throughput',
    () {
      expect(estimateScanRemaining(2, 98, const Duration(seconds: 5)), isNull);
      expect(
        estimateScanRemaining(5, 95, const Duration(milliseconds: 500)),
        isNull,
      );
      expect(
        estimateScanRemaining(10, 90, const Duration(seconds: 20)),
        const Duration(minutes: 3),
      );
      expect(
        estimateScanRemaining(20, 80, const Duration(seconds: 20)),
        const Duration(seconds: 80),
      );
      expect(
        estimateScanRemaining(10, 0, const Duration(seconds: 20)),
        Duration.zero,
      );
    },
  );

  testWidgets('scan card shows calibration beneath the progress bar', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: ScanProgress(processed: 0, total: 100))),
    );
    final estimate = find.text('Calculando tiempo estimado…');
    expect(estimate, findsOneWidget);
    expect(
      tester.getTopLeft(estimate).dy,
      greaterThan(
        tester.getBottomLeft(find.byType(LinearProgressIndicator)).dy,
      ),
    );
  });

  testWidgets(
    'scroll cue advances, hides at the end and returns when scrolling up',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: personasTheme(Brightness.light),
          home: const Scaffold(
            body: HalladinScrollView(
              slivers: [SliverToBoxAdapter(child: SizedBox(height: 1800))],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final cue = find.byTooltip('Ver más abajo');
      double opacity() => tester
          .widget<AnimatedOpacity>(
            find
                .ancestor(of: cue, matching: find.byType(AnimatedOpacity))
                .first,
          )
          .opacity;
      expect(opacity(), .65);
      final viewport = tester.getRect(find.byType(CustomScrollView));
      expect(tester.getRect(cue).right, closeTo(viewport.right - 16, 1));
      expect(tester.getCenter(cue).dy, closeTo(viewport.center.dy, 1));
      final gesture = await tester.startGesture(
        viewport.center + const Offset(100, 0),
      );
      await gesture.moveBy(const Offset(0, -120));
      await tester.pump();
      expect(opacity(), 0);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(opacity(), .65);

      final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
      final beforeTap = scroll.position.pixels;
      await tester.tap(cue);
      await tester.pump(const Duration(milliseconds: 60));
      expect(opacity(), 0);
      await tester.pumpAndSettle();
      expect(scroll.position.pixels, greaterThan(beforeTap));
      scroll.position.jumpTo(scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(opacity(), 0);
      scroll.position.jumpTo(0);
      await tester.pumpAndSettle();
      expect(opacity(), .65);
    },
  );

  testWidgets('fitting content has no scroll cue', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HalladinScrollView(
            slivers: [SliverToBoxAdapter(child: SizedBox(height: 100))],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Ver más abajo').hitTestable(), findsNothing);
  });
}

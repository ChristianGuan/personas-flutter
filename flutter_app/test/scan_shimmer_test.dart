import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personas_flutter/ui_components.dart';

void main() {
  for (final reduced in [false, true]) {
    testWidgets('scan note has periodic glint, reduced motion: $reduced', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduced),
            child: const Scaffold(body: ScanSpeedShimmer()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(ScanSpeedShimmer.message), findsOneWidget);
      expect(tester.binding.hasScheduledFrame, false);
      await tester.pump(const Duration(seconds: 7));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.binding.hasScheduledFrame, !reduced);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, false);
      expect(find.text(ScanSpeedShimmer.message), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 8));
      expect(tester.takeException(), isNull);
    });
  }
}

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart' hide SearchController;
import 'package:flutter_test/flutter_test.dart';
import 'package:personas_flutter/main.dart';
import 'package:personas_flutter/photo_widgets.dart';
import 'package:personas_flutter/search_controller.dart';
import 'search_controller_test.dart' show TestBridge;

void main() {
  test('thumbnail cache evicts by recency, byte budget and entry count', () {
    final cache = ThumbnailCache(maxBytes: 6, maxEntries: 2);
    final a = Uint8List(3), b = Uint8List(3), c = Uint8List(3);
    cache.put('a', a);
    cache.put('b', b);
    expect(cache.get('a'), same(a));
    cache.put('c', c);
    expect(cache.get('b'), isNull);
    expect(cache.get('a'), same(a));
    cache.put('oversized', Uint8List(7));
    expect(cache.get('oversized'), isNull);
    expect(cache.get('c'), same(c));
    final countCache = ThumbnailCache(maxBytes: 100, maxEntries: 1);
    countCache.put('a', a);
    countCache.put('b', b);
    expect(countCache.get('a'), isNull);
  });

  testWidgets('1000 results load only nearby thumbnails and reuse them on return', (
    tester,
  ) async {
    final bridge = TestBridge();
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
    );
    bridge.handlers['image'] = (_) async => png;
    final c = SearchController(bridge)..page = StepPage.results;
    c.reviews.addAll(
      List.generate(1000, (i) => Review('photo-$i', 'match', 'key-$i')),
    );
    await tester.pumpWidget(PersonasApp(controller: c));
    await tester.pumpAndSettle();
    if (find.byTooltip('Cerrar acciones').evaluate().isNotEmpty) {
      await tester.tap(find.byTooltip('Cerrar acciones'));
      await tester.pumpAndSettle();
    }
    int requests() => bridge.calls.where((call) => call.$1 == 'image').length;
    final initial = requests();
    expect(initial, greaterThan(0));
    expect(initial, lessThan(30));
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    position.jumpTo(600);
    await tester.pumpAndSettle();
    final afterDown = requests();
    expect(afterDown, greaterThan(initial));
    expect(afterDown, lessThan(60));
    position.jumpTo(0);
    await tester.pumpAndSettle();
    expect(requests(), afterDown);
    // Clearing the session cache makes a later revisit fetch fresh data.
    clearThumbnailCache(bridge);
    position.jumpTo(600);
    await tester.pumpAndSettle();
    expect(requests(), greaterThan(afterDown));
    expect(tester.takeException(), isNull);
    // Report actual bridge requests, not inferred frame-rate improvements.
    // ignore: avoid_print
    print(
      '1000 photos: initial=$initial, after scroll=$afterDown, return=0 extra requests',
    );
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    await bridge.stream.close();
  });
}

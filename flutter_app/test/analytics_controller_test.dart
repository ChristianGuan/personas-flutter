import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:personas_flutter/analytics/event.dart';
import 'package:personas_flutter/search_controller.dart';
import 'search_controller_test.dart' as helpers;

class Sink implements AnalyticsSink {
  @override
  bool enabled = true;
  final events = <(String, Payload)>[];
  @override
  void record(String type, [Payload payload = const {}]) {
    if (enabled) events.add((type, payload));
  }
}

void main() {
  test('cancelled native completion emits one cancellation event', () async {
    final bridge = helpers.TestBridge();
    final sink = Sink();
    final c = SearchController(bridge, analytics: sink);
    try {
      await c.initialize();
      bridge.handlers['reference'] = (a) async => helpers.reference(a!['id']);
      await c.useReference('ref');
      c.addPhotos(['a', 'b']);
      await c.search();
      final run = bridge.calls.lastWhere((call) => call.$1 == 'search').$2!['runId'];
      bridge.event({'type': 'photo', 'runId': run, 'id': 'a', 'outcome': 'match'});
      await c.cancel();
      expect(sink.events.where((e) => e.$1 == 'search_cancelled'), isEmpty);
      bridge.event({'type': 'done', 'runId': run, 'cancelled': true, 'diagnostics': {'readMs': 1, 'decodeMs': 2, 'engineMs': 3, 'cacheHits': 0, 'cacheMisses': 1}});
      bridge.event({'type': 'done', 'runId': run, 'cancelled': true});
      final event = sink.events.where((e) => e.$1 == 'search_cancelled').single;
      expect(event.$2['readMs'], 1);
      expect(event.$2['cacheMisses'], 1);
      expect(event.$2['cancelLatencyMs'], isA<int>());
      expect(event.$2['timeToCancelMs'], isA<int>());
      expect(event.$2['photosProcessed'], 1);
      expect(event.$2['photosPlanned'], 2);
      expect(validPayload(event.$1, {...event.$2, 'sessionId': randomUuid()}, schemaVersion: 2), true);
      expect(sink.events.where((e) => e.$1 == 'search_completed'), isEmpty);
    } finally {
      c.dispose();
      await bridge.stream.close();
    }
  });
  test(
    'controller emits only allowed metrics, once, with optional rating and totals',
    () async {
      final bridge = helpers.TestBridge();
      final sink = Sink();
      final c = SearchController(bridge, analytics: sink);
      try {
        await c.initialize();
        bridge.handlers['reference'] = (a) async => helpers.reference(a!['id']);
        await c.useReference('private-reference');
        c.addPhotos(['private-photo']);
        await c.search();
        final run = bridge.calls
            .lastWhere((call) => call.$1 == 'search')
            .$2!['runId'];
        bridge.event({
          'type': 'photo',
          'runId': run,
          'id': 'private-photo',
          'outcome': 'match',
          'key': 'private-hash',
        });
        bridge.event({'type': 'done', 'runId': run, 'cancelled': false});
        bridge.event({'type': 'done', 'runId': run, 'cancelled': false});
        expect(sink.events.where((e) => e.$1 == 'search_completed').length, 1);
        c.rateResults(null);
        expect(sink.events.any((e) => e.$1 == 'results_rated'), false);
        c.confirm('private-photo', true);
        c.sendReviewTotals();
        c.sendReviewTotals();
        expect(sink.events.where((e) => e.$1 == 'results_reviewed').single.$2, {
          'searchId': sink.events.first.$2['searchId'],
          'confirmed': 1,
          'rejected': 0,
        });
        expect(
          jsonEncode(sink.events.map((e) => e.$2).toList()).contains('private'),
          false,
        );
        for (final event in sink.events) {
          expect(
            validPayload(event.$1, {
              ...event.$2,
              'sessionId': randomUuid(),
            }, schemaVersion: 2),
            true,
          );
        }
        await c.search();
        bridge.event({'type': 'done', 'runId': run + 1, 'cancelled': false});
        c.rateResults(5);
        c.rateResults(1);
        expect(sink.events.where((e) => e.$1 == 'results_rated').single.$2, {
          'searchId': sink.events
              .where((e) => e.$1 == 'search_started')
              .last
              .$2['searchId'],
          'stars': 5,
        });
      } finally {
        c.dispose();
        await bridge.stream.close();
      }
    },
  );
}

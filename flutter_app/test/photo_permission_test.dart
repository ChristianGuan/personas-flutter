import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:personas_flutter/search_controller.dart';
import 'search_controller_test.dart' show TestBridge, reference;

void main() {
  for (final access in ['full', 'none', 'limited']) {
    test(
      'first album visit automatically requests access, response: $access',
      () async {
        final bridge = TestBridge();
        bridge.handlers['initialize'] = (_) async => {
          'platform': 'android',
          'access': 'none',
          'photoAccessAsked': false,
        };
        bridge.handlers['reference'] = (_) async => reference('ref');
        final response = Completer<Map<String, dynamic>>();
        bridge.handlers['requestAccess'] = (_) => response.future;
        bridge.handlers['albums'] = (_) async => {
          'access': access,
          'albums': [],
        };
        final c = SearchController(bridge);
        await c.initialize();
        await c.useReference('ref');
        c.navigate(StepPage.albums);
        await Future<void>.delayed(Duration.zero);
        expect(
          bridge.calls.where((call) => call.$1 == 'requestAccess'),
          hasLength(1),
        );
        await c.refreshAlbums();
        expect(
          bridge.calls.where((call) => call.$1 == 'requestAccess'),
          hasLength(1),
        );
        response.complete({'access': access, 'albums': []});
        await Future<void>.delayed(Duration.zero);
        expect(c.access, access);
        expect(c.loadingAlbums, false);
        c.navigate(StepPage.reference);
        c.navigate(StepPage.albums);
        await Future<void>.delayed(Duration.zero);
        expect(
          bridge.calls.where((call) => call.$1 == 'requestAccess'),
          hasLength(1),
        );
        c.dispose();
        await bridge.stream.close();
      },
    );
  }
  test(
    'previous denial is not requested automatically after relaunch',
    () async {
      final bridge = TestBridge();
      bridge.handlers['initialize'] = (_) async => {
        'platform': 'android',
        'access': 'none',
        'photoAccessAsked': true,
      };
      bridge.handlers['reference'] = (_) async => reference('ref');
      bridge.handlers['albums'] = (_) async => {'access': 'none', 'albums': []};
      final c = SearchController(bridge);
      await c.initialize();
      await c.useReference('ref');
      c.navigate(StepPage.albums);
      await Future<void>.delayed(Duration.zero);
      expect(bridge.calls.where((call) => call.$1 == 'requestAccess'), isEmpty);
      c.dispose();
      await bridge.stream.close();
    },
  );
}

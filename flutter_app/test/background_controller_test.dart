import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:personas_flutter/native_bridge.dart';
import 'package:personas_flutter/search_controller.dart';
import 'search_controller_test.dart' show TestBridge, reference;

Json photo(String id, String outcome, {String? key}) => {
  'type': 'photo',
  'runId': 7,
  'id': id,
  'outcome': outcome,
  'key': key,
};
Json snapshot({
  bool active = false,
  bool available = true,
  List<Json>? events,
  Json? done,
  Json? context,
}) => {
  'runId': 7,
  'active': active,
  'referencesAvailable': available,
  'backgroundMode': 'androidService',
  'context':
      context ??
      {
        'runId': 7,
        'photos': ['a', 'b', 'bad'],
        'reference': reference('person'),
        'chosen': (reference('person')['faces'] as List).first,
        'examples': [],
        'feedback': <String, bool>{},
        'selected': <String>[],
      },
  'events': events ?? [photo('a', 'match', key: 'ka')],
  if (!active || done != null)
    'done': done ?? {'type': 'done', 'runId': 7, 'cancelled': false},
};

void main() {
  late TestBridge bridge;
  late SearchController controller;
  Json initialize([Json? search]) => {
    'platform': 'android',
    'access': 'none',
    'incoming': [],
    'backgroundMode': 'androidService',
    'notifications': {'enabled': true, 'asked': true, 'canAsk': false},
    if (search != null) 'search': search,
  };
  setUp(() {
    bridge = TestBridge();
    bridge.handlers['initialize'] = (_) async => initialize();
    bridge.handlers['reference'] = (a) async => reference(a!['id']);
    controller = SearchController(bridge);
  });
  tearDown(() async {
    controller.dispose();
    await bridge.stream.close();
  });

  test(
    'cold recovery keeps completed results and preview without reusing expired face handles',
    () async {
      bridge.handlers['initialize'] = (_) async =>
          initialize(snapshot(available: false));
      await controller.initialize();
      expect(controller.page, StepPage.results);
      expect(controller.results, ['a']);
      expect(controller.searchReference!.image, 'person');
      expect(controller.reference, isNull);
      expect(controller.chosen, isNull);
      expect(controller.canSearch, isFalse);
      expect(controller.message, contains('elige de nuevo'));
      controller.toggle('a');
      await controller.share();
      expect(bridge.calls.last.$1, 'share');
      expect(bridge.calls.last.$2!['ids'], ['a']);
    },
  );

  test(
    'resume reconciles missed and duplicate events, errors, feedback and completion exactly once',
    () async {
      final initial = snapshot(active: true);
      (initial['context'] as Json)['feedback'] = {'kb': false};
      bridge.handlers['initialize'] = (_) async => initialize(initial);
      await controller.initialize();
      expect(controller.busy, isTrue);
      expect(controller.processed, 1);
      bridge.handlers['searchSnapshot'] = (_) async => snapshot(
        events: [
          photo('a', 'match', key: 'ka'),
          photo('b', 'match', key: 'kb'),
          photo('bad', 'unreadable'),
        ],
      );
      await controller.resume();
      await controller.resume();
      expect(controller.busy, isFalse);
      expect(controller.processed, 3);
      expect(controller.reviews.length, 3);
      expect(controller.results, ['a']);
      expect(controller.reviews[1].outcome, 'rejected');
      expect(controller.skipped, 1);
      await controller.search();
      expect(bridge.calls.lastWhere((c) => c.$1 == 'search').$2!['runId'], 8);
    },
  );

  test(
    'completion arriving during initialization is replayed after restoring its scope',
    () async {
      final initializing = Completer<Json>();
      bridge.handlers['initialize'] = (_) => initializing.future;
      final ready = controller.initialize();
      bridge.event(photo('a', 'match', key: 'ka'));
      bridge.event({'type': 'done', 'runId': 7, 'cancelled': false});
      initializing.complete(initialize(snapshot(active: true, events: [])));
      await ready;
      expect(controller.page, StepPage.results);
      expect(controller.busy, isFalse);
      expect(controller.results, ['a']);
    },
  );

  test(
    'denied notifications do not prevent analysis or trigger repeated permission prompts',
    () async {
      await controller.initialize();
      controller.notificationsEnabled = false;
      controller.notificationsAsked = false;
      controller.canAskNotifications = true;
      bridge.handlers['requestNotifications'] = (_) async => {
        'enabled': false,
        'asked': true,
        'canAsk': false,
      };
      await controller.useReference('person');
      controller.addPhotos(['a']);
      await controller.search();
      final first = bridge.calls
          .lastWhere((c) => c.$1 == 'search')
          .$2!['runId'];
      bridge.event({'type': 'done', 'runId': first, 'cancelled': false});
      await controller.search();
      expect(
        bridge.calls.where((c) => c.$1 == 'requestNotifications').length,
        1,
      );
      expect(bridge.calls.where((c) => c.$1 == 'search').length, 2);
      expect(controller.notificationsEnabled, isFalse);
      await controller.requestNotifications();
      expect(bridge.calls.last.$1, 'notificationSettings');
    },
  );

  test(
    'cancelling while notification permission is pending never starts a native job',
    () async {
      await controller.initialize();
      controller.notificationsEnabled = false;
      controller.notificationsAsked = false;
      final permission = Completer<Json>();
      bridge.handlers['requestNotifications'] = (_) => permission.future;
      await controller.useReference('person');
      controller.addPhotos(['a']);
      final searching = controller.search();
      expect(controller.busy, isTrue);
      await controller.cancel();
      permission.complete({'enabled': true, 'asked': true, 'canAsk': false});
      await searching;
      expect(controller.cancelled, isTrue);
      expect(controller.busy, isFalse);
      expect(bridge.calls.any((c) => c.$1 == 'search'), isFalse);
    },
  );

  test(
    'an older notification cannot replace the person while permission is pending',
    () async {
      await controller.initialize();
      controller.notificationsEnabled = false;
      controller.notificationsAsked = false;
      final permission = Completer<Json>();
      bridge.handlers['requestNotifications'] = (_) => permission.future;
      bridge.handlers['searchSnapshot'] = (_) async => snapshot();
      await controller.useReference('new-person');
      controller.addPhotos(['new-photo']);
      final searching = controller.search();
      bridge.event({'type': 'openAnalysis'});
      await Future<void>.delayed(Duration.zero);
      expect(controller.reference!.image, 'new-person');
      expect(controller.photos, ['new-photo']);
      permission.complete({'enabled': true, 'asked': true, 'canAsk': false});
      await searching;
      final args = bridge.calls.lastWhere((c) => c.$1 == 'search').$2!;
      expect(args['ids'], ['new-photo']);
      expect((args['context'] as Map)['reference']['image'], 'new-person');
    },
  );

  test(
    'late initialization cannot replace a pending reference preparation',
    () async {
      final initial = Completer<Json>();
      bridge.handlers['initialize'] = (_) => initial.future;
      final initializing = controller.initialize();
      final pending = Completer<Json>();
      bridge.handlers['reference'] = (_) => pending.future;
      final preparing = controller.useReference('new-person');
      initial.complete(initialize(snapshot()));
      await initializing;
      expect(controller.page, StepPage.reference);
      expect(controller.busy, isTrue);
      pending.complete(reference('new-person'));
      await preparing;
      expect(controller.reference!.image, 'new-person');
      expect(controller.blocked, isFalse);
    },
  );
  test(
    'an older notification cannot replace a pending reference preparation',
    () async {
      await controller.initialize();
      final pending = Completer<Json>();
      bridge.handlers['reference'] = (_) => pending.future;
      bridge.handlers['searchSnapshot'] = (_) async => snapshot();
      final preparing = controller.useReference('new-person');
      bridge.event({'type': 'openAnalysis'});
      await Future<void>.delayed(Duration.zero);
      expect(controller.page, StepPage.reference);
      expect(controller.busy, isTrue);
      expect(bridge.calls.any((call) => call.$1 == 'searchSnapshot'), isFalse);
      pending.complete(reference('new-person'));
      await preparing;
      expect(controller.reference!.image, 'new-person');
      expect(controller.blocked, isFalse);
    },
  );

  test(
    'opening a notification with an evicted cache offers a new search',
    () async {
      await controller.initialize();
      bridge.handlers['searchSnapshot'] = (_) async => null;
      await controller.resume(openResults: true);
      expect(controller.page, StepPage.home);
      expect(controller.message, contains('Inicia una nueva búsqueda'));
      expect(controller.busy, isFalse);
    },
  );

  test(
    'system interruption restores partial results and never masquerades as completion',
    () async {
      bridge.handlers['initialize'] = (_) async => initialize(
        snapshot(
          available: false,
          done: {
            'type': 'done',
            'runId': 7,
            'cancelled': true,
            'error': 'Android interrumpió el análisis.',
          },
        ),
      );
      await controller.initialize();
      expect(controller.cancelled, isTrue);
      expect(controller.processed, 1);
      expect(controller.photos.length, 3);
      expect(controller.message, contains('interrumpió'));
      expect(controller.results, ['a']);
    },
  );

  test(
    'clearing a session while a resume snapshot is pending cannot resurrect it',
    () async {
      await controller.initialize();
      final pending = Completer<Json>();
      bridge.handlers['searchSnapshot'] = (_) => pending.future;
      final resuming = controller.resume(openResults: true);
      await controller.clear();
      pending.complete(snapshot());
      await resuming;
      expect(controller.page, StepPage.home);
      expect(controller.photos, isEmpty);
      expect(controller.results, isEmpty);
    },
  );

  test(
    'new search rejects a pending snapshot of the previous results',
    () async {
      await controller.initialize();
      final pending = Completer<Json>();
      bridge.handlers['searchSnapshot'] = (_) => pending.future;
      final resuming = controller.resume(openResults: true);
      await controller.newSearch();
      pending.complete(snapshot());
      await resuming;
      expect(controller.page, StepPage.reference);
      expect(controller.reference, isNull);
      expect(controller.photos, isEmpty);
      expect(controller.results, isEmpty);
    },
  );

  test(
    'notification action opens the native result and retained selection excludes rejected photos',
    () async {
      await controller.initialize();
      final restored = snapshot(
        events: [
          photo('a', 'match', key: 'ka'),
          photo('b', 'match', key: 'kb'),
          photo('bad', 'unreadable'),
        ],
      );
      (restored['context'] as Json)['selected'] = ['a', 'b', 'bad'];
      (restored['context'] as Json)['feedback'] = {'kb': false};
      bridge.handlers['searchSnapshot'] = (_) async => restored;
      bridge.event({'type': 'openAnalysis'});
      await Future<void>.delayed(Duration.zero);
      expect(controller.page, StepPage.results);
      expect(controller.selected, {'a'});
      controller.confirm('b', true);
      await Future<void>.delayed(Duration.zero);
      final context = bridge.calls.lastWhere((c) => c.$1 == 'updateSearch').$2!;
      expect((context['feedback'] as Map)['kb'], true);
      expect(context.keys, isNot(contains('embeddings')));
    },
  );
}

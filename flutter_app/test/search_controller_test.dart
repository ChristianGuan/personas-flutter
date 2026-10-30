import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personas_flutter/native_bridge.dart';
import 'package:personas_flutter/search_controller.dart';

class TestBridge implements PhotoBridge {
  final stream = StreamController<Json>.broadcast(sync: true);
  final calls = <(String, Json?)>[];
  final handlers = <String, Future<dynamic> Function(Json?)>{};
  @override
  Stream<Json> get events => stream.stream;
  @override
  Future<T?> call<T>(String method, [Json? arguments]) async {
    calls.add((method, arguments));
    dynamic result;
    if (handlers.containsKey(method)) {
      result = await handlers[method]!(arguments);
    } else if (method == 'initialize') {
      result = {'platform': 'android', 'access': 'none', 'incoming': []};
    }
    return result as T?;
  }

  void event(Json value) => stream.add(value);
}

Json reference(String token, {int count = 1}) => {
  'token': token,
  'image': token,
  'width': 1000,
  'height': 800,
  'faces': List.generate(
    count,
    (i) => {'id': '$token:$i', 'x': .1, 'y': .1, 'width': .3, 'height': .4},
  ),
};

void main() {
  late TestBridge bridge;
  late SearchController controller;
  setUp(() async {
    bridge = TestBridge();
    controller = SearchController(bridge);
    await controller.initialize();
    bridge.handlers['reference'] = (a) async => reference(a!['id']);
  });
  tearDown(() async {
    controller.dispose();
    await bridge.stream.close();
  });
  void photo(String id, String outcome, {String? key, int? run}) {
    final current = bridge.calls
        .lastWhere((c) => c.$1 == 'search')
        .$2!['runId'];
    bridge.event({
      'type': 'photo',
      'runId': run ?? current,
      'id': id,
      'outcome': outcome,
      'key': key,
    });
  }

  void done() {
    final run = bridge.calls.lastWhere((c) => c.$1 == 'search').$2!['runId'];
    bridge.event({'type': 'done', 'runId': run, 'cancelled': false});
  }

  test(
    'new search prevents duplicate clearing and preserves results on native failure',
    () async {
      await controller.useReference('person');
      controller.addPhotos(['photo']);
      controller.page = StepPage.results;
      controller.reviews.add(const Review('photo', 'match', 'key'));
      controller.selected.add('photo');
      final clearing = Completer<void>();
      bridge.handlers['clear'] = (_) => clearing.future;
      final starting = controller.newSearch();
      await controller.newSearch();
      expect(controller.blocked, isTrue);
      expect(bridge.calls.where((call) => call.$1 == 'clear').length, 1);
      clearing.completeError(
        PlatformException(
          code: 'clear_failed',
          message: 'No se pudo preparar la búsqueda.',
        ),
      );
      await starting;
      expect(controller.blocked, isFalse);
      expect(controller.page, StepPage.results);
      expect(controller.reference?.token, 'person');
      expect(controller.photos, ['photo']);
      expect(controller.selected, {'photo'});
      expect(controller.results, ['photo']);
      expect(controller.message, contains('No se pudo preparar'));
    },
  );

  test('old reference cleanup cannot keep a new reference loading', () async {
    controller.platform = 'ios';
    await controller.useReference('first');
    final releasing = Completer<void>();
    bridge.handlers['releaseReference'] = (_) => releasing.future;
    final loading = controller.useReference('next');
    await Future<void>.delayed(Duration.zero);
    expect(controller.reference!.image, 'next');
    expect(controller.blocked, isFalse);
    expect(controller.canCancelPreparation, isFalse);
    releasing.complete();
    await loading;
  });
  test(
    'iOS reference cancellation preserves the person and fences late replies',
    () async {
      controller.platform = 'ios';
      await controller.useReference('first');
      controller.addPhotos(['existing']);
      final old = controller.reference;
      final stalled = Completer<Json>();
      bridge.handlers['reference'] = (_) => stalled.future;
      final firstLoad = controller.useReference('stalled');
      expect(controller.canCancelPreparation, isTrue);
      final request = bridge.calls.last.$2!['requestId'];
      controller.cancelPreparation();
      expect(controller.blocked, isFalse);
      expect(controller.reference, same(old));
      expect(controller.photos, ['existing']);
      expect(bridge.calls.last.$1, 'cancelPreparation');
      expect(bridge.calls.last.$2, {'requestId': request});

      final retry = Completer<Json>();
      bridge.handlers['reference'] = (_) => retry.future;
      final secondLoad = controller.useReference('retry');
      stalled.complete(reference('stale'));
      await firstLoad;
      expect(controller.busy, isTrue);
      expect(controller.reference, same(old));
      expect(bridge.calls.last.$1, 'releaseReference');
      expect(bridge.calls.last.$2, {'token': 'stale'});
      retry.complete(reference('retry'));
      await secondLoad;
      expect(controller.reference!.image, 'retry');
      expect(controller.blocked, isFalse);
      expect(controller.canCancelPreparation, isFalse);
      expect(controller.photos, ['existing']);
    },
  );
  for (final fail in [false, true]) {
    test(
      'cancelled iOS picker ignores late completion (error=$fail)',
      () async {
        controller.platform = 'ios';
        await controller.useReference('person');
        controller.addPhotos(['existing']);
        final pending = Completer<List<String>>();
        bridge.handlers['pick'] = (_) => pending.future;
        final picking = controller.pickPhotos();
        controller.cancelPreparation();
        final retry = Completer<Json>();
        bridge.handlers['reference'] = (_) => retry.future;
        final loading = controller.useReference('new');
        if (fail) {
          pending.completeError(
            PlatformException(code: 'cancelled', message: 'stale error'),
          );
        } else {
          pending.complete(['stale-photo']);
        }
        await picking;
        expect(controller.photos, ['existing']);
        expect(controller.busy, isTrue);
        expect(controller.message, 'Abriendo tu foto y buscando rostros…');
        retry.complete(reference('new'));
        await loading;
        expect(controller.reference!.image, 'new');
        expect(controller.blocked, isFalse);
      },
    );
  }
  test(
    'iOS preparation failure unlocks the previous reference and allows retry',
    () async {
      controller.platform = 'ios';
      await controller.useReference('first');
      controller.addPhotos(['existing']);
      final old = controller.reference;
      bridge.handlers['reference'] = (_) async => throw PlatformException(
        code: 'photo_error',
        message: 'La foto tardó demasiado en prepararse.',
      );
      await controller.useReference('stalled');
      expect(controller.reference, same(old));
      expect(controller.blocked, isFalse);
      expect(controller.canCancelPreparation, isFalse);
      expect(controller.canSearch, isTrue);
      expect(controller.message, contains('tardó demasiado'));
      bridge.handlers['reference'] = (_) async => reference('retry');
      await controller.useReference('retry');
      expect(controller.reference!.image, 'retry');
    },
  );

  test(
    'selection accumulates more than thirty without duplicate IDs; cancelled picker preserves scope',
    () async {
      controller.addPhotos(List.generate(45, (i) => 'p$i'));
      controller.addPhotos(['p0', 'p44', 'p45']);
      expect(controller.photos.length, 46);
      bridge.handlers['pick'] = (_) async => [];
      await controller.pickPhotos();
      expect(controller.photos.length, 46);
    },
  );
  test(
    'a pending cloud selection cannot race a search or clear the existing scope',
    () async {
      await controller.useReference('person');
      controller.addPhotos(['existing']);
      final pending = Completer<List<String>>();
      bridge.handlers['pick'] = (_) => pending.future;
      final choosing = controller.pickPhotos();
      expect(controller.picking, isTrue);
      expect(controller.canSearch, isFalse);
      controller.navigate(StepPage.albums);
      controller.back();
      expect(controller.page, StepPage.reference);
      await controller.search();
      await controller.clear();
      expect(
        bridge.calls.any((c) => c.$1 == 'search' || c.$1 == 'clear'),
        isFalse,
      );
      expect(controller.photos, ['existing']);
      pending.complete(['new', 'existing']);
      await choosing;
      expect(controller.picking, isFalse);
      expect(controller.canSearch, isTrue);
      expect(controller.photos, ['existing', 'new']);
    },
  );
  test(
    'failed and faceless additional references preserve the valid reference and scope',
    () async {
      await controller.useReference('first');
      controller.addPhotos(['a']);
      final old = controller.reference;
      bridge.handlers['reference'] = (_) async => throw PlatformException(
        code: 'decode',
        message: 'No pudimos leer esta imagen.',
      );
      await controller.useReference('broken', append: true);
      expect(controller.reference, same(old));
      expect(controller.photos, ['a']);
      expect(controller.chosen, isNotNull);
      bridge.handlers['reference'] = (_) async => reference('blank', count: 0);
      await controller.useReference('blank', append: true);
      expect(controller.reference, same(old));
      expect(controller.examples, isEmpty);
      expect(
        bridge.calls.where((c) => c.$1 == 'releaseReference').last.$2!['token'],
        'blank',
      );
    },
  );
  test(
    'all nine detected faces can be chosen, including fourth and ninth',
    () async {
      bridge.handlers['reference'] = (_) async => reference('group', count: 9);
      await controller.useReference('group');
      expect(controller.chosen, isNull);
      controller.choose(controller.reference!.faces[3]);
      expect(controller.chosen!.id, 'group:3');
      controller.choose(controller.reference!.faces[8]);
      expect(controller.chosen!.id, 'group:8');
    },
  );
  test(
    'review never enters selection or share until explicit confirmation; rejection survives repeat',
    () async {
      await controller.useReference('person');
      controller.addPhotos(['match', 'other']);
      await controller.search();
      photo('match', 'match', key: 'one');
      photo('other', 'review', key: 'two');
      done();
      controller.toggle('other');
      controller.toggleAll();
      await controller.share();
      expect(bridge.calls.last.$2!['ids'], ['match']);
      controller.confirm('other', true);
      controller.toggle('other');
      expect(controller.selected, contains('other'));
      controller.confirm('other', false);
      expect(controller.selected, isNot(contains('other')));
      await controller.search();
      photo('other', 'match', key: 'two');
      done();
      expect(controller.results, isEmpty);
      expect(controller.reviews.single.outcome, 'rejected');
    },
  );
  test('a changed content key is not rejected by an old decision', () async {
    await controller.useReference('person');
    controller.addPhotos(['photo']);
    await controller.search();
    photo('photo', 'review', key: 'old');
    done();
    controller.confirm('photo', false);
    await controller.search();
    photo('photo', 'match', key: 'edited');
    done();
    expect(controller.results, ['photo']);
  });
  test('unreadable files stay errors and cannot be confirmed', () async {
    await controller.useReference('person');
    controller.addPhotos(['broken']);
    await controller.search();
    photo('broken', 'unreadable');
    done();
    controller.confirm('broken', true);
    expect(controller.skipped, 1);
    expect(controller.results, isEmpty);
    expect(controller.reviews.single.outcome, 'unreadable');
  });
  test(
    'duplicate and obsolete progress cannot alter a current search',
    () async {
      await controller.useReference('person');
      controller.addPhotos(['a']);
      await controller.search();
      photo('outside', 'match');
      photo('a', 'match', run: -1);
      expect(controller.processed, 0);
      photo('a', 'match');
      photo('a', 'none');
      expect(controller.processed, 1);
      expect(controller.results, ['a']);
      done();
    },
  );
  test(
    'cancellation waits for native completion and retains partial results',
    () async {
      await controller.useReference('person');
      controller.addPhotos(['a', 'b']);
      await controller.search();
      photo('a', 'match');
      await controller.cancel();
      expect(controller.busy, isTrue);
      final run = bridge.calls.firstWhere((c) => c.$1 == 'search').$2!['runId'];
      bridge.event({'type': 'done', 'runId': run, 'cancelled': true});
      expect(controller.busy, isFalse);
      expect(controller.cancelled, isTrue);
      expect(controller.results, ['a']);
    },
  );
  test(
    'revoked album access removes the inaccessible scope and old results',
    () async {
      await controller.useReference('person');
      bridge.handlers['albums'] = (_) async => {
        'access': 'full',
        'albums': [
          {'id': 'album', 'name': 'Familia', 'cover': 'a', 'count': 1},
        ],
      };
      bridge.handlers['albumPhotos'] = (_) async => ['a'];
      controller.navigate(StepPage.albums);
      await Future<void>.delayed(Duration.zero);
      await controller.selectAlbum(controller.albums.single);
      expect(controller.photos, ['a']);
      await controller.search();
      photo('a', 'match');
      done();
      controller.toggleAll();
      expect(controller.page, StepPage.results);
      expect(controller.selected, ['a']);
      bridge.handlers['albums'] = (_) async => {'access': 'none', 'albums': []};
      await controller.refreshAlbums();
      expect(controller.album, isNull);
      expect(controller.photos, isEmpty);
      expect(controller.results, isEmpty);
      expect(controller.selected, isEmpty);
    },
  );
  test('a shared photo arriving during initialization is retained', () async {
    final source = TestBridge(), initialized = Completer<Json>();
    source.handlers['initialize'] = (_) => initialized.future;
    final receiving = SearchController(source);
    final starting = receiving.initialize();
    source.event({
      'type': 'incoming',
      'ids': ['shared-photo'],
    });
    initialized.complete({'platform': 'ios', 'access': 'none', 'incoming': []});
    await starting;
    expect(receiving.incoming, ['shared-photo']);
    receiving.dispose();
    await source.stream.close();
  });
  test('late album query cannot replace a new individual selection', () async {
    await controller.useReference('person');
    final wait = Completer<Json>();
    bridge.handlers['albums'] = (_) => wait.future;
    controller.navigate(StepPage.albums);
    controller.addPhotos(['new']);
    wait.complete({'access': 'full', 'albums': []});
    await Future<void>.delayed(Duration.zero);
    expect(controller.photos, ['new']);
    expect(controller.loadingAlbums, isFalse);
  });
  test(
    'starting another person clears feedback and complementary references',
    () async {
      await controller.useReference('one');
      await controller.useReference('side', append: true);
      expect(controller.examples.length, 1);
      await controller.useReference('other');
      expect(controller.examples, isEmpty);
      expect(controller.chosen!.id, 'other:0');
      await controller.clear();
      expect(controller.reference, isNull);
      expect(controller.page, StepPage.home);
    },
  );
}

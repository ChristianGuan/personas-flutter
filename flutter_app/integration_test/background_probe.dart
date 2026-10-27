// QA-only entrypoint. The host supplies public fixtures in the private cache.
// No production method channel, permission override or timing hook is added.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:personas_flutter/main.dart';
import 'package:personas_flutter/native_bridge.dart';
import 'package:personas_flutter/search_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final c = SearchController(NativePhotoBridge());
  runApp(PersonasApp(controller: c));
  unawaited(probe(c));
}

Future<void> probe(SearchController c) async {
  final cache = Platform.isIOS
      ? Directory.systemTemp.parent.uri.resolve('Library/Caches/')
      : Uri.parse('file:///data/user/0/co.local.personas/cache/');
  final state = File.fromUri(cache.resolve('background-probe.json'));
  var fixtures = cache.resolve(
    Platform.isIOS ? 'PersonasSession/qa-flutter/' : 'qa-flutter/',
  );
  // Foundation's sandbox URLs use /var on physical iOS; Dart's temp root may
  // include the /private alias. Use the same spelling as native provider copies.
  if (Platform.isIOS && fixtures.path.startsWith('/private/var/')) {
    fixtures = Uri.file(fixtures.path.substring('/private'.length));
  }
  void report(String phase, [Map<String, dynamic>? extra]) {
    state.writeAsStringSync(
      jsonEncode({
        'phase': phase,
        'mode': c.backgroundMode,
        'processed': c.processed,
        'accepted': c.results.length,
        'skipped': c.skipped,
        'cancelled': c.cancelled,
        'notifications': c.notificationsEnabled,
        'message': c.message,
        ...?extra,
      }),
    );
  }

  Map<String, String> outcomes() => {
    for (final r in c.reviews) Uri.parse(r.id).pathSegments.last: r.outcome,
  };
  Future<void> waitFor(bool Function() ready) async {
    final until = DateTime.now().add(const Duration(minutes: 4));
    while (!ready()) {
      if (DateTime.now().isAfter(until)) throw StateError('Probe timeout');
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  try {
    final previous = state.existsSync()
        ? jsonDecode(state.readAsStringSync())
        : null;
    report('initializing');
    await c.initialize();
    if (const bool.fromEnvironment('PERSONAS_QA_CLEANUP')) {
      if (c.busy) throw StateError('An existing search is still active');
      if (c.photos.any((id) => !id.contains('/qa-flutter/'))) {
        throw StateError('Refusing to clear a non-QA search');
      }
      await c.clear();
      report('cleaned');
      await state.delete();
      return;
    }
    if (previous is Map && previous['phase'] == 'complete') {
      report('restored', {
        'outcomes': outcomes(),
        'referencesExpired': c.chosen == null,
        'sameOutcomes':
            jsonEncode(outcomes()) == jsonEncode(previous['outcomes']),
      });
      return;
    }
    if (c.busy) throw StateError('An existing search is still active');
    await c.clear();
    report('waiting-fixtures');
    await waitFor(
      () => File.fromUri(fixtures.resolve('background-ready')).existsSync(),
    );
    await c.useReference(fixtures.resolve('face-10bit.heic').toString());
    if (c.chosen == null && c.reference?.faces.isNotEmpty == true) {
      c.choose(c.reference!.faces.first);
    }
    if (c.chosen == null) throw StateError('No fixture face: ${c.message}');
    final inputs =
        Directory.fromUri(fixtures)
            .listSync()
            .whereType<File>()
            .where(
              (f) => RegExp(
                r'\.(heic|jpg)$',
                caseSensitive: false,
              ).hasMatch(f.path),
            )
            .map((f) => f.uri.toString())
            .toList()
          ..sort();
    c.addPhotos(inputs);
    if (const bool.fromEnvironment('PERSONAS_QA_SKIP_NOTIFICATIONS')) {
      c.notificationsAsked = true;
    }
    await waitFor(
      () => WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
    );
    final elapsed = Stopwatch()..start();
    await c.search();
    if (!c.busy) throw StateError('Search did not start: ${c.message}');
    report('running', {'total': inputs.length});
    if (const bool.fromEnvironment('PERSONAS_QA_CANCEL')) {
      await waitFor(() => c.processed >= 25 || !c.busy);
      await c.cancel();
      await waitFor(() => !c.busy);
      report('cancelled', {'total': inputs.length});
      return;
    }
    await waitFor(() => !c.busy);
    final first = outcomes();
    final firstMs = elapsed.elapsedMilliseconds;
    final notificationStatus = await c.bridge.call('notifications');
    report('background-complete', {
      'outcomes': first,
      'elapsedMs': firstMs,
      'notificationStatus': notificationStatus,
    });
    // Wait until the host brings the app back before the foreground comparison.
    final compare = File.fromUri(fixtures.resolve('compare'));
    await waitFor(compare.existsSync);
    await c.resume();
    if (const bool.fromEnvironment('PERSONAS_QA_SKIP_NOTIFICATIONS')) {
      c.notificationsAsked = true;
    }
    await c.search();
    await waitFor(() => !c.busy);
    final second = outcomes();
    report('complete', {
      'total': inputs.length,
      'elapsedMs': firstMs,
      'outcomes': second,
      'sameOutcomes': jsonEncode(first) == jsonEncode(second),
      'notificationStatus': notificationStatus,
    });
  } catch (error) {
    report('error', {'error': error.toString()});
  }
}

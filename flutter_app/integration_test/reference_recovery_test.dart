import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:personas_flutter/native_bridge.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('iOS native reference cancellation and stale cancel allow retry', (
    tester,
  ) async {
    expect(Platform.isIOS, isTrue);
    final bridge = NativePhotoBridge();
    await bridge.call('initialize');
    final folder = Directory.fromUri(
      Directory.systemTemp.parent.uri.resolve(
        'Library/Caches/PersonasSession/qa-reference-recovery/',
      ),
    );
    final marker = File('${folder.path}/ready');
    await tester.runAsync(() async {
      final limit = DateTime.now().add(const Duration(minutes: 2));
      while (!marker.existsSync() && DateTime.now().isBefore(limit)) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    });
    expect(marker.existsSync(), isTrue, reason: 'Public HEIC fixture required');
    final image = File(
      '${folder.path}/face-10bit.heic',
    ).uri.toString().replaceFirst('file:///private/var/', 'file:///var/');
    // Queue cancellation immediately after starting the native request. The
    // callback is attached first so a cancellation error is never unhandled.
    final first = bridge
        .call('reference', {'id': image, 'requestId': 1001})
        .then<Object?>((value) => value, onError: (Object error) => error);
    await bridge.call('cancelPreparation', {'requestId': 1001});
    final cancelled = await first.timeout(const Duration(seconds: 10));
    expect(cancelled, isA<PlatformException>());
    expect((cancelled as PlatformException).message, contains('cancelada'));

    // A late cancellation for the first request must not cancel the next one.
    final retry = bridge.call('reference', {'id': image, 'requestId': 1002});
    await bridge.call('cancelPreparation', {'requestId': 1001});
    final reference = Reference.fromJson(
      await retry.timeout(const Duration(seconds: 90)),
    );
    expect(reference.faces, isNotEmpty);
    final preview = await bridge.call<Uint8List>('image', {
      'id': image,
      'edge': 512,
    });
    expect(preview, isNotEmpty);
    await bridge.call('releaseReference', {'token': reference.token});
    // Only this test's public copies are removed; no session or library clear.
    folder.deleteSync(recursive: true);
  });
}

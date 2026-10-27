import 'dart:io';
import 'dart:convert';
import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() => integrationDriver(
  responseDataCallback: (data) async {
    final directory = Directory(
      Platform.environment['PERSONAS_QA_OUTPUT'] ??
          '/tmp/personas-flutter-visual',
    );
    await directory.create(recursive: true);
    final metrics = Map<String, dynamic>.of(data ?? {})..remove('screenshots');
    await File(
      '${directory.path}/metrics.json',
    ).writeAsString(jsonEncode(metrics));
  },
  onScreenshot: (name, bytes, [args]) async {
    final directory = Directory(
      Platform.environment['PERSONAS_QA_OUTPUT'] ??
          '/tmp/personas-flutter-visual',
    );
    await directory.create(recursive: true);
    await File('${directory.path}/$name.png').writeAsBytes(bytes);
    return true;
  },
);

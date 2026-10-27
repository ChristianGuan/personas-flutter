import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

abstract class AnalyticsTransport {
  Future<void> register(String id, String token);
  Future<Set<String>> send(
    String id,
    String token,
    List<Map<String, Object?>> events,
  );
  Future<void> delete(String id, String token);
  void cancel();
}

class HttpAnalyticsTransport implements AnalyticsTransport {
  final Uri base;
  HttpClient? _client;
  HttpAnalyticsTransport(String url) : base = Uri.parse(url) {
    final local = {
      'localhost',
      '127.0.0.1',
      '::1',
      '10.0.2.2',
    }.contains(base.host);
    if (base.host.isEmpty ||
        base.userInfo.isNotEmpty ||
        base.hasQuery ||
        base.hasFragment ||
        (base.scheme != 'https' &&
            !(kDebugMode && local && base.scheme == 'http')))
      throw ArgumentError('Use an HTTPS analytics API');
  }
  Future<Map<String, dynamic>> _request(
    String method,
    String path,
    String token, [
    Object? body,
  ]) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    _client = client;
    try {
      return await (() async {
        final request = await client.openUrl(method, base.resolve(path));
        request.followRedirects = false;
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
        request.headers.contentType = ContentType.json;
        if (body != null) request.write(jsonEncode(body));
        final response = await request.close();
        if (response.statusCode != 200)
          throw const HttpException('Analytics API unavailable');
        final bytes = <int>[];
        await for (final chunk in response) {
          bytes.addAll(chunk);
          if (bytes.length > 65536)
            throw const FormatException('Response too large');
        }
        return Map<String, dynamic>.from(jsonDecode(utf8.decode(bytes)) as Map);
      })().timeout(const Duration(seconds: 10));
    } finally {
      client.close(force: true);
      if (identical(client, _client)) _client = null;
    }
  }

  @override
  Future<void> register(String id, String token) async {
    await _request('POST', '/v1/analytics/installations', token, {
      'installationId': id,
    });
  }

  @override
  Future<Set<String>> send(
    String id,
    String token,
    List<Map<String, Object?>> events,
  ) async {
    final result = await _request('POST', '/v1/analytics/events/batch', token, {
      'installationId': id,
      'events': events,
    });
    return (result['acceptedEventIds'] as List).cast<String>().toSet();
  }

  @override
  Future<void> delete(String id, String token) async {
    final result = await _request(
      'DELETE',
      '/v1/analytics/installations/$id',
      token,
    );
    if (result['deleted'] != true)
      throw const FormatException('Deletion unconfirmed');
  }

  @override
  void cancel() {
    _client?.close(force: true);
    _client = null;
  }
}

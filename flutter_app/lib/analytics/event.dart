import 'dart:math';

typedef Payload = Map<String, Object>;
final _random = Random.secure();
String randomToken() => List.generate(
  32,
  (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
).join();
String randomUuid() {
  final b = List.generate(16, (_) => _random.nextInt(256));
  b[6] = (b[6] & 15) | 64;
  b[8] = (b[8] & 63) | 128;
  final h = b.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

String countRange(int count) => count <= 0
    ? '0'
    : count <= 25
    ? '1-25'
    : count <= 100
    ? '26-100'
    : count <= 500
    ? '101-500'
    : '501+';
int durationMs(Stopwatch? clock) =>
    (clock?.elapsedMilliseconds ?? 0).clamp(0, 86400000);
const _ranges = {'0', '1-25', '26-100', '101-500', '501+'};
const _fields = <String, Set<String>>{
  'session_started': {},
  'session_ended': {'durationMs'},
  'search_started': {},
  'search_completed': {'durationMs', 'photoRange', 'matchRange'},
  'search_cancelled': {'durationMs', 'photoRange'},
  'search_failed': {'durationMs', 'errorCategory'},
  'results_rated': {'stars'},
  'results_reviewed': {'confirmed', 'rejected'},
};
bool _validLegacyPayload(String type, Payload payload) {
  final keys = _fields[type];
  if (keys == null ||
      keys.length != payload.length ||
      !keys.containsAll(payload.keys))
    return false;
  for (final e in payload.entries) {
    final v = e.value;
    switch (e.key) {
      case 'durationMs':
        if (v is! int || v < 0 || v > 86400000) return false;
      case 'photoRange':
      case 'matchRange':
        if (!_ranges.contains(v)) return false;
      case 'stars':
        if (v is! int || v < 1 || v > 5) return false;
      case 'confirmed':
      case 'rejected':
        if (v is! int || v < 0 || v > 1000000) return false;
      case 'errorCategory':
        if (!{'permission', 'storage', 'processing', 'unknown'}.contains(v))
          return false;
    }
  }
  return type != 'results_reviewed' ||
      (payload['confirmed'] as int) + (payload['rejected'] as int) > 0;
}

final _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);
bool validPayload(String type, Payload payload, {int schemaVersion = 1}) {
  if (schemaVersion == 1) return _validLegacyPayload(type, payload);
  if (schemaVersion != 2) return false;
  const common = {'sessionId', 'searchId'};
  const counts = {
    'photosPlanned',
    'photosProcessed',
    'unreadableCount',
    'matchesShown',
  };
  final timing = <String>{
    'timingSource',
    if (payload['timingSource'] != 'unavailable') ...{
      'durationMs',
      'setupMs',
      'processingMs',
    },
  };
  const diagnostics = {
    'readMs',
    'decodeMs',
    'engineMs',
    'cacheHits',
    'cacheMisses',
    'cancelLatencyMs',
    'timeToCancelMs',
  };
  final fields = switch (type) {
    'session_started' => {'sessionId'},
    'session_ended' => {'sessionId', 'durationMs'},
    'search_started' => {...common, 'photosPlanned'},
    'search_completed' ||
    'search_cancelled' => {...common, ...counts, ...timing},
    'search_failed' => {...common, ...counts, ...timing, 'errorCategory'},
    'search_interrupted' => {...common, 'photosPlanned', 'errorCategory'},
    'results_rated' => {...common, 'stars'},
    'results_reviewed' => {...common, 'confirmed', 'rejected'},
    'results_presented' => {...common, 'presentationMs'},
    _ => <String>{},
  };
  if ({
    'search_completed',
    'search_cancelled',
    'search_failed',
  }.contains(type)) {
    fields.addAll(diagnostics.where(payload.containsKey));
    if (payload.containsKey('cacheHits') != payload.containsKey('cacheMisses'))
      return false;
  }
  if (fields.isEmpty ||
      fields.length != payload.length ||
      !fields.containsAll(payload.keys))
    return false;
  for (final e in payload.entries) {
    final v = e.value;
    if (common.contains(e.key)) {
      if (v is! String || !_uuidPattern.hasMatch(v)) return false;
    } else if (e.key == 'timingSource') {
      if (!{'live', 'unavailable'}.contains(v)) return false;
    } else if (e.key == 'errorCategory') {
      if (type == 'search_interrupted'
          ? v != 'process_interrupted'
          : !{'permission', 'storage', 'processing', 'unknown'}.contains(v))
        return false;
    } else {
      final max = e.key.endsWith('Ms')
          ? 86400000
          : e.key == 'stars'
          ? 5
          : 1000000;
      if (v is! int || v < 0 || v > max || e.key == 'stars' && v < 1)
        return false;
    }
  }
  if (type == 'results_reviewed' &&
      (payload['confirmed'] as int) + (payload['rejected'] as int) == 0)
    return false;
  if (payload.containsKey('cacheHits') &&
      (payload['cacheHits'] as int) + (payload['cacheMisses'] as int) >
          (payload['photosProcessed'] as int))
    return false;
  if (payload.containsKey('photosProcessed')) {
    final processed = payload['photosProcessed'] as int;
    if (processed > (payload['photosPlanned'] as int) ||
        (payload['unreadableCount'] as int) + (payload['matchesShown'] as int) >
            processed ||
        payload['timingSource'] == 'live' &&
            (payload['setupMs'] as int) + (payload['processingMs'] as int) >
                (payload['durationMs'] as int))
      return false;
  }
  return true;
}

abstract class AnalyticsSink {
  bool get enabled;
  void record(String type, [Payload payload = const {}]);
}

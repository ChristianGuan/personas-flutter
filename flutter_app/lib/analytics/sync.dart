import 'dart:math';
import 'store.dart';
import 'transport.dart';

abstract class TokenVault {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> clear();
}

class AnalyticsSync {
  final AnalyticsStore store;
  final TokenVault vault;
  final AnalyticsTransport? transport;
  bool _running = false;
  String? _registered;
  AnalyticsSync(this.store, this.vault, this.transport);
  static int delayMs(int attempt) {
    final exponent = min(max(attempt - 1, 0), 13);
    return min(
      21600000,
      (5000 * pow(2, exponent) * (0.75 + Random().nextDouble() * 0.5)).round(),
    );
  }

  Future<void> flush() async {
    if (_running) return;
    _running = true;
    try {
      await store.prune();
      if (transport == null) return;
      var state = await store.state();
      final id = state.installationId;
      if (id == null) return;
      final token = await vault.read();
      if (token == null)
        return; // Fail closed; keep deletion state instead of inventing credentials.
      if (state.deletionPending) {
        if (state.deletionNextAttempt > DateTime.now().millisecondsSinceEpoch)
          return;
        try {
          await transport!.delete(id, token);
          // Persist deletion confirmation; a crash before it simply retries.
          await store.deleted(id);
        } catch (_) {
          await store.deletionFailed(id, delayMs);
        }
        return;
      }
      if (!state.enabled) return;
      final batch = await store.due();
      if (batch.isEmpty) return;
      try {
        if (_registered != id) {
          await transport!.register(id, token);
          _registered = id;
        }
        state = await store.state();
        if (!state.enabled ||
            state.deletionPending ||
            state.installationId != id)
          return;
        final accepted = await transport!.send(
          id,
          token,
          batch.map(AnalyticsStore.event).toList(),
        );
        await store.acknowledge(batch, accepted, delayMs);
      } catch (_) {
        _registered = null;
        await store.acknowledge(batch, {}, delayMs);
      }
    } catch (_) {
      // No telemetry of telemetry; no request bodies or platform errors in logs.
    } finally {
      _running = false;
    }
  }

  void cancel() => transport?.cancel();
}

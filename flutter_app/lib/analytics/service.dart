import 'dart:async';
import 'dart:io';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:workmanager/workmanager.dart';
import 'event.dart';
import 'store.dart';
import 'sync.dart';
import 'transport.dart';

const analyticsApi = String.fromEnvironment('ANALYTICS_API_URL');
const analyticsTask = 'co.local.personas.analytics.sync';

class SecureTokenVault implements TokenVault {
  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );
  @override
  Future<String?> read() => _storage.read(key: 'analytics_token_v1');
  @override
  Future<void> write(String value) =>
      _storage.write(key: 'analytics_token_v1', value: value);
  @override
  Future<void> clear() => _storage.delete(key: 'analytics_token_v1');
}

@pragma('vm:entry-point')
void analyticsDispatcher() {
  Workmanager().executeTask((task, input) async {
    AnalyticsStore? store;
    try {
      store = await AnalyticsStore.open();
      final sync = AnalyticsSync(
        store,
        SecureTokenVault(),
        analyticsApi.isEmpty ? null : HttpAnalyticsTransport(analyticsApi),
      );
      await sync.flush();
      sync.cancel();
      return true;
    } catch (_) {
      return false;
    } finally {
      await store?.close();
    }
  });
}

class AnalyticsService extends ChangeNotifier implements AnalyticsSink {
  AnalyticsStore? _store;
  AnalyticsSync? _sync;
  final TokenVault _vault;
  final AnalyticsTransport? _transport;
  bool _reenableRequested = false;
  StreamSubscription<List<ConnectivityResult>>? _connectivity;
  Timer? _timer;
  bool _enabled = false,
      _pending = false,
      _ready = false,
      _changing = false,
      _disposed = false;
  Stopwatch? _session;
  String? _sessionId;
  String _appVersion = '';
  bool _renewalRequired = false, _reconciliationKnown = false;
  String? _activeNativeSearch;
  (String, Payload)? _restoredTerminal;
  bool get renewalRequired => _renewalRequired;
  String status = '';
  AnalyticsService({
    TokenVault? vault,
    AnalyticsTransport? transport,
    AnalyticsStore? store,
  }) : _vault = vault ?? SecureTokenVault(),
       _transport = transport,
       _store = store;
  @override
  bool get enabled => _enabled && !_renewalRequired;
  bool get pendingDeletion => _pending;
  bool get consentRequested => enabled || _reenableRequested;
  bool get ready => _ready;
  bool get changing => _changing;
  Future<void> initialize() async {
    try {
      _store ??= await AnalyticsStore.open();
      final state = await _store!.state();
      _enabled = state.enabled;
      _renewalRequired = state.enabled && state.consentVersion < 2;
      final package = await PackageInfo.fromPlatform();
      _appVersion = '${package.version}+${package.buildNumber}';
      if (_renewalRequired)
        status =
            'No estamos recogiendo datos nuevos. Revisa este mensaje antes de decidir si quieres seguir compartiendo.';
      _pending = state.deletionPending;
      _reenableRequested = state.reenableRequested;
      _sync = AnalyticsSync(
        _store!,
        _vault,
        _transport ??
            (analyticsApi.isEmpty
                ? null
                : HttpAnalyticsTransport(analyticsApi)),
      );
      _ready = true;
      try {
        await Workmanager().initialize(analyticsDispatcher);
      } catch (_) {}
      _connectivity = Connectivity().onConnectivityChanged.listen(
        (_) => unawaited(flush()),
      );
      _timer = Timer.periodic(
        const Duration(seconds: 15),
        (_) => unawaited(flush()),
      );
      if (_enabled || _pending) unawaited(_schedule());
      foreground();
      if (_reconciliationKnown) reconcileSearch(_activeNativeSearch);
      unawaited(flush());
    } catch (_) {
      status =
          'No podemos activar el envío de datos de uso ahora. Puedes seguir buscando.';
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> _schedule() async {
    try {
      await Workmanager().registerPeriodicTask(
        analyticsTask,
        analyticsTask,
        frequency: const Duration(minutes: 15),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      );
    } catch (_) {}
  }

  Future<void> setConsent(bool value) async {
    if (!_ready ||
        _changing ||
        value == enabled &&
            value == consentRequested &&
            !_pending &&
            !_renewalRequired)
      return;
    _changing = true;
    var saved = false;
    // Stop capture and abort current foreground HTTP before awaiting any writes.
    if (!value) {
      _enabled = false;
      _session = null;
      _sessionId = null;
      _sync?.cancel();
    }
    if (!_disposed) notifyListeners();
    try {
      if (value) {
        final previous = await _store!.state();
        if (previous.deletionPending) {
          await _store!.requestReenable();
          _reenableRequested = true;
          _pending = true;
          await _store!.retryDeletion();
          status =
              'Guardamos tu elección. Volverás a compartir datos cuando termine el borrado anterior.';
        } else {
          final id = previous.installationId ?? randomUuid();
          if (previous.installationId == null) {
            final token = randomToken();
            await _vault.write(token);
            if (await _vault.read() != token)
              throw StateError('Credential storage unavailable');
          } else if (await _vault.read() == null) {
            throw StateError('Credential storage unavailable');
          }
          await _store!.enable(id);
          _enabled = true;
          _renewalRequired = false;
          status =
              'Ya estás compartiendo datos de uso. Puedes desactivarlo cuando quieras.';
          foreground();
          if (_reconciliationKnown) reconcileSearch(_activeNativeSearch);
          _pending = false;
          _reenableRequested = false;
        }
      } else {
        await _store!.revoke();
        _reenableRequested = false;
        _renewalRequired = false;
        _pending = (await _store!.state()).deletionPending;
        try {
          await Workmanager().cancelByUniqueName(analyticsTask);
        } catch (_) {}
        status =
            'Dejaste de compartir datos y borramos los pendientes. Completaremos el borrado de los datos enviados cuando haya conexión.';
      }
      if (_enabled || _pending) await _schedule();
      saved = true;
    } catch (_) {
      status = 'No pudimos guardar tu elección. Vuelve a intentarlo.';
    } finally {
      _changing = false;
      if (!_disposed) notifyListeners();
    }
    if (saved) unawaited(flush());
  }

  @override
  void record(String type, [Payload payload = const {}]) {
    if (!enabled || !_ready || _changing && type != 'session_started') return;
    // Snapshot primitives now; no photo/native objects enter the outbox.
    if (_sessionId == null) {
      _sessionId = randomUuid();
      _session = Stopwatch()..start();
    }
    final copy = <String, Object>{...payload, 'sessionId': _sessionId!};
    unawaited(_capture(type, copy));
  }

  Future<void> _capture(String type, Payload payload) async {
    try {
      if (await _store!.add(
        type,
        payload,
        schemaVersion: 2,
        platform: Platform.isIOS ? 'ios' : 'android',
        appVersion: _appVersion,
      ))
        await flush();
    } catch (_) {}
  }

  void foreground() {
    if (!enabled || _session != null) return;
    _sessionId = randomUuid();
    _session = Stopwatch()..start();
    record('session_started');
  }

  void background() {
    if (_session == null) return;
    final elapsed = durationMs(_session);
    _session = null;
    record('session_ended', {'durationMs': elapsed});
  }

  void deferRestoredTerminal(String type, Payload payload) {
    _restoredTerminal = (type, Map<String, Object>.of(payload));
  }

  void reconcileSearch(String? activeSearchId) {
    _reconciliationKnown = true;
    _activeNativeSearch = activeSearchId;
    if (!_ready || !enabled) return;
    unawaited(_recover());
  }

  Future<void> _recover() async {
    try {
      final terminal = _restoredTerminal;
      _restoredTerminal = null;
      if (terminal != null && _sessionId != null)
        await _capture(terminal.$1, {...terminal.$2, 'sessionId': _sessionId!});
      await _store!.recoverInterrupted(_activeNativeSearch);
      await flush();
    } catch (_) {}
  }

  Future<void> retryDeletion() async {
    await _store?.retryDeletion();
    await flush();
  }

  Future<void> flush() async {
    await _sync?.flush();
    if (_store == null) return;
    try {
      final state = await _store!.state();
      if (_changing) return;
      final wasPending = _pending;
      final changed =
          _pending != state.deletionPending ||
          _reenableRequested != state.reenableRequested;
      _pending = state.deletionPending;
      _reenableRequested = state.reenableRequested;
      if (!_pending && _reenableRequested && !_disposed) {
        await setConsent(true);
        return;
      }
      if (wasPending && !_pending) {
        status =
            'Se eliminaron los datos que habías compartido. Sólo se conservan estadísticas generales.';
        try {
          await Workmanager().cancelByUniqueName(analyticsTask);
        } catch (_) {}
        if (enabled || _reenableRequested) await _schedule();
      }
      if (changed && !_disposed) notifyListeners();
    } catch (_) {}
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    unawaited(_connectivity?.cancel());
    _sync?.cancel();
    super.dispose();
  }
}

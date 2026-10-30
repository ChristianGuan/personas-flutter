import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'native_bridge.dart';
import 'analytics/event.dart';
import 'analytics/service.dart';

enum StepPage { home, reference, albums, analysis, results }

class Example {
  final Reference reference;
  final Face face;
  const Example(this.reference, this.face);
}

class Review {
  final String id, outcome;
  final String? key;
  const Review(this.id, this.outcome, this.key);
  bool get accepted => outcome == 'match' || outcome == 'confirmed';
  bool get pending => outcome == 'review';
  String get label => switch (outcome) {
    'match' => 'Coincidencia',
    'confirmed' => 'Confirmada por ti',
    'review' => 'Por revisar',
    'rejected' => 'Excluida por ti',
    'noFace' => 'Sin rostros utilizables',
    'unreadable' => 'No se pudo analizar',
    _ => 'Rostros detectados, sin coincidencia suficiente',
  };
}

class SearchController extends ChangeNotifier {
  final PhotoBridge bridge;
  final AnalyticsSink? analytics;
  Stopwatch? _searchClock, _presentationClock;
  Stopwatch? _cancelClock;
  int? _timeToCancelMs;
  Map<String, Object> _nativeDiagnostics = {};
  String? _searchId;
  int? _searchStartedAt;
  int _planned = 0, _setupMs = 0;
  bool _finished = false, _workerDispatched = false;
  bool ratingAvailable = false, reviewSent = false;
  int? rating;
  void _finishAnalytics(String type) {
    if (_searchId == null || _finished || _replaying) return;
    _finished = true;
    final measured = _searchClock != null;
    final duration = durationMs(_searchClock);
    _searchClock = null;
    final payload = <String, Object>{
      'searchId': _searchId!,
      'photosPlanned': _planned,
    };
    if (type == 'search_interrupted') {
      payload['errorCategory'] = 'process_interrupted';
    } else {
      final setup = _workerDispatched ? _setupMs.clamp(0, duration) : duration;
      payload.addAll({
        'timingSource': measured ? 'live' : 'unavailable',
        if (measured) ...{
          'durationMs': duration,
          'setupMs': setup,
          'processingMs': duration - setup,
        },
        'photosProcessed': processed.clamp(0, _planned),
        'unreadableCount': skipped.clamp(0, processed),
        'matchesShown': results.length.clamp(0, processed - skipped),
      });
      payload.addAll(_nativeDiagnostics);
      if (_timeToCancelMs != null) payload['timeToCancelMs'] = _timeToCancelMs!;
      if (_cancelClock != null)
        payload['cancelLatencyMs'] = durationMs(_cancelClock);
      if (type == 'search_failed') payload['errorCategory'] = 'processing';
    }
    if (type == 'search_completed') {
      ratingAvailable = true;
      _presentationClock = Stopwatch()..start();
    }
    if (analytics case final AnalyticsService service when !service.ready) {
      service.deferRestoredTerminal(type, payload);
    } else {
      analytics?.record(type, payload);
    }
    if (analytics case final AnalyticsService service)
      service.reconcileSearch(null);
  }

  void resultsPresented() {
    final clock = _presentationClock;
    if (clock == null || _searchId == null || page != StepPage.results) return;
    _presentationClock = null;
    analytics?.record('results_presented', {
      'searchId': _searchId!,
      'presentationMs': durationMs(clock),
    });
  }

  void rateResults(int? stars) {
    if (!ratingAvailable || stars != null && (stars < 1 || stars > 5)) return;
    ratingAvailable = false;
    rating = stars;
    if (stars != null && _searchId != null)
      analytics?.record('results_rated', {
        'searchId': _searchId!,
        'stars': stars,
      });
    _changed();
  }

  int get confirmedCount =>
      reviews.where((r) => r.outcome == 'confirmed').length;
  int get rejectedCount => reviews.where((r) => r.outcome == 'rejected').length;
  void sendReviewTotals() {
    if (reviewSent ||
        confirmedCount + rejectedCount == 0 ||
        busy ||
        _searchId == null)
      return;
    analytics?.record('results_reviewed', {
      'searchId': _searchId!,
      'confirmed': confirmedCount,
      'rejected': rejectedCount,
    });
    reviewSent = true;
    _changed();
  }

  StreamSubscription<Json>? _subscription;
  bool _disposed = false, _appending = false;
  bool _initializing = false,
      _replaying = false,
      _permissionPending = false,
      _cancelStart = false;
  final List<Json> _earlyEvents = [];
  int _generation = 0, _libraryGeneration = 0, _run = 0;
  int? _preparation;
  StepPage page = StepPage.home;
  Reference? reference;
  Face? chosen;
  Reference? searchReference;
  Face? searchFace;
  final List<Example> examples = [];
  List<String> photos = [], incoming = [];
  List<Album> albums = [];
  Album? album;
  String access = 'none', platform = '', message = '';
  bool photoAccessAsked = true, _requestingPhotoAccess = false;
  String backgroundMode = '';
  bool notificationsEnabled = false,
      notificationsAsked = false,
      canAskNotifications = true,
      askingNotifications = false;
  bool picking = false;
  bool get blocked => busy || picking;
  bool get canCancelPreparation => platform == 'ios' && _preparation != null;
  bool busy = false,
      loadingAlbums = false,
      cancelled = false,
      cancelling = false,
      libraryError = false;
  int processed = 0, skipped = 0;
  final List<Review> reviews = [];
  final Set<String> selected = {};
  final Map<String, bool> _feedback = {};
  List<String> get results =>
      reviews.where((r) => r.accepted).map((r) => r.id).toList();
  List<Review> get pending => reviews.where((r) => r.pending).toList();
  bool get canSearch =>
      chosen != null && photos.isNotEmpty && !blocked && !loadingAlbums;
  bool get analysing => busy && page == StepPage.analysis;
  SearchController(this.bridge, {this.analytics});

  void _changed() {
    if (!_disposed && !_replaying) notifyListeners();
  }

  String _error(Object error) => error is PlatformException
      ? (error.message ??
            'No se pudo completar la acción. Vuelve a intentarlo.')
      : 'No se pudo completar la acción. Revisa el acceso y vuelve a intentarlo.';
  void _resetResults() {
    _cancelClock = null;
    _timeToCancelMs = null;
    _nativeDiagnostics = {};
    _searchId = null;
    _searchStartedAt = null;
    _searchClock = null;
    _presentationClock = null;
    _setupMs = 0;
    _planned = 0;
    _finished = false;
    _workerDispatched = false;
    ratingAvailable = false;
    reviewSent = false;
    rating = null;
    reviews.clear();
    selected.clear();
    processed = 0;
    skipped = 0;
    cancelled = false;
    cancelling = false;
  }

  Future<void> initialize() async {
    _initializing = true;
    _subscription = bridge.events.listen(
      _event,
      onError: (Object e) {
        message = _error(e);
        _changed();
      },
    );
    try {
      final j = jsonMap(await bridge.call('initialize'));
      platform = j['platform'] ?? '';
      access = j['access'] ?? 'none';
      photoAccessAsked = j['photoAccessAsked'] as bool? ?? true;
      backgroundMode = j['backgroundMode'] as String? ?? '';
      _notificationStatus(j['notifications']);
      _restoreSnapshot(j['search'], force: true);
      if (analytics case final AnalyticsService service)
        service.reconcileSearch(busy ? _searchId : null);
      final initialIncoming = List<String>.from(j['incoming'] ?? []);
      if (initialIncoming.isNotEmpty) incoming = initialIncoming;
    } catch (e) {
      message = _error(e);
    } finally {
      _initializing = false;
      final events = List<Json>.of(_earlyEvents);
      _earlyEvents.clear();
      for (final event in events) {
        _event(event);
      }
    }
    _changed();
  }

  void _event(Json event) {
    if (_disposed) return;
    if (event['type'] == 'incoming') {
      incoming = List<String>.from(event['ids'] ?? []);
      _changed();
      return;
    }
    if (_initializing && !_replaying) {
      _earlyEvents.add(event);
      return;
    }
    if (event['type'] == 'openAnalysis') {
      unawaited(resume(openResults: true));
      return;
    }
    if (event['runId'] != _run || !analysing) return;
    if (event['type'] == 'status') {
      backgroundMode = event['backgroundMode'] as String? ?? backgroundMode;
      if (event['cancelling'] == true) {
        cancelling = true;
        message = 'Cancelando… Estamos terminando la foto en curso.';
      }
    } else if (event['type'] == 'photo') {
      if (cancelling && !_replaying) return;
      final id = event['id'] as String;
      if (!photos.contains(id) || reviews.any((r) => r.id == id)) return;
      var outcome = event['outcome'] as String;
      final key = event['key'] as String?;
      if (outcome != 'unreadable' &&
          key != null &&
          _feedback.containsKey(key)) {
        outcome = _feedback[key]! ? 'confirmed' : 'rejected';
      }
      reviews.add(Review(id, outcome, key));
      processed = reviews.length;
      if (outcome == 'unreadable') skipped++;
    } else if (event['type'] == 'done') {
      final diagnostics = event['diagnostics'];
      if (diagnostics is Map) {
        for (final key in [
          'readMs',
          'decodeMs',
          'engineMs',
          'cacheHits',
          'cacheMisses',
          'cancelLatencyMs',
        ]) {
          final value = diagnostics[key];
          if (value is int && value >= 0)
            _nativeDiagnostics[key] = value.clamp(
              0,
              key.startsWith('cache') ? 1000000 : 86400000,
            );
        }
      }
      // Native callbacks may include work suppressed after cancellation; do not claim more samples than visible photos.
      if ((_nativeDiagnostics['cacheHits'] as int? ?? 0) +
              (_nativeDiagnostics['cacheMisses'] as int? ?? 0) >
          processed) {
        _nativeDiagnostics.remove('cacheHits');
        _nativeDiagnostics.remove('cacheMisses');
      }
      cancelling = false;
      busy = false;
      page = StepPage.results;
      cancelled = event['cancelled'] == true;
      _finishAnalytics(
        event['error'] != null
            ? 'search_failed'
            : cancelled
            ? 'search_cancelled'
            : 'search_completed',
      );
      message =
          event['error'] as String? ??
          (cancelled
              ? 'Análisis cancelado. Puedes revisar lo encontrado o volver a buscar.'
              : pending.isNotEmpty
              ? 'Hay fotos dudosas por revisar. Confirma cuáles son de esta persona.'
              : results.isEmpty
              ? 'No encontramos coincidencias. Prueba otra referencia clara.'
              : 'Revisa las coincidencias antes de compartir.');
    }
    _changed();
  }

  void _notificationStatus(dynamic value) {
    if (value is! Map) return;
    notificationsEnabled = value['enabled'] == true;
    notificationsAsked = value['asked'] == true;
    canAskNotifications = value['canAsk'] == true;
  }

  Future<void> requestNotifications({bool automatic = false}) async {
    if (askingNotifications || _disposed || notificationsEnabled) return;
    if (!canAskNotifications && !automatic) {
      try {
        await bridge.call('notificationSettings');
      } catch (e) {
        message = _error(e);
        _changed();
      }
      return;
    }
    if (automatic && notificationsAsked) return;
    askingNotifications = true;
    _changed();
    try {
      final response = await bridge.call('requestNotifications');
      notificationsAsked = true;
      _notificationStatus(response);
    } catch (_) {
      notificationsAsked = true;
    } finally {
      askingNotifications = false;
      _changed();
    }
  }

  Future<void> resume({bool openResults = false}) async {
    // An older completion must not replace a search awaiting OS permission.
    if (_permissionPending || _preparation != null) return;
    final generation = _generation, run = _run;
    try {
      final snapshot = await bridge.call('searchSnapshot');
      if (_disposed || generation != _generation || run != _run) return;
      if (openResults && snapshot is! Map && !busy) {
        page = StepPage.home;
        message =
            'El último análisis ya no está disponible. Inicia una nueva búsqueda.';
      } else if (busy || openResults) {
        _restoreSnapshot(snapshot, force: openResults);
      }
      final status = await bridge.call('notifications');
      if (_disposed) return;
      _notificationStatus(status);
      _changed();
    } catch (e) {
      if (!_disposed && openResults) {
        message = _error(e);
        _changed();
      }
    }
    if (!_disposed && (page == StepPage.albums || album != null))
      await refreshAlbums();
  }

  void _restoreSnapshot(dynamic value, {bool force = false}) {
    if (_preparation != null) return;
    if (value is! Map || value['context'] is! Map) return;
    final snapshot = jsonMap(value), id = snapshot['runId'] as int;
    if (!force && (id != _run || !analysing)) return;
    final context = jsonMap(snapshot['context']);
    final available = snapshot['referencesAvailable'] == true;
    _replaying = true;
    try {
      if (force) {
        ++_generation;
        ++_libraryGeneration;
        _run = id;
        photos = List<String>.from(context['photos'] ?? []);
        album = context['album'] == null
            ? null
            : Album.fromJson(context['album']);
        searchReference = context['reference'] == null
            ? null
            : Reference.fromJson(context['reference']);
        searchFace = context['chosen'] == null
            ? null
            : Face.fromJson(context['chosen']);
        reference = available ? searchReference : null;
        chosen = available ? searchFace : null;
        examples.clear();
        if (available) {
          for (final item in context['examples'] as List? ?? []) {
            final entry = jsonMap(item);
            examples.add(
              Example(
                Reference.fromJson(entry['reference']),
                Face.fromJson(entry['face']),
              ),
            );
          }
        }
        _feedback
          ..clear()
          ..addAll(Map<String, bool>.from(context['feedback'] as Map? ?? {}));
        _resetResults();
        _searchId = context['analyticsSearchId'] as String?;
        _searchStartedAt = context['analyticsStartedAt'] as int?;
        _planned = photos.length;
        _setupMs = context['analyticsSetupMs'] as int? ?? 0;
        busy = true;
        page = StepPage.analysis;
      }
      if (snapshot['cancelling'] == true) cancelling = true;
      backgroundMode = snapshot['backgroundMode'] as String? ?? backgroundMode;
      for (final event in snapshot['events'] as List? ?? []) {
        _event(jsonMap(event));
      }
      if (snapshot['done'] != null) _event(jsonMap(snapshot['done']));
      if (force) {
        selected.addAll(
          List<String>.from(context['selected'] ?? []).where(results.contains),
        );
        if (!available)
          message +=
              ' Para volver a buscar, elige de nuevo tu foto de referencia.';
      }
    } finally {
      _replaying = false;
      if (_searchId != null && !_finished && snapshot['done'] is Map) {
        final done = jsonMap(snapshot['done']);
        _finishAnalytics(
          done['error'] is String &&
                  (done['error'] as String).contains('interrumpió')
              ? 'search_interrupted'
              : done['error'] != null
              ? 'search_failed'
              : done['cancelled'] == true
              ? 'search_cancelled'
              : 'search_completed',
        );
      }
      _changed();
    }
  }

  Json _context() => {
    'runId': _run,
    if (_searchId != null) 'analyticsSearchId': _searchId,
    if (_searchStartedAt != null) 'analyticsStartedAt': _searchStartedAt,
    if (_searchId != null) 'analyticsSetupMs': _setupMs,
    'photos': photos,
    'album': album?.toJson(),
    'reference': (reference ?? searchReference)?.toJson(),
    'chosen': (chosen ?? searchFace)?.toJson(),
    'examples': examples
        .map(
          (e) => {'reference': e.reference.toJson(), 'face': e.face.toJson()},
        )
        .toList(),
    'feedback': Map<String, bool>.of(_feedback),
    'selected': selected.toList(),
  };
  void _saveResultContext() {
    if (reviews.isEmpty || busy) return;
    unawaited(bridge.call('updateSearch', _context()).catchError((_) => null));
  }

  void navigate(StepPage next) {
    if (blocked) return;
    // Restored results can outlive the native reference kept in memory.
    page = next == StepPage.albums && chosen == null
        ? StepPage.reference
        : next;
    _libraryGeneration++;
    loadingAlbums = false;
    _changed();
    if (page == StepPage.albums) unawaited(refreshAlbums());
  }

  void back() => navigate(switch (page) {
    StepPage.reference => StepPage.home,
    StepPage.albums => StepPage.reference,
    StepPage.results => StepPage.albums,
    _ => StepPage.home,
  });

  Future<List<String>> _pick(String kind) async {
    if (blocked) return [];
    final generation = ++_generation;
    _preparation = generation;
    final previous = message;
    picking = true;
    message =
        'Preparando tus fotos. Las fotos de la nube pueden necesitar descarga…';
    _changed();
    try {
      final ids = List<String>.from(
        await bridge.call('pick', {'kind': kind, 'requestId': generation}) ??
            [],
      );
      return _disposed || generation != _generation ? [] : ids;
    } catch (_) {
      if (_disposed || generation != _generation) return [];
      rethrow;
    } finally {
      if (generation == _generation) {
        _preparation = null;
        picking = false;
        message = previous;
        _changed();
      }
    }
  }

  void cancelPreparation() {
    if (!canCancelPreparation) return;
    final request = _preparation;
    ++_generation;
    _preparation = null;
    busy = false;
    picking = false;
    message = 'Carga cancelada. Puedes volver a elegir tu foto.';
    unawaited(
      bridge
          .call('cancelPreparation', {'requestId': request})
          .catchError((_) => null),
    );
    _changed();
  }

  Future<void> pickReference({bool append = false}) async {
    if (blocked) return;
    try {
      final ids = await _pick('reference');
      if (ids.isNotEmpty) await useReference(ids.first, append: append);
    } catch (e) {
      message = _error(e);
      _changed();
    }
  }

  void _releaseReference(String token) {
    unawaited(
      bridge.call('releaseReference', {'token': token}).catchError((_) => null),
    );
  }

  Future<void> useReference(String id, {bool append = false}) async {
    if (blocked || (append && (reference == null || chosen == null))) return;
    final previous = reference, previousFace = chosen;
    final generation = ++_generation;
    _preparation = generation;
    busy = true;
    page = StepPage.reference;
    message = 'Abriendo tu foto y buscando rostros…';
    _changed();
    try {
      final next = Reference.fromJson(
        await bridge.call('reference', {'id': id, 'requestId': generation}),
      );
      if (generation != _generation || _disposed) {
        await bridge.call('releaseReference', {'token': next.token});
        return;
      }
      if (append && next.faces.isEmpty) {
        _releaseReference(next.token);
        message =
            'No encontramos un rostro utilizable. Conservamos tus referencias anteriores.';
      } else {
        if (append) {
          examples.add(Example(previous!, previousFace!));
        } else {
          final tokens = {
            if (previous != null) previous.token,
            ...examples.map((e) => e.reference.token),
          };
          for (final token in tokens) {
            _releaseReference(token);
          }
          examples.clear();
          _feedback.clear();
        }
        reference = next;
        chosen = next.faces.length == 1 ? next.faces.single : null;
        _appending = append && next.faces.length > 1;
        _resetResults();
        message = next.faces.isEmpty
            ? 'No se encontró un rostro utilizable. Prueba una foto más clara y frontal.'
            : append
            ? 'Confirma que es la misma persona y elige su rostro.'
            : 'Toca el rostro que quieres buscar.';
      }
    } catch (e) {
      if (generation == _generation)
        message =
            '${_error(e)}${previous != null ? ' Conservamos tus referencias anteriores.' : ''}';
    } finally {
      if (generation == _generation && !_disposed) {
        _preparation = null;
        busy = false;
        _changed();
      }
    }
  }

  void choose(Face face) {
    if (blocked || !(reference?.faces.contains(face) ?? false)) return;
    if (chosen?.id != face.id && !_appending) _feedback.clear();
    chosen = face;
    _appending = false;
    _resetResults();
    _changed();
  }

  Future<void> removeExample(int index) async {
    if (blocked || index < 0 || index >= examples.length) return;
    final removed = examples.removeAt(index);
    _resetResults();
    _changed();
    if (reference?.token != removed.reference.token &&
        !examples.any((e) => e.reference.token == removed.reference.token)) {
      await bridge.call('releaseReference', {'token': removed.reference.token});
    }
  }

  Future<void> pickPhotos({bool files = false}) async {
    if (blocked) return;
    try {
      addPhotos(await _pick(files ? 'files' : 'photos'));
    } catch (e) {
      message = _error(e);
      _changed();
    }
  }

  void addPhotos(List<String> ids) {
    if (blocked || ids.isEmpty) return;
    ++_libraryGeneration;
    loadingAlbums = false;
    photos = {...(album == null ? photos : <String>[]), ...ids}.toList();
    album = null;
    _resetResults();
    message =
        '${photos.length} fotos preparadas. Puedes añadir más o iniciar la búsqueda.';
    _changed();
  }

  void clearPhotos() {
    if (blocked) return;
    ++_libraryGeneration;
    photos = [];
    album = null;
    loadingAlbums = false;
    _resetResults();
    _changed();
  }

  Future<void> refreshAlbums({bool request = false}) async {
    if (_requestingPhotoAccess ||
        blocked ||
        (page != StepPage.albums && album == null))
      return;
    request = request || (!photoAccessAsked && access == 'none');
    if (request) {
      photoAccessAsked = true;
      _requestingPhotoAccess = true;
    }
    final generation = ++_libraryGeneration;
    final previous = album;
    loadingAlbums = true;
    libraryError = false;
    _changed();
    try {
      final j = jsonMap(
        await bridge.call(request ? 'requestAccess' : 'albums'),
      );
      if (generation != _libraryGeneration || _disposed) return;
      final nextAccess = j['access'] as String;
      final nextAlbums = (j['albums'] as List).map(Album.fromJson).toList();
      Album? restored;
      for (final item in nextAlbums) {
        if (item.id == previous?.id) restored = item;
      }
      final currentPhotos = previous == null
          ? photos
          : restored == null
          ? <String>[]
          : List<String>.from(
              await bridge.call('albumPhotos', {'id': restored.id}) ?? [],
            );
      if (generation != _libraryGeneration || _disposed) return;
      access = nextAccess;
      albums = nextAlbums;
      if (previous != null) {
        if (!listEquals(photos, currentPhotos)) _resetResults();
        album = restored;
        photos = currentPhotos;
      }
    } catch (e) {
      if (generation == _libraryGeneration) {
        libraryError = true;
        message = _error(e);
        if (previous != null) {
          album = null;
          photos = [];
          _resetResults();
        }
      }
    } finally {
      if (request) _requestingPhotoAccess = false;
      if (generation == _libraryGeneration && !_disposed) {
        loadingAlbums = false;
        _changed();
      }
    }
  }

  Future<void> managePhotoAccess() async {
    if (blocked) return;
    if (platform == 'ios' && access == 'limited') {
      try {
        await bridge.call('managePhotoAccess');
        await refreshAlbums();
      } catch (e) {
        message = _error(e);
        _changed();
      }
    } else {
      await refreshAlbums(request: true);
    }
  }

  Future<void> selectAlbum(Album value) async {
    if (blocked || loadingAlbums) return;
    final generation = ++_libraryGeneration;
    loadingAlbums = true;
    _changed();
    try {
      final ids = List<String>.from(
        await bridge.call('albumPhotos', {'id': value.id}) ?? [],
      );
      if (generation != _libraryGeneration || _disposed) return;
      album = value;
      photos = ids;
      _resetResults();
      message = '${ids.length} fotos en ${value.name}.';
    } catch (e) {
      if (generation == _libraryGeneration) {
        message = _error(e);
        album = null;
        photos = [];
      }
    } finally {
      if (generation == _libraryGeneration && !_disposed) {
        loadingAlbums = false;
        _changed();
      }
    }
  }

  Future<void> search() async {
    if (!canSearch) return;
    ++_libraryGeneration;
    _resetResults();
    final run = ++_run;
    if (analytics?.enabled == true) {
      _searchId = randomUuid();
      _searchStartedAt = DateTime.now().millisecondsSinceEpoch;
      _searchClock = Stopwatch()..start();
      _planned = photos.length;
      analytics?.record('search_started', {
        'searchId': _searchId!,
        'photosPlanned': _planned,
      });
      if (analytics case final AnalyticsService service)
        service.reconcileSearch(_searchId);
    }
    busy = true;
    page = StepPage.analysis;
    searchReference = reference;
    searchFace = chosen;
    message = '';
    _changed();
    try {
      _permissionPending = true;
      _cancelStart = false;
      await requestNotifications(automatic: true);
      _permissionPending = false;
      if (_run != run) return;
      if (_cancelStart || _disposed) {
        busy = false;
        cancelled = true;
        page = StepPage.results;
        cancelling = false;
        message = 'Análisis cancelado.';
        _finishAnalytics('search_cancelled');
        _changed();
        return;
      }
      _setupMs = durationMs(_searchClock);
      _workerDispatched = true;
      final response = await bridge.call('search', {
        'runId': run,
        'ids': photos,
        'faces': [...examples.map((e) => e.face.id), chosen!.id],
        'context': _context(),
      });
      if (response is Map) {
        backgroundMode =
            response['backgroundMode'] as String? ?? backgroundMode;
        _changed();
      }
    } catch (e) {
      if (_run == run) {
        busy = false;
        cancelling = false;
        page = StepPage.results;
        message = _error(e);
        _finishAnalytics('search_failed');
        _changed();
      }
    } finally {
      _permissionPending = false;
    }
  }

  Future<void> cancel() async {
    if (!analysing || cancelling) return;
    _timeToCancelMs = _searchClock == null ? null : durationMs(_searchClock);
    _cancelClock = Stopwatch()..start();
    cancelling = true;
    message = 'Cancelando… Estamos terminando la foto en curso.';
    _changed();
    if (_permissionPending) {
      _cancelStart = true;
      return;
    }
    try {
      await bridge.call('cancel', {'runId': _run});
    } catch (e) {
      _cancelClock = null;
      _timeToCancelMs = null;
      cancelling = false;
      message = _error(e);
      _changed();
    }
  }

  void confirm(String id, bool belongs) {
    if (blocked) return;
    final index = reviews.indexWhere((r) => r.id == id);
    if (index < 0 || reviews[index].outcome == 'unreadable') return;
    final old = reviews[index];
    if (old.key != null) _feedback[old.key!] = belongs;
    reviews[index] = Review(id, belongs ? 'confirmed' : 'rejected', old.key);
    if (!belongs) selected.remove(id);
    _saveResultContext();
    _changed();
  }

  void confirmPending(Iterable<String> ids) {
    if (blocked) return;
    final chosen = ids.toSet();
    var changed = false;
    for (var i = 0; i < reviews.length; i++) {
      final review = reviews[i];
      if (!review.pending || !chosen.contains(review.id)) continue;
      if (review.key != null) _feedback[review.key!] = true;
      reviews[i] = Review(review.id, 'confirmed', review.key);
      changed = true;
    }
    if (!changed) return;
    _saveResultContext();
    _changed();
  }

  void toggle(String id) {
    if (blocked || !results.contains(id)) return;
    if (!selected.add(id)) selected.remove(id);
    _saveResultContext();
    _changed();
  }

  void toggleAll() {
    if (blocked) return;
    if (selected.length == results.length) {
      selected.clear();
    } else {
      selected.addAll(results);
    }
    _saveResultContext();
    _changed();
  }

  Future<void> share() async {
    final ids = results.where(selected.contains).toList();
    if (blocked || ids.isEmpty) return;
    try {
      await bridge.call('share', {'ids': ids});
    } catch (e) {
      message = _error(e);
      _changed();
    }
  }

  Future<void> settings({bool cloud = false}) async {
    try {
      await bridge.call(cloud ? 'cloudSettings' : 'settings');
    } catch (e) {
      message = _error(e);
      _changed();
    }
  }

  Future<void> acceptIncoming(bool asReference) async {
    if (blocked || incoming.isEmpty || (asReference && incoming.length != 1))
      return;
    final ids = incoming;
    incoming = [];
    _changed();
    if (asReference) {
      await useReference(ids.single);
    } else {
      addPhotos(ids);
      navigate(chosen == null ? StepPage.reference : StepPage.albums);
    }
  }

  void dismissIncoming() {
    incoming = [];
    _changed();
  }

  Future<void> clear() => _clearSession(StepPage.home);

  Future<void> newSearch() => _clearSession(StepPage.reference);

  Future<void> _clearSession(StepPage destination) async {
    if (blocked) return;
    ++_generation;
    ++_libraryGeneration;
    ++_run;
    busy = true;
    _changed();
    try {
      await bridge.call('clear');
    } catch (e) {
      busy = false;
      message = _error(e);
      _changed();
      return;
    }
    if (_disposed) return;
    reference = null;
    chosen = null;
    searchReference = null;
    searchFace = null;
    examples.clear();
    photos = [];
    album = null;
    albums = [];
    incoming = [];
    _feedback.clear();
    _resetResults();
    busy = false;
    page = destination;
    message = destination == StepPage.reference
        ? 'Elige una foto de referencia para tu nueva búsqueda.'
        : 'Datos de esta sesión eliminados. Tus fotos originales se conservan.';
    _changed();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart' hide SearchController;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'native_bridge.dart';
import 'search_controller.dart';
import 'photo_widgets.dart';
import 'app_theme.dart';
import 'ui_components.dart';
import 'analytics/service.dart';
import 'analytics/privacy_panel.dart';

void main() => runApp(const PersonasApp());

class PersonasApp extends StatelessWidget {
  final SearchController? controller;
  const PersonasApp({super.key, this.controller});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Personas',
    debugShowCheckedModeBanner: false,
    locale: const Locale('es'),
    supportedLocales: const [Locale('es'), Locale('en')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: personasTheme(Brightness.light),
    darkTheme: personasTheme(Brightness.dark),
    home: SearchPage(controller: controller),
  );
}

class SearchPage extends StatefulWidget {
  final SearchController? controller;
  const SearchPage({super.key, this.controller});
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> with WidgetsBindingObserver {
  late final SearchController c;
  AnalyticsService? analytics;
  bool incomingOpen = false, showDiscarded = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.controller?.analytics case final AnalyticsService service) {
      analytics = service;
    }
    if (widget.controller == null) {
      analytics = AnalyticsService();
      unawaited(analytics!.initialize());
    }
    c =
        widget.controller ??
        SearchController(NativePhotoBridge(), analytics: analytics);
    c.addListener(changed);
    if (widget.controller == null) unawaited(c.initialize());
  }

  void changed() {
    if (!mounted) return;
    setState(() {});
    if (c.page == StepPage.results)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) c.resultsPresented();
      });
    if (!c.blocked && c.incoming.isNotEmpty && !incomingOpen) {
      incomingOpen = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(importDialog());
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      analytics?.foreground();
      unawaited(analytics?.flush());
      unawaited(c.resume());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      analytics?.background();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    c.removeListener(changed);
    if (widget.controller == null) c.dispose();
    if (widget.controller == null) analytics?.dispose();
    super.dispose();
  }

  Future<void> analyticsDialog() async {
    final service = analytics;
    if (service == null) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        content: SingleChildScrollView(
          child: SizedBox(
            width: 480,
            child: AnalyticsPrivacyPanel(service: service),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> importDialog() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${c.incoming.length} fotos para esta búsqueda'),
        content: const SingleChildScrollView(
          child: Text(
            'Añade estas imágenes al conjunto. La referencia actual se conserva. Una sola foto también puede iniciar una referencia nueva.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          if (c.incoming.length == 1)
            TextButton(
              onPressed: () => Navigator.pop(context, 'reference'),
              child: const Text('Usar como referencia'),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'photos'),
            child: const Text('Añadir al conjunto'),
          ),
        ],
      ),
    );
    incomingOpen = false;
    if (!mounted) return;
    if (choice == null) {
      c.dismissIncoming();
    } else {
      await c.acceptIncoming(choice == 'reference');
    }
  }

  Future<void> back() async {
    if (c.canCancelPreparation) {
      c.cancelPreparation();
      c.back();
      return;
    }
    if (c.picking) return;
    if (c.blocked) {
      await cancelDialog();
    } else {
      c.back();
    }
  }

  Future<void> cancelDialog() async {
    if (c.cancelling) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Cancelar el análisis?'),
        content: const Text(
          'Podrás revisar las coincidencias que ya se encontraron.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Continuar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancelar análisis'),
          ),
        ],
      ),
    );
    if (confirmed == true) await c.cancel();
  }

  Future<void> clearDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Borrar esta sesión?'),
        content: const Text(
          'Se quitarán referencias y resultados. Tus fotos originales se conservan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Volver'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Borrar sesión'),
          ),
        ],
      ),
    );
    if (confirmed == true) await c.clear();
  }

  Future<void> cloud({bool reference = false, bool append = false}) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          c.platform == 'ios'
              ? 'Fotos de iCloud y otros proveedores'
              : 'Fotos de Google Fotos',
        ),
        content: SingleChildScrollView(
          child: Text(
            c.platform == 'ios'
                ? 'El selector muestra la fototeca y las imágenes de iCloud Fotos. Para Google Drive usa Archivos. Desde Google Fotos puedes compartir imágenes con Personas si has habilitado la extensión. Las fotos remotas necesitan conexión y descarga.'
                : 'Activa Google Fotos como proveedor del selector si tu teléfono lo permite. También puedes seleccionar fotos en Google Fotos y usar Compartir → Personas. Para Google Drive usa Archivos. Las fotos remotas necesitan conexión y descarga.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Volver'),
          ),
          if (c.platform != 'ios')
            TextButton(
              onPressed: () => Navigator.pop(context, 'settings'),
              child: const Text('Ajustes de nube'),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'pick'),
            child: const Text('Abrir selector'),
          ),
        ],
      ),
    );
    if (choice == 'settings') {
      await c.settings(cloud: true);
    }
    if (choice == 'pick') {
      if (reference) {
        await c.pickReference(append: append);
      } else {
        await c.pickPhotos();
      }
    }
  }

  void preview(String id) {
    unawaited(
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => ReviewPage(controller: c, id: id),
        ),
      ),
    );
  }

  Widget heading(String title, String subtitle) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 8),
      Text(subtitle),
    ],
  );
  Widget section(Widget child) => SliverPadding(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
    sliver: SliverToBoxAdapter(child: child),
  );
  Widget contextSummary() {
    final searching = c.page == StepPage.analysis || c.page == StepPage.results;
    final reference = searching
        ? c.searchReference ?? c.reference
        : c.reference;
    final face = searching ? c.searchFace ?? c.chosen : c.chosen;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (reference != null && face != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              width: 72,
              height: 72,
              child: NativePhoto(
                bridge: c.bridge,
                id: reference.image,
                crop: face.crop,
                label: 'Tu persona elegida',
              ),
            ),
          ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tu persona elegida',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (c.examples.isNotEmpty)
                Text('${c.examples.length + 1} referencias confirmadas'),
              Text(c.album?.name ?? 'Tus fotos elegidas'),
              Text('${c.photos.length} fotos donde buscar'),
            ],
          ),
        ),
      ],
    );
  }

  Widget backgroundNote() => BackgroundNote(
    mode: c.backgroundMode,
    enabled: c.notificationsEnabled,
    asking: c.askingNotifications,
    canAsk: c.canAskNotifications,
    onEnable: () => c.requestNotifications(),
  );

  Widget referencePicker() => Wrap(
    spacing: 12,
    runSpacing: 12,
    children: [
      OutlinedButton.icon(
        onPressed: c.blocked ? null : () => c.pickReference(),
        icon: const Icon(Icons.add_photo_alternate_outlined),
        label: Text(
          c.reference == null ? 'Elegir foto de referencia' : 'Cambiar foto',
        ),
      ),
      TextButton(
        onPressed: c.blocked ? null : () => cloud(reference: true),
        child: const Text('Fotos de la nube'),
      ),
    ],
  );

  List<Widget> content() {
    // Outgoing slivers remain alive during the step transition. Their lazy
    // builders must keep the data from that frame when the session changes.
    final reference = c.reference;
    final albums = List<Album>.of(c.albums);
    final results = c.results;
    final pending = c.pending;
    final discarded = c.reviews
        .where((r) => !r.accepted && !r.pending)
        .toList();
    switch (c.page) {
      case StepPage.home:
        return [
          section(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    Text(
                      'Personas',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Chip(
                      avatar: const Icon(Icons.lock_outline, size: 18),
                      label: const Text('En tu dispositivo'),
                      side: BorderSide.none,
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.surfaceContainer,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const HomeIntro(),
                const SizedBox(height: 28),
                Text(
                  'Así encuentras tus fotos',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const FlowStepRow(
                  1,
                  'Elige a tu persona',
                  'Toca su rostro en una foto de referencia.',
                ),
                const FlowStepRow(
                  2,
                  'Elige dónde buscar',
                  'Usa tu álbum o reúne las fotos que quieras.',
                ),
                const FlowStepRow(
                  3,
                  'Reúne tus favoritas',
                  'Revisa tus coincidencias y elige cuáles compartir.',
                ),
                const SizedBox(height: 20),
                const Text(
                  'Tus fotos se analizan en tu dispositivo, sin subirlas a servidores.',
                ),
              ],
            ),
          ),
          if (analytics != null)
            section(AnalyticsPrivacyPanel(service: analytics!)),
        ];
      case StepPage.reference:
        return [
          section(
            heading(
              reference == null
                  ? 'Una foto para empezar'
                  : '¿A quién quieres encontrar?',
              reference == null
                  ? 'Elige una referencia clara y toca a la persona que buscas.'
                  : 'Toca un rostro en tu foto o elige su recorte para continuar.',
            ),
          ),
          if (reference == null) section(referencePicker()),
          if (reference != null && reference.faces.isEmpty)
            section(
              EmptyMessage(
                'No encontramos un rostro utilizable',
                'Prueba una foto más clara, frontal o con la persona más cerca.',
                action: 'Elegir otra foto',
                onAction: () => c.pickReference(),
              ),
            ),
          if (reference != null)
            section(ReferenceView(controller: c, reference: reference)),
          if (reference != null)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverList.builder(
                itemCount: reference.faces.length,
                itemBuilder: (context, index) {
                  final face = reference.faces[index],
                      active = face.id == c.chosen?.id;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Semantics(
                      selected: active,
                      button: true,
                      label:
                          'Rostro ${index + 1}${active ? ', seleccionado' : ''}',
                      child: SelectionSurface(
                        selected: active,
                        radius: 16,
                        onTap: c.blocked ? null : () => c.choose(face),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 64,
                                height: 64,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: NativePhoto(
                                    bridge: c.bridge,
                                    id: reference.image,
                                    crop: face.crop,
                                    label: 'Rostro ${index + 1}',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(child: Text('Rostro ${index + 1}')),
                              SelectionMark(selected: active),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          if (reference != null) section(referencePicker()),
          if (c.chosen != null)
            section(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  contextSummary(),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: c.blocked
                        ? null
                        : () => c.pickReference(append: true),
                    child: const Text('Añadir otra referencia de esta persona'),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Una foto de la misma persona con distinta pose o iluminación puede ayudar.',
                  ),
                  ...c.examples.indexed.map(
                    (entry) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: SizedBox(
                        width: 56,
                        height: 56,
                        child: NativePhoto(
                          bridge: c.bridge,
                          id: entry.$2.reference.image,
                          crop: entry.$2.face.crop,
                        ),
                      ),
                      title: Text('Referencia adicional ${entry.$1 + 1}'),
                      trailing: IconButton(
                        tooltip: 'Quitar referencia ${entry.$1 + 1}',
                        onPressed: c.blocked
                            ? null
                            : () => c.removeExample(entry.$1),
                        icon: const Icon(Icons.close),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ];
      case StepPage.albums:
        return [
          section(
            heading(
              '¿Dónde quieres buscar?',
              'Elige tu álbum o reúne las fotos donde quieres buscar.',
            ),
          ),
          section(
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.tonal(
                  onPressed: () => c.pickPhotos(),
                  child: Text(
                    c.photos.isEmpty ? 'Elegir fotos' : 'Añadir más fotos',
                  ),
                ),
                OutlinedButton(
                  onPressed: () => c.pickPhotos(files: true),
                  child: const Text('Elegir desde Archivos'),
                ),
                TextButton(
                  onPressed: () => cloud(),
                  child: const Text('Fotos de la nube'),
                ),
                if (c.photos.isNotEmpty)
                  TextButton(
                    onPressed: c.clearPhotos,
                    child: const Text('Vaciar conjunto'),
                  ),
              ],
            ),
          ),
          section(const ScanSpeedNote()),
          if (c.backgroundMode.isNotEmpty) section(backgroundNote()),
          if (c.photos.isNotEmpty)
            section(
              Text(
                '${c.photos.length} fotos · ${c.album?.name ?? 'Selección individual'}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          if (c.access == 'none')
            section(
              EmptyMessage(
                'Permite ver tus álbumes',
                'Puedes seguir eligiendo fotos individuales sin dar acceso a la fototeca.',
                action: 'Permitir acceso a álbumes',
                onAction: () => c.refreshAlbums(request: true),
              ),
            ),
          if (c.access == 'none')
            section(
              TextButton(
                onPressed: () => c.settings(),
                child: const Text('Ajustes de acceso a fotos'),
              ),
            ),
          if (c.access == 'limited')
            section(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Acceso limitado: sólo podemos analizar las fotos autorizadas, no el álbum completo. Amplía tu selección o permite acceso completo desde Ajustes.',
                  ),
                  TextButton(
                    onPressed: c.managePhotoAccess,
                    child: const Text('Actualizar fotos autorizadas'),
                  ),
                ],
              ),
            ),
          if (c.loadingAlbums) section(const LinearProgressIndicator()),
          if (c.libraryError)
            section(
              EmptyMessage(
                'No pudimos consultar los álbumes',
                'Revisa el permiso o selecciona fotos individuales.',
                action: 'Volver a intentar',
                onAction: () => c.refreshAlbums(),
              ),
            ),
          if (!c.loadingAlbums && c.access != 'none' && c.albums.isEmpty)
            section(
              EmptyMessage(
                'No hay álbumes accesibles',
                'Elige fotos individuales o revisa las fotos autorizadas.',
                action: 'Elegir fotos',
                onAction: () => c.pickPhotos(),
              ),
            ),
          if (c.access != 'none')
            section(
              Wrap(
                spacing: 12,
                children: [
                  TextButton(
                    onPressed: () => c.refreshAlbums(),
                    child: const Text('Actualizar'),
                  ),
                  TextButton(
                    onPressed: () => c.settings(),
                    child: const Text('Ajustes de acceso'),
                  ),
                ],
              ),
            ),
          photoGrid(albums.length, (index) {
            final album = albums[index], active = c.album?.id == album.id;
            return Semantics(
              selected: active,
              button: true,
              label:
                  'Álbum ${album.name}, ${album.count} fotos${active ? ', seleccionado' : ''}',
              child: SelectionSurface(
                selected: active,
                onTap: c.loadingAlbums ? null : () => c.selectAlbum(album),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AspectRatio(
                      aspectRatio: 1.25,
                      child: NativePhoto(
                        bridge: c.bridge,
                        id: album.cover,
                        label: 'Portada de ${album.name}',
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            album.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text('${album.count} fotos'),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              SelectionMark(selected: active),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  active ? 'Seleccionado' : 'Elegir álbum',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }, album: true),
        ];
      case StepPage.analysis:
      case StepPage.results:
        return [
          section(
            heading(
              c.cancelling
                  ? 'Deteniendo la búsqueda'
                  : c.analysing
                  ? 'Encontrando tus momentos'
                  : c.cancelled
                  ? 'Búsqueda cancelada'
                  : 'Tus momentos, reunidos',
              c.cancelling
                  ? 'Estamos terminando la foto en curso. Conservarás los resultados encontrados.'
                  : c.analysing
                  ? 'Puedes cancelar y conservar lo que encontremos.'
                  : 'Revisa tus fotos y elige las que quieres compartir.',
            ),
          ),
          section(contextSummary()),
          if (c.analysing) ...[
            section(
              ScanProgress(processed: c.processed, total: c.photos.length),
            ),
            section(const ScanSpeedNote()),
            if (c.backgroundMode.isNotEmpty) section(backgroundNote()),
          ],
          section(
            Text(
              '${c.results.length} ${c.results.length == 1 ? 'coincidencia' : 'coincidencias'}',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ),
          if (c.analytics?.enabled == true && c.ratingAvailable)
            section(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '¿Qué tan acertados fueron los resultados?',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Text(
                    'Valoración subjetiva, no mide la precisión técnica del algoritmo.',
                  ),
                  Wrap(
                    spacing: 4,
                    children: [
                      for (var stars = 1; stars <= 5; stars++)
                        OutlinedButton(
                          onPressed: () => c.rateResults(stars),
                          child: Text('$stars ★'),
                        ),
                    ],
                  ),
                  TextButton(
                    onPressed: () => c.rateResults(null),
                    child: const Text('Omitir valoración'),
                  ),
                ],
              ),
            ),
          if (c.analytics?.enabled == true && !c.reviewSent)
            section(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Coincidencias confirmadas por ti: se envían sólo los totales de esta revisión, sin imágenes ni identificadores.',
                  ),
                  Text(
                    '${c.confirmedCount} confirmadas · ${c.rejectedCount} rechazadas',
                  ),
                  Text(
                    c.confirmedCount + c.rejectedCount == 0
                        ? 'Tasa confirmada: sin datos'
                        : 'Tasa confirmada: ${(100 * c.confirmedCount / (c.confirmedCount + c.rejectedCount)).toStringAsFixed(0)} %',
                  ),
                  TextButton(
                    onPressed: c.confirmedCount + c.rejectedCount == 0
                        ? null
                        : c.sendReviewTotals,
                    child: const Text('Enviar totales de revisión'),
                  ),
                ],
              ),
            ),
          if (c.cancelled)
            section(
              Text(
                '${c.processed} de ${c.photos.length} fotos procesadas. Estos resultados son parciales.',
              ),
            ),
          if (!c.analysing && c.results.isEmpty && c.pending.isEmpty)
            section(
              EmptyMessage(
                'No encontramos coincidencias',
                'Prueba otra referencia clara o cambia el conjunto de fotos.',
                action: 'Cambiar referencia',
                onAction: () => c.navigate(StepPage.reference),
              ),
            ),
          if (c.skipped > 0)
            section(
              TextButton.icon(
                onPressed: c.blocked ? null : () => c.navigate(StepPage.albums),
                icon: const Icon(Icons.info_outline),
                label: Text(
                  '${c.skipped} ${c.skipped == 1 ? 'foto no se pudo analizar' : 'fotos no se pudieron analizar'} · Revisar',
                ),
              ),
            ),
          if (!c.analysing)
            section(
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  if (c.results.isNotEmpty)
                    TextButton(
                      onPressed: c.toggleAll,
                      child: Text(
                        c.selected.length == c.results.length
                            ? 'Deseleccionar todas'
                            : 'Seleccionar todas',
                      ),
                    ),
                  PopupMenuButton<String>(
                    tooltip: 'Opciones de búsqueda',
                    onSelected: (choice) {
                      if (choice == 'reference')
                        unawaited(c.pickReference(append: true));
                      if (choice == 'album') c.navigate(StepPage.albums);
                      if (choice == 'repeat') unawaited(c.search());
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'reference',
                        child: Text('Mejorar con otra referencia'),
                      ),
                      const PopupMenuItem(
                        value: 'album',
                        child: Text('Cambiar álbum'),
                      ),
                      if (c.cancelled)
                        const PopupMenuItem(
                          value: 'repeat',
                          child: Text('Volver a buscar'),
                        ),
                    ],
                    icon: const Icon(Icons.more_horiz),
                  ),
                ],
              ),
            ),
          photoGrid(results.length, (index) => resultTile(results[index])),
          if (!c.analysing && c.pending.isNotEmpty) ...[
            section(
              heading(
                'Por revisar (${c.pending.length})',
                'Estas fotos se comparten sólo si confirmas que aparece la persona.',
              ),
            ),
            photoGrid(pending.length, (index) => reviewTile(pending[index])),
          ],
          if (!c.analysing && c.reviews.isNotEmpty) ...[
            section(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(),
                  Text(
                    'Revisar el análisis',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(
                    '${c.reviews.where((r) => r.outcome == 'noFace').length} sin rostros utilizables · ${c.reviews.where((r) => r.outcome == 'none').length} sin coincidencia suficiente · ${c.skipped} con error',
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      showDiscarded = !showDiscarded;
                    }),
                    child: Text(
                      showDiscarded
                          ? 'Ocultar descartadas'
                          : 'Revisar fotos descartadas',
                    ),
                  ),
                  TextButton(
                    onPressed: clearDialog,
                    child: const Text('Borrar datos de esta sesión'),
                  ),
                ],
              ),
            ),
            if (showDiscarded)
              photoGrid(discarded.length, (i) => reviewTile(discarded[i])),
          ],
        ];
    }
  }

  Widget photoGrid(
    int count,
    Widget Function(int) builder, {
    bool album = false,
  }) => SliverLayoutBuilder(
    builder: (context, constraints) {
      final large = MediaQuery.textScalerOf(context).scale(16) > 22;
      final columns = math.max(
        1,
        ((constraints.crossAxisExtent - 40 + 12) / (large ? 252 : 156)).floor(),
      );
      final width =
          (constraints.crossAxisExtent - 40 - (columns - 1) * 12) / columns;
      return SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        sliver: SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            mainAxisExtent: album
                ? width / 1.25 + (large ? 248 : 136)
                : width + (large ? 100 : 64),
          ),
          delegate: SliverChildBuilderDelegate(
            (_, i) => builder(i),
            childCount: count,
          ),
        ),
      );
    },
  );
  Widget resultTile(String id) {
    final selected = c.selected.contains(id);
    return SelectionSurface(
      key: ValueKey('result:$id'),
      selected: selected,
      child: Column(
        children: [
          Expanded(
            child: Semantics(
              button: true,
              key: ValueKey('result-preview:$id'),
              label: 'Coincidencia. Tocar para ver imagen completa',
              child: InkWell(
                onTap: () => preview(id),
                child: SizedBox.expand(
                  child: NativePhoto(bridge: c.bridge, id: id),
                ),
              ),
            ),
          ),
          CheckboxListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            controlAffinity: ListTileControlAffinity.leading,
            value: selected,
            onChanged: c.blocked ? null : (_) => c.toggle(id),
            title: Text(selected ? 'Elegida' : 'Elegir'),
          ),
        ],
      ),
    );
  }

  Widget reviewTile(Review review) => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: () => preview(review.id),
      child: Column(
        children: [
          Expanded(
            child: SizedBox.expand(
              child: NativePhoto(
                bridge: c.bridge,
                id: review.id,
                label: 'Foto ${review.label}. Tocar para revisar',
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              review.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    ),
  );

  Widget bottomBar() {
    final Widget action = c.canCancelPreparation
        ? OutlinedButton.icon(
            onPressed: c.cancelPreparation,
            icon: const Icon(Icons.close),
            label: const Text('Cancelar carga'),
          )
        : switch (c.page) {
            StepPage.home => FilledButton.icon(
              onPressed: () => c.navigate(StepPage.reference),
              icon: const Icon(Icons.person_search_outlined),
              label: const Text('Buscar a una persona'),
            ),
            StepPage.reference => FilledButton(
              onPressed: c.chosen == null || c.blocked
                  ? null
                  : () => c.photos.isEmpty
                        ? c.navigate(StepPage.albums)
                        : c.search(),
              child: Text(
                c.photos.isEmpty
                    ? 'Elegir álbum'
                    : 'Buscar de nuevo en ${c.photos.length} fotos',
              ),
            ),
            StepPage.albums => FilledButton(
              onPressed: c.canSearch ? () => c.search() : null,
              child: Text(
                c.album == null
                    ? 'Buscar en las fotos elegidas'
                    : 'Buscar en este álbum',
              ),
            ),
            StepPage.analysis => OutlinedButton(
              onPressed: c.cancelling ? null : cancelDialog,
              child: Text(c.cancelling ? 'Cancelando…' : 'Cancelar análisis'),
            ),
            StepPage.results => FilledButton.icon(
              onPressed: c.blocked || c.selected.isEmpty
                  ? null
                  : () => c.share(),
              icon: const Icon(Icons.ios_share_outlined),
              label: const Text('Compartir selección'),
            ),
          };
    return Material(
      elevation: 4,
      color: Theme.of(context).colorScheme.surface,
      child: MotionSize(
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (c.page == StepPage.results && c.selected.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Semantics(
                      label:
                          '${c.selected.length} ${c.selected.length == 1 ? 'foto seleccionada' : 'fotos seleccionadas'}',
                      child: ExcludeSemantics(
                        child: AnimatedSwitcher(
                          duration: PersonasMotion.duration(context),
                          layoutBuilder: (current, previous) => Stack(
                            alignment: Alignment.centerLeft,
                            children: [
                              ...previous.map(
                                (child) => ExcludeSemantics(child: child),
                              ),
                              if (current != null) current,
                            ],
                          ),
                          child: Text(
                            '${c.selected.length} ${c.selected.length == 1 ? 'foto' : 'fotos'}',
                            key: ValueKey(c.selected.length),
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                      ),
                    ),
                  ),
                if ((c.blocked && c.page == StepPage.reference) || c.picking)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: LinearProgressIndicator(),
                  ),
                action,
                if (c.page == StepPage.reference && c.chosen == null)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('Elige un rostro para continuar'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: c.page == StepPage.home && !c.blocked,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) unawaited(back());
    },
    child: Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: c.page == StepPage.home
            ? null
            : IconButton(
                tooltip: 'Volver',
                onPressed: back,
                icon: const Icon(Icons.arrow_back),
              ),
        title: c.page == StepPage.home
            ? null
            : Text(
                c.page == StepPage.reference
                    ? 'Tu persona'
                    : c.page == StepPage.albums
                    ? 'Tus fotos'
                    : 'Tus momentos',
              ),
        actions: [
          if (analytics != null)
            TextButton.icon(
              onPressed: analyticsDialog,
              icon: const Icon(Icons.privacy_tip_outlined),
              label: const Text('Analítica'),
            ),
        ],
      ),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: PersonasMotion.duration(context),
          switchInCurve: PersonasMotion.curve,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, .025),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.topCenter,
            children: [
              ...previous.map(
                (child) => IgnorePointer(child: ExcludeSemantics(child: child)),
              ),
              if (current != null) current,
            ],
          ),
          child: CustomScrollView(
            key: ValueKey(c.page),
            slivers: [
              if (c.page != StepPage.home)
                section(
                  SearchSteps(
                    step: c.page == StepPage.reference
                        ? 1
                        : c.page == StepPage.albums
                        ? 2
                        : 3,
                  ),
                ),
              ...content(),
              if (c.message.isNotEmpty)
                section(Text(c.message, key: const ValueKey('status-message'))),
              const SliverToBoxAdapter(child: SizedBox(height: 20)),
            ],
          ),
        ),
      ),
      bottomNavigationBar: bottomBar(),
    ),
  );
}

class ReferenceView extends StatelessWidget {
  final SearchController controller;
  final Reference reference;
  const ReferenceView({
    super.key,
    required this.controller,
    required this.reference,
  });
  @override
  Widget build(BuildContext context) {
    final c = controller;
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = math.min(
          380.0,
          constraints.maxWidth * reference.height / reference.width,
        );
        final scale = math.min(
          constraints.maxWidth / reference.width,
          height / reference.height,
        );
        final width = reference.width * scale,
            imageHeight = reference.height * scale;
        final left = (constraints.maxWidth - width) / 2,
            top = (height - imageHeight) / 2;
        return Semantics(
          label:
              'Referencia con ${reference.faces.length} rostros. Elige también con los botones de rostro.',
          child: GestureDetector(
            onTapUp: c.blocked
                ? null
                : (tap) {
                    final x = (tap.localPosition.dx - left) / width,
                        y = (tap.localPosition.dy - top) / imageHeight;
                    final faces =
                        reference.faces
                            .where(
                              (f) =>
                                  x >= f.x &&
                                  y >= f.y &&
                                  x <= f.x + f.width &&
                                  y <= f.y + f.height,
                            )
                            .toList()
                          ..sort(
                            (a, b) => (a.width * a.height).compareTo(
                              b.width * b.height,
                            ),
                          );
                    if (faces.isNotEmpty) c.choose(faces.first);
                  },
            child: SizedBox(
              height: height,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: NativePhoto(
                        bridge: c.bridge,
                        id: reference.image,
                        edge: 1600,
                        fit: BoxFit.contain,
                        label: 'Foto de referencia',
                      ),
                    ),
                    ...reference.faces.indexed.map((entry) {
                      final f = entry.$2, active = f.id == c.chosen?.id;
                      return Positioned(
                        left: left + width * f.x,
                        top: top + imageHeight * f.y,
                        width: width * f.width,
                        height: imageHeight * f.height,
                        child: IgnorePointer(
                          child: AnimatedContainer(
                            duration: PersonasMotion.duration(context),
                            curve: PersonasMotion.curve,
                            decoration: BoxDecoration(
                              border: Border.all(
                                width: active ? 4 : 2,
                                color: active
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.white,
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Align(
                              alignment: Alignment.topLeft,
                              child: ColoredBox(
                                color: const Color(0xcc292435),
                                child: Padding(
                                  padding: const EdgeInsets.all(2),
                                  child: Text(
                                    '${entry.$1 + 1}${active ? ' ✓' : ''}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class ReviewPage extends StatelessWidget {
  final SearchController controller;
  final String id;
  const ReviewPage({super.key, required this.controller, required this.id});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final c = controller, accepted = controller.results.contains(id);
      final review = c.reviews.where((r) => r.id == id).firstOrNull;
      return Scaffold(
        appBar: AppBar(title: const Text('Revisar fotografía')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              SizedBox(
                height: MediaQuery.sizeOf(context).height * .55,
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,
                  child: SizedBox.expand(
                    child: NativePhoto(
                      bridge: c.bridge,
                      id: id,
                      edge: 1600,
                      fit: BoxFit.contain,
                      label: 'Imagen completa para revisar',
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                review?.label ?? 'Fotografía',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              if (accepted)
                FilledButton(
                  onPressed: () => c.toggle(id),
                  child: Text(
                    c.selected.contains(id)
                        ? '✓ Seleccionada · Quitar'
                        : 'Seleccionar esta foto',
                  ),
                ),
              if (!accepted && review?.outcome != 'unreadable')
                FilledButton(
                  onPressed: () => c.confirm(id, true),
                  child: const Text('Sí, es esta persona'),
                ),
              if (review?.outcome != 'unreadable')
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: OutlinedButton(
                    onPressed: () => c.confirm(id, false),
                    child: const Text('No es esta persona'),
                  ),
                ),
              if (c.chosen != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      unawaited(c.useReference(id, append: true));
                    },
                    child: const Text('Usar como otra referencia'),
                  ),
                ),
              const SizedBox(height: 12),
              const Text('Después, elige el rostro de la misma persona.'),
            ],
          ),
        ),
      );
    },
  );
}

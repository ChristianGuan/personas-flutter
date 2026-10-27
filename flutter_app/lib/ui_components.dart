import 'package:flutter/material.dart';
import 'app_theme.dart';

class BackgroundNote extends StatelessWidget {
  final String mode;
  final bool enabled, asking, canAsk;
  final VoidCallback onEnable;
  const BackgroundNote({
    super.key,
    required this.mode,
    required this.enabled,
    required this.asking,
    required this.canAsk,
    required this.onEnable,
  });
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Puedes cambiar de app',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 6),
      Text(switch (mode) {
        'androidService' =>
          'El análisis seguirá en segundo plano. Puedes ver su progreso o cancelarlo desde la notificación.',
        'iosContinued' =>
          'iOS puede mantener el análisis en segundo plano. Si el sistema lo interrumpe, podrás revisar los resultados parciales al volver.',
        _ =>
          'iOS concede un tiempo limitado en segundo plano. Para un álbum grande, mantén Personas abierta; si se interrumpe, revisa lo encontrado al volver.',
      }),
      const SizedBox(height: 8),
      if (enabled)
        const Text('Te avisaremos cuando termine el análisis.')
      else ...[
        const Text(
          'Activa los avisos para saber cuándo termina. Puedes seguir buscando sin ellos.',
        ),
        TextButton.icon(
          onPressed: asking ? null : onEnable,
          icon: const Icon(Icons.notifications_outlined),
          label: Text(
            asking
                ? 'Solicitando permiso…'
                : canAsk
                ? 'Activar avisos'
                : 'Abrir ajustes de avisos',
          ),
        ),
      ],
    ],
  );
}

class MotionSize extends StatelessWidget {
  final Widget child;
  const MotionSize({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return AnimatedSize(
      duration: PersonasMotion.duration(context),
      curve: PersonasMotion.curve,
      alignment: Alignment.topCenter,
      child: child,
    );
  }
}

class HomeIntro extends StatelessWidget {
  const HomeIntro({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    final large = MediaQuery.textScalerOf(context).scale(16) > 22;
    return Container(
      padding: EdgeInsets.all(large ? 22 : 28),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.primaryContainer, colors.secondaryContainer],
        ),
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: colors.onPrimaryContainer),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Icon(
                Icons.photo_library_outlined,
                size: 36,
                color: colors.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Encuentra tus mejores momentos',
              style:
                  (large
                          ? theme.textTheme.headlineSmall
                          : theme.textTheme.headlineLarge)
                      ?.copyWith(color: colors.onPrimaryContainer),
            ),
            const SizedBox(height: 16),
            const Text(
              'Elige una foto, selecciona tu álbum y encuentra a quien buscas.',
            ),
          ],
        ),
      ),
    );
  }
}

class FlowStepRow extends StatelessWidget {
  final int number;
  final String title, subtitle;
  const FlowStepRow(this.number, this.title, this.subtitle, {super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: CircleAvatar(
              radius: 20,
              backgroundColor: colors.primaryContainer,
              foregroundColor: colors.onPrimaryContainer,
              child: Text('$number'),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(subtitle),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SearchSteps extends StatelessWidget {
  final int step;
  const SearchSteps({super.key, required this.step});
  static const labels = ['Tu persona', 'Tus fotos', 'Tus momentos'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    return Semantics(
      label: 'Paso $step de 3: ${labels[step - 1]}',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: List.generate(5, (index) {
                if (index.isOdd) {
                  return Expanded(
                    child: AnimatedContainer(
                      duration: PersonasMotion.duration(context),
                      curve: PersonasMotion.curve,
                      height: 2,
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      color: step > (index + 1) ~/ 2
                          ? colors.primary
                          : colors.outlineVariant,
                    ),
                  );
                }
                final number = index ~/ 2 + 1, complete = step > number;
                final active = step >= number;
                return AnimatedContainer(
                  duration: PersonasMotion.duration(context),
                  curve: PersonasMotion.curve,
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: active
                        ? colors.primary
                        : colors.surfaceContainerHighest,
                  ),
                  alignment: Alignment.center,
                  child: complete
                      ? Icon(Icons.check, size: 20, color: colors.onPrimary)
                      : Text(
                          '$number',
                          // The full accessible step label below scales with text.
                          textScaler: TextScaler.noScaling,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: active
                                ? colors.onPrimary
                                : colors.onSurfaceVariant,
                          ),
                        ),
                );
              }),
            ),
            const SizedBox(height: 8),
            Text('Paso $step de 3', style: theme.textTheme.labelLarge),
          ],
        ),
      ),
    );
  }
}

class SelectionSurface extends StatelessWidget {
  final bool selected;
  final double radius;
  final Widget child;
  final VoidCallback? onTap;
  const SelectionSurface({
    super.key,
    required this.selected,
    required this.child,
    this.radius = 20,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: PersonasMotion.duration(context),
      curve: PersonasMotion.curve,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: selected
            ? colors.primaryContainer.withValues(alpha: .45)
            : colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: selected ? colors.primary : colors.outlineVariant,
          width: selected ? 2 : 1,
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: onTap == null ? child : InkWell(onTap: onTap, child: child),
      ),
    );
  }
}

class SelectionMark extends StatelessWidget {
  final bool selected;
  const SelectionMark({super.key, required this.selected});
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: AnimatedSwitcher(
      duration: PersonasMotion.duration(context),
      switchInCurve: PersonasMotion.curve,
      child: Icon(
        selected ? Icons.check_circle : Icons.radio_button_unchecked,
        key: ValueKey(selected),
        color: selected
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

class ScanSpeedNote extends StatelessWidget {
  const ScanSpeedNote({super.key});
  static const message =
      'El primer escaneo de un álbum puede tardar un poco más. '
      'Si vuelves a buscar en las mismas fotos durante esta sesión, '
      'el reconocimiento puede ser más rápido.';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: colors.primary, width: 3)),
      ),
      child: Padding(
        padding: const EdgeInsets.only(left: 16, top: 4, bottom: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tu primer escaneo', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            const Text(message),
          ],
        ),
      ),
    );
  }
}

class ScanProgress extends StatelessWidget {
  final int processed, total;
  const ScanProgress({super.key, required this.processed, required this.total});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Buscando en tus fotos',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(color: colors.onPrimaryContainer),
          ),
          const SizedBox(height: 8),
          Semantics(
            liveRegion: true,
            child: Text(
              total > 0
                  ? 'Procesadas $processed de $total fotos'
                  : 'Preparando tus fotos…',
              style: TextStyle(color: colors.onPrimaryContainer),
            ),
          ),
          const SizedBox(height: 16),
          LinearProgressIndicator(
            value: total > 0 ? (processed / total).clamp(0.0, 1.0) : null,
            minHeight: 8,
            borderRadius: BorderRadius.circular(8),
            backgroundColor: colors.onPrimaryContainer.withValues(alpha: .12),
          ),
        ],
      ),
    );
  }
}

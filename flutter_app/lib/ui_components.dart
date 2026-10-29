import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'app_theme.dart';

class BackgroundNote extends StatelessWidget {
  final String mode;
  final bool enabled, asking, canAsk;
  final bool showHeading;
  final VoidCallback onEnable;
  const BackgroundNote({
    super.key,
    required this.mode,
    required this.enabled,
    required this.asking,
    required this.canAsk,
    required this.onEnable,
    this.showHeading = true,
  });
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (showHeading)
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
          'iOS concede un tiempo limitado en segundo plano. Para un álbum grande, mantén Halladin abierta; si se interrumpe, revisa lo encontrado al volver.',
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
    final width = MediaQuery.sizeOf(context).width;
    final size = width < 360 ? 29.0 : 34.0;
    return SizedBox(
      width: double.infinity,
      child: CustomPaint(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Column(
            children: [
              const HalladinBrand(),
              const SizedBox(height: 16),
              Semantics(
                header: true,
                label: 'Encuentra a tu gente',
                child: ExcludeSemantics(
                  child: DefaultTextStyle(
                    style: Theme.of(context).textTheme.headlineLarge!.copyWith(
                      fontSize: size,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1.2,
                      color: HalladinColors.ivory,
                      height: 1.15,
                      shadows: const [
                        Shadow(
                          color: Color(0x5500103c),
                          offset: Offset(0, 2),
                          blurRadius: 3,
                        ),
                      ],
                    ),
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 6,
                      children: [
                        HalladinGradientText(
                          'Encuentra',
                          gradient: HalladinSurfaces.goldLettering,
                        ),
                        const Text('a tu gente'),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Entre las fotos de tus eventos',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: HalladinColors.ivory,
                  fontSize: 20,
                  fontWeight: FontWeight.w400,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Brand lettering and an illustrated loupe, independent of the screen artwork.
class HalladinBrand extends StatelessWidget {
  final bool compact;
  const HalladinBrand({super.key, this.compact = false});
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Halladín',
    image: true,
    child: ExcludeSemantics(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final markSize = compact
              ? 64.0
              : constraints.maxWidth < 310
              ? 80.0
              : 96.0;
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox.square(
                dimension: markSize,
                child: Image.asset(
                  'assets/brand/lamp-gold-transparent.png',
                  fit: BoxFit.contain,
                  cacheWidth: 384,
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: HalladinGradientText(
                    'Halladín',
                    gradient: HalladinSurfaces.ivoryLettering,
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                      fontSize: compact ? 36 : 46,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1.8,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

Future<ui.Image>? _artworkFuture;
Future<ui.Image> get _sharedBrandArtwork =>
    _artworkFuture ??= _decodeBrandArtwork();
Future<ui.Image> _decodeBrandArtwork() async {
  final bytes = await rootBundle.load('assets/brand/home-reference.png');
  final codec = await ui.instantiateImageCodec(
    bytes.buffer.asUint8List(),
    targetWidth: 864,
  );
  final frame = await codec.getNextFrame();
  codec.dispose();
  return frame.image;
}

class FlowStepRow extends StatelessWidget {
  final int number;
  final String title, subtitle;
  const FlowStepRow(this.number, this.title, this.subtitle, {super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: HalladinSurfaces.card(colors),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: .5)),
        boxShadow: HalladinSurfaces.shadow(),
      ),
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
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
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
                          ? HalladinColors.turquoise
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
                        ? (complete
                              ? HalladinColors.turquoise
                              : HalladinColors.gold)
                        : colors.surfaceContainerHighest,
                  ),
                  alignment: Alignment.center,
                  child: complete
                      ? Icon(Icons.check, size: 20, color: HalladinColors.night)
                      : Text(
                          '$number',
                          // The full accessible step label below scales with text.
                          textScaler: TextScaler.noScaling,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: active
                                ? HalladinColors.night
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
        gradient: HalladinSurfaces.card(colors, selected: selected),
        boxShadow: HalladinSurfaces.shadow(raised: selected),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: selected
              ? (colors.brightness == Brightness.dark
                    ? HalladinColors.turquoise
                    : HalladinColors.tealInk)
              : colors.outlineVariant,
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
            ? (Theme.of(context).brightness == Brightness.dark
                  ? HalladinColors.turquoise
                  : HalladinColors.tealInk)
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
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.primaryContainer, colors.surfaceContainerLow],
        ),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: .6)),
        boxShadow: HalladinSurfaces.shadow(),
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

/// Native Flutter surfaces shared by Android and iOS.
class HalladinPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const HalladinPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      gradient: HalladinSurfaces.card(Theme.of(context).colorScheme),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(
        color: Theme.of(
          context,
        ).colorScheme.outlineVariant.withValues(alpha: .5),
      ),
      boxShadow: HalladinSurfaces.shadow(),
    ),
    child: child,
  );
}

class HalladinHeader extends StatelessWidget {
  final String title, subtitle;
  final int? step;
  const HalladinHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.step,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      gradient: HalladinSurfaces.hero,
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const HalladinBrand(compact: true),
        const SizedBox(height: 20),
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.headlineMedium?.copyWith(color: HalladinColors.ivory),
        ),
        if (step != null) ...[
          const SizedBox(height: 16),
          Theme(
            data: Theme.of(context).copyWith(
              textTheme: Theme.of(
                context,
              ).textTheme.apply(bodyColor: HalladinColors.ivory),
              colorScheme: Theme.of(context).colorScheme.copyWith(
                onSurfaceVariant: HalladinColors.ivory,
                surfaceContainerHighest: const Color(0xff748ebb),
                outlineVariant: const Color(0xff748ebb),
              ),
            ),
            child: SearchSteps(step: step!),
          ),
        ],
        const SizedBox(height: 12),
        Text(
          subtitle,
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(color: HalladinColors.ivory),
        ),
      ],
    ),
  );
}

/// Display only the photographic region of the supplied home artwork.
/// All text and controls are independent Flutter widgets.
class HalladinHomeArtwork extends StatefulWidget {
  const HalladinHomeArtwork({super.key});
  @override
  State<HalladinHomeArtwork> createState() => _HalladinHomeArtworkState();
}

class _HalladinHomeArtworkState extends State<HalladinHomeArtwork> {
  ui.Image? artwork;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final image = await _sharedBrandArtwork;
    if (!mounted) return;
    setState(() => artwork = image);
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Recuerdos compartidos en familia',
    image: true,
    child: AspectRatio(
      aspectRatio: 864 / 770,
      child: CustomPaint(painter: _CollagePainter(artwork)),
    ),
  );
}

class _CollagePainter extends CustomPainter {
  final ui.Image? image;
  _CollagePainter(this.image);
  @override
  void paint(Canvas canvas, Size size) {
    if (image == null) return;
    canvas.save();
    canvas.scale(size.width / 864, size.height / 770);
    canvas.translate(0, -490);
    // Preserve the actual overlapping photo frames while removing the mockup's background.
    final cards = [
      [
        const Offset(35, 615),
        const Offset(294, 545),
        const Offset(395, 961),
        const Offset(137, 1032),
      ],
      [
        const Offset(567, 550),
        const Offset(830, 606),
        const Offset(751, 971),
        const Offset(488, 915),
      ],
      [
        const Offset(36, 906),
        const Offset(298, 846),
        const Offset(364, 1137),
        const Offset(102, 1197),
      ],
      [
        const Offset(566, 885),
        const Offset(829, 943),
        const Offset(775, 1185),
        const Offset(512, 1127),
      ],
      [
        const Offset(181, 542),
        const Offset(654, 493),
        const Offset(720, 1193),
        const Offset(233, 1238),
      ],
    ];
    final source = Rect.fromLTWH(
      0,
      0,
      image!.width.toDouble(),
      image!.height.toDouble(),
    );
    for (final corners in cards) {
      final path = Path()..addPolygon(corners, true);
      canvas.drawShadow(path, const Color(0x550f1733), 18, false);
      canvas.save();
      canvas.clipPath(path);
      canvas.drawImageRect(
        image!,
        source,
        const Rect.fromLTWH(0, 0, 864, 1824),
        Paint()..filterQuality = FilterQuality.high,
      );
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CollagePainter oldDelegate) =>
      image != oldDelegate.image;
}

/// One continuous canvas behind both the heading and the overlapping photographs.
class HalladinLandingBackdrop extends CustomPainter {
  const HalladinLandingBackdrop();
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = HalladinColors.ivory);
    final boundary = size.height - size.width * .66;
    final background = Path()
      ..lineTo(size.width, 0)
      ..lineTo(size.width, boundary)
      ..quadraticBezierTo(
        size.width * .5,
        boundary + size.width * .3,
        0,
        boundary,
      )
      ..close();
    canvas.drawPath(
      background,
      Paint()
        ..shader = HalladinSurfaces.hero.createShader(
          Rect.fromLTWH(
            0,
            0,
            size.width,
            (boundary + size.width * .15).clamp(1, double.infinity).toDouble(),
          ),
        ),
    );
    canvas.save();
    canvas.clipPath(background);
    final wave = Path()
      ..moveTo(0, size.width * .13)
      ..quadraticBezierTo(
        size.width * .5,
        size.width * .45,
        size.width,
        size.width * .19,
      )
      ..lineTo(size.width, size.width * .33)
      ..quadraticBezierTo(
        size.width * .55,
        size.width * .6,
        0,
        size.width * .32,
      )
      ..close();
    canvas.drawPath(
      wave,
      Paint()
        ..shader = LinearGradient(
          colors: [
            HalladinColors.brightBlue.withValues(alpha: .07),
            HalladinColors.night.withValues(alpha: .04),
          ],
        ).createShader(rect),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant HalladinLandingBackdrop oldDelegate) => false;
}

/// Gradient glyphs with an independent, neutral shadow (the mask excludes shadows).
class HalladinGradientText extends StatelessWidget {
  final String text;
  final Gradient gradient;
  final TextStyle? style;
  final TextScaler? textScaler;
  const HalladinGradientText(
    this.text, {
    super.key,
    required this.gradient,
    this.style,
    this.textScaler,
  });
  @override
  Widget build(BuildContext context) {
    final base = (style ?? DefaultTextStyle.of(context).style).copyWith(
      shadows: const [],
    );
    return Stack(
      children: [
        ExcludeSemantics(
          child: Text(
            text,
            textScaler: textScaler,
            style: base.copyWith(
              color: Colors.transparent,
              shadows: const [
                Shadow(
                  color: Color(0x44000b2b),
                  offset: Offset(0, 2),
                  blurRadius: 3,
                ),
              ],
            ),
          ),
        ),
        ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: gradient.createShader,
          child: Text(
            text,
            textScaler: textScaler,
            style: base.copyWith(color: Colors.white),
          ),
        ),
      ],
    );
  }
}

/// Expandable sections never change consent or the search session when opened.
class HalladinDisclosure extends StatelessWidget {
  final String title, subtitle;
  final IconData icon;
  final Widget child;
  const HalladinDisclosure({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
  });
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerLow,
      elevation: 2,
      shadowColor: HalladinColors.night.withValues(alpha: .12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        maintainState: true,
        leading: Icon(icon, color: colors.primary),
        title: Text(title, style: Theme.of(context).textTheme.titleMedium),
        subtitle: Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
        shape: const Border(),
        collapsedShape: const Border(),
        children: [child],
      ),
    );
  }
}

class HalladinHowTo extends StatelessWidget {
  const HalladinHowTo({super.key});
  static const steps = [
    (
      'Elige a tu persona',
      'Toca su rostro en una foto de referencia.',
      Rect.fromLTWH(435, 510, 375, 290),
    ),
    (
      'Elige dónde buscar',
      'Usa tu álbum o reúne las fotos que quieras.',
      Rect.fromLTWH(470, 895, 335, 265),
    ),
    (
      'Reúne tus favoritas',
      'Revisa tus coincidencias y elige cuáles compartir.',
      Rect.fromLTWH(450, 1215, 360, 285),
    ),
  ];
  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final entry in steps.indexed)
        _HowToStep(
          number: entry.$1 + 1,
          title: entry.$2.$1,
          description: entry.$2.$2,
          artwork: entry.$2.$3,
        ),
      const Padding(
        padding: EdgeInsets.all(12),
        child: Text(
          'Tus fotos se analizan en tu dispositivo, sin subirlas a servidores.',
          textAlign: TextAlign.center,
        ),
      ),
    ],
  );
}

class _HowToStep extends StatelessWidget {
  final int number;
  final String title, description;
  final Rect artwork;
  const _HowToStep({
    required this.number,
    required this.title,
    required this.description,
    required this.artwork,
  });
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final colors = Theme.of(context).colorScheme;
      final stacked =
          constraints.maxWidth < 280 ||
          MediaQuery.textScalerOf(context).scale(16) > 22;
      final copy = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: HalladinSurfaces.action,
              border: Border.all(color: HalladinColors.gold),
              boxShadow: HalladinSurfaces.shadow(),
            ),
            child: Text(
              '$number',
              textScaler: TextScaler.noScaling,
              style: const TextStyle(
                color: HalladinColors.night,
                fontWeight: FontWeight.w800,
                fontSize: 24,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
      );
      final art = ExcludeSemantics(
        child: AspectRatio(
          aspectRatio: artwork.width / artwork.height,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(
                width: artwork.width,
                height: artwork.height,
                child: Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    Positioned(
                      left: -artwork.left,
                      top: -artwork.top,
                      width: 863,
                      height: 1823,
                      child: Image.asset(
                        'assets/brand/how-it-works-reference.png',
                        cacheWidth: 863,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      return Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: HalladinSurfaces.card(colors),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: colors.outlineVariant.withValues(alpha: .5),
          ),
          boxShadow: HalladinSurfaces.shadow(),
        ),
        child: stacked
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [copy, const SizedBox(height: 16), art],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(flex: 3, child: copy),
                  const SizedBox(width: 12),
                  Expanded(flex: 2, child: art),
                ],
              ),
      );
    },
  );
}

/// The existing reference picker, with a dimensional photo illustration and clear actions.
class HalladinReferencePicker extends StatelessWidget {
  final bool hasReference, enabled;
  final VoidCallback onPick, onCloud;
  const HalladinReferencePicker({
    super.key,
    required this.hasReference,
    required this.enabled,
    required this.onPick,
    required this.onCloud,
  });
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final actions = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: enabled ? onPick : null,
          style: FilledButton.styleFrom(
            minimumSize: const Size(48, 56),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(
                HalladinSurfaces.buttonRadius,
              ),
            ),
          ).copyWith(backgroundBuilder: HalladinSurfaces.actionLayer),
          icon: const Icon(Icons.add_photo_alternate_outlined),
          label: Text(
            hasReference ? 'Cambiar foto' : 'Elegir foto de referencia',
          ),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: enabled ? onCloud : null,
          icon: const Icon(Icons.cloud_outlined),
          label: const Text('Fotos de la nube'),
        ),
      ],
    );
    if (hasReference) return actions;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: HalladinSurfaces.card(colors),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: .7)),
        boxShadow: HalladinSurfaces.shadow(raised: true),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked =
                  constraints.maxWidth < 260 ||
                  MediaQuery.textScalerOf(context).scale(16) > 22;
              final copy = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '1. Foto de referencia',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Elige una referencia clara y toca a la persona que buscas.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              );
              return stacked
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Center(child: _ReferencePhotoIllustration()),
                        const SizedBox(height: 18),
                        copy,
                      ],
                    )
                  : Row(
                      children: [
                        const _ReferencePhotoIllustration(),
                        const SizedBox(width: 18),
                        Expanded(child: copy),
                      ],
                    );
            },
          ),
          const SizedBox(height: 24),
          actions,
        ],
      ),
    );
  }
}

class _ReferencePhotoIllustration extends StatelessWidget {
  const _ReferencePhotoIllustration();
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      width: 108,
      height: 118,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Container(
            width: 106,
            height: 106,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  HalladinColors.focusSurface,
                  HalladinColors.turquoise.withValues(alpha: .12),
                ],
              ),
            ),
          ),
          Transform.rotate(
            angle: -.16,
            child: Container(
              width: 70,
              height: 88,
              decoration: BoxDecoration(
                color: HalladinColors.focusSurface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: HalladinSurfaces.shadow(),
              ),
            ),
          ),
          Transform.rotate(
            angle: .07,
            child: Container(
              width: 72,
              height: 90,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xfffffff7), HalladinColors.ivory],
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: HalladinSurfaces.shadow(raised: true),
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.person_outline_rounded,
                    color: HalladinColors.night,
                    size: 40,
                  ),
                  SizedBox(height: 7),
                  SizedBox(
                    width: 32,
                    child: Divider(
                      height: 2,
                      thickness: 3,
                      color: HalladinColors.brightBlue,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 7,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: HalladinSurfaces.action,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: HalladinSurfaces.shadow(),
              ),
              child: const Icon(
                Icons.add_photo_alternate_rounded,
                size: 22,
                color: HalladinColors.night,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class HalladinSelectedReference extends StatelessWidget {
  final Widget photo;
  final int referenceCount;
  final VoidCallback? onChange;
  const HalladinSelectedReference({
    super.key,
    required this.photo,
    required this.referenceCount,
    required this.onChange,
  });
  @override
  Widget build(BuildContext context) => HalladinPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '1. Foto de referencia',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            final portrait = SizedBox(
              width: 112,
              height: 120,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        color: Colors.white,
                        border: Border.all(
                          color: HalladinColors.turquoise,
                          width: 2,
                        ),
                        boxShadow: HalladinSurfaces.shadow(raised: true),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(17),
                        child: photo,
                      ),
                    ),
                  ),
                  Positioned(
                    right: -5,
                    bottom: -5,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: HalladinColors.turquoise,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        size: 19,
                        color: HalladinColors.night,
                      ),
                    ),
                  ),
                ],
              ),
            );
            final details = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Persona seleccionada',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  referenceCount > 1
                      ? '$referenceCount referencias confirmadas'
                      : 'Tu persona elegida',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: onChange,
                  icon: const Icon(Icons.photo_outlined),
                  label: const Text('Cambiar foto'),
                ),
              ],
            );
            return constraints.maxWidth < 285 ||
                    MediaQuery.textScalerOf(context).scale(16) > 22
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(child: portrait),
                      const SizedBox(height: 18),
                      details,
                    ],
                  )
                : Row(
                    children: [
                      portrait,
                      const SizedBox(width: 20),
                      Expanded(child: details),
                    ],
                  );
          },
        ),
      ],
    ),
  );
}

/// Shared secondary actions: a framed blue accent, neutral depth and optional guidance.
class HalladinSecondaryAction extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool compact;
  const HalladinSecondaryAction({
    super.key,
    required this.title,
    required this.icon,
    required this.onPressed,
    this.subtitle,
    this.compact = false,
  });
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    final enabled = onPressed != null,
        dark = theme.brightness == Brightness.dark;
    final ink = enabled
        ? colors.onSurface
        : colors.onSurfaceVariant.withValues(alpha: .6);
    if (compact)
      return TextButton.icon(
        onPressed: onPressed,
        icon: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: enabled
                ? (dark ? HalladinColors.deepBlue : HalladinColors.focusSurface)
                : colors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20, color: ink),
        ),
        label: Text(title),
        style:
            TextButton.styleFrom(
              foregroundColor: ink,
              disabledForegroundColor: ink,
              textStyle: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              minimumSize: const Size(48, 52),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              elevation: enabled ? 1 : 0,
              shadowColor: HalladinColors.night.withValues(alpha: .13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(
                  color: enabled
                      ? colors.primary.withValues(alpha: .25)
                      : colors.outlineVariant,
                ),
              ),
            ).copyWith(
              backgroundBuilder: (context, states, child) => DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: enabled
                        ? colors.primary.withValues(alpha: .25)
                        : colors.outlineVariant,
                  ),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: dark
                        ? [HalladinColors.darkCard, HalladinColors.darkSurface]
                        : [const Color(0xffedf3ff), const Color(0xfffffdf1)],
                  ),
                ),
                child: child,
              ),
            ),
      );
    final badge = Container(
      padding: EdgeInsets.all(compact ? 6 : 12),
      decoration: BoxDecoration(
        color: enabled
            ? (dark ? HalladinColors.deepBlue : HalladinColors.focusSurface)
            : colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(compact ? 10 : 16),
      ),
      child: Icon(icon, size: compact ? 20 : 26, color: ink),
    );
    final titleWidget = Text(
      title,
      style: theme.textTheme.titleMedium?.copyWith(
        fontSize: compact ? 15 : 17,
        fontWeight: FontWeight.w700,
        color: ink,
        height: 1.3,
      ),
    );
    final description = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        titleWidget,
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(
            subtitle!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: enabled ? colors.onSurfaceVariant : ink,
              height: 1.45,
            ),
          ),
        ],
      ],
    );
    final stacked = !compact && MediaQuery.textScalerOf(context).scale(16) > 22;
    return TextButton(
      onPressed: onPressed,
      style:
          TextButton.styleFrom(
            foregroundColor: colors.primary,
            backgroundColor: colors.surfaceContainerLow,
            minimumSize: Size(48, compact ? 52 : 64),
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 14 : 18,
              vertical: compact ? 10 : 18,
            ),
            elevation: enabled ? 2 : 0,
            shadowColor: HalladinColors.night.withValues(alpha: .13),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ).copyWith(
            backgroundBuilder: (context, states, child) => DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: enabled
                      ? (dark
                            ? HalladinColors.brightBlue.withValues(alpha: .55)
                            : HalladinColors.night.withValues(alpha: .22))
                      : colors.outlineVariant,
                ),
                gradient: enabled
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: dark
                            ? [
                                HalladinColors.darkCard,
                                HalladinColors.darkSurface,
                              ]
                            : [
                                const Color(0xfff2f6ff),
                                const Color(0xfffffdf1),
                              ],
                      )
                    : null,
              ),
              child: child,
            ),
          ),
      child: stacked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [badge, const SizedBox(height: 12), description],
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                badge,
                SizedBox(width: compact ? 10 : 14),
                Expanded(child: description),
                if (!compact) ...[
                  const SizedBox(width: 10),
                  Icon(Icons.arrow_forward_rounded, size: 20, color: ink),
                ],
              ],
            ),
    );
  }
}

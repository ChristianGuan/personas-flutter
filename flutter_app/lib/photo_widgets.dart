import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'native_bridge.dart';
import 'app_theme.dart';

// Two visible image requests at a time; disposed queued cells never decode.
class _ImageSlots {
  int active = 0;
  final waiting = <Completer<void>>[];
  Future<void> acquire() async {
    if (active < 2) {
      active++;
      return;
    }
    final waiter = Completer<void>();
    waiting.add(waiter);
    await waiter.future;
  }

  void release() {
    if (waiting.isNotEmpty) {
      waiting.removeAt(0).complete();
    } else {
      active--;
    }
  }
}

final _slots = _ImageSlots();

class NativePhoto extends StatefulWidget {
  final PhotoBridge bridge;
  final String id, label;
  final int edge;
  final List<double>? crop;
  final BoxFit fit;
  const NativePhoto({
    super.key,
    required this.bridge,
    required this.id,
    this.label = 'Fotografía',
    this.edge = 512,
    this.crop,
    this.fit = BoxFit.cover,
  });
  @override
  State<NativePhoto> createState() => _NativePhotoState();
}

class _NativePhotoState extends State<NativePhoto> {
  Uint8List? bytes;
  bool failed = false;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  @override
  void didUpdateWidget(covariant NativePhoto old) {
    super.didUpdateWidget(old);
    if (old.id != widget.id ||
        old.edge != widget.edge ||
        old.crop.toString() != widget.crop.toString()) {
      bytes = null;
      failed = false;
      unawaited(load());
    }
  }

  Future<void> load() async {
    final request = ++generation;
    final id = widget.id, edge = widget.edge, crop = widget.crop;
    await _slots.acquire();
    try {
      if (!mounted || request != generation) return;
      final result = await widget.bridge.call<Uint8List>('image', {
        'id': id,
        'edge': edge,
        if (crop != null) 'crop': crop,
      });
      if (mounted && request == generation)
        setState(() {
          bytes = result;
          failed = result == null;
        });
    } catch (_) {
      if (mounted && request == generation)
        setState(() {
          failed = true;
        });
    } finally {
      _slots.release();
    }
  }

  @override
  Widget build(BuildContext context) => Semantics(
    image: bytes != null,
    label: widget.label,
    value: bytes != null
        ? null
        : failed
        ? 'Foto no disponible'
        : 'Cargando foto',
    child: ExcludeSemantics(
      child: AnimatedSwitcher(
        duration: PersonasMotion.duration(context),
        switchInCurve: PersonasMotion.curve,
        layoutBuilder: (current, previous) => Stack(
          fit: StackFit.expand,
          children: [...previous, if (current != null) current],
        ),
        child: bytes != null
            ? Image.memory(
                bytes!,
                key: ValueKey('image:$generation'),
                fit: widget.fit,
                gaplessPlayback: true,
              )
            : ColoredBox(
                key: ValueKey('placeholder:$generation:$failed'),
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      failed ? 'Foto no disponible' : 'Cargando foto…',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
      ),
    ),
  );
}

class EmptyMessage extends StatelessWidget {
  final String title, message;
  final String? action;
  final VoidCallback? onAction;
  const EmptyMessage(
    this.title,
    this.message, {
    super.key,
    this.action,
    this.onAction,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(message),
        if (action != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: OutlinedButton(onPressed: onAction, child: Text(action!)),
          ),
      ],
    ),
  );
}

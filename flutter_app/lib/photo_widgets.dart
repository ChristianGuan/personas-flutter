import 'dart:async';
import 'dart:collection';
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

/// Encoded thumbnails only. Full-size previews never consume this budget.
/// The bridge owns the cache lifetime; nothing is written to disk.
class ThumbnailCache {
  final int maxBytes, maxEntries;
  final _entries = LinkedHashMap<String, Uint8List>();
  int _byteCount = 0;
  ThumbnailCache({this.maxBytes = 8 * 1024 * 1024, this.maxEntries = 64});

  Uint8List? get(String key) {
    final bytes = _entries.remove(key);
    if (bytes != null) _entries[key] = bytes;
    return bytes;
  }

  void put(String key, Uint8List bytes) {
    final previous = _entries.remove(key);
    if (previous != null) _byteCount -= previous.lengthInBytes;
    if (bytes.lengthInBytes > maxBytes || maxEntries <= 0) return;
    _entries[key] = bytes;
    _byteCount += bytes.lengthInBytes;
    while (_byteCount > maxBytes || _entries.length > maxEntries) {
      _byteCount -= _entries.remove(_entries.keys.first)!.lengthInBytes;
    }
  }
}

final _thumbnailCaches = Expando<ThumbnailCache>();
void clearThumbnailCache(PhotoBridge bridge) => _thumbnailCaches[bridge] = null;
ThumbnailCache _cacheFor(PhotoBridge bridge) =>
    _thumbnailCaches[bridge] ??= ThumbnailCache();

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
    if (old.bridge != widget.bridge ||
        old.id != widget.id ||
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
    final bridge = widget.bridge;
    final cache = edge <= 512 ? _cacheFor(bridge) : null;
    final cacheKey = '$id|$edge|${crop?.join(',')}';
    final cached = cache?.get(cacheKey);
    if (cached != null) {
      bytes = cached;
      return;
    }
    await _slots.acquire();
    try {
      if (!mounted || request != generation) return;
      final result = await bridge.call<Uint8List>('image', {
        'id': id,
        'edge': edge,
        if (crop != null) 'crop': crop,
      });
      if (result != null) cache?.put(cacheKey, result);
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
                filterQuality: widget.crop == null
                    ? FilterQuality.low
                    : FilterQuality.high,
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

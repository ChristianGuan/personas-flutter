import 'package:flutter/services.dart';

typedef Json = Map<String, dynamic>;
Json jsonMap(dynamic value) => Map<String, dynamic>.from(value as Map);

class Album {
  final String id, name, cover;
  final int count;
  const Album(this.id, this.name, this.cover, this.count);
  Json toJson() => {'id': id, 'name': name, 'cover': cover, 'count': count};
  factory Album.fromJson(dynamic value) {
    final j = jsonMap(value);
    return Album(j['id'], j['name'], j['cover'], j['count']);
  }
}

class Face {
  final String id;
  final double x, y, width, height;
  const Face(this.id, this.x, this.y, this.width, this.height);
  Json toJson() => {'id': id, 'x': x, 'y': y, 'width': width, 'height': height};
  factory Face.fromJson(dynamic value) {
    final j = jsonMap(value);
    return Face(
      j['id'],
      (j['x'] as num).toDouble(),
      (j['y'] as num).toDouble(),
      (j['width'] as num).toDouble(),
      (j['height'] as num).toDouble(),
    );
  }
  List<double> get crop => [x, y, width, height];
}

class Reference {
  final String token, image;
  final int width, height;
  final List<Face> faces;
  const Reference(this.token, this.image, this.width, this.height, this.faces);
  Json toJson() => {
    'token': token,
    'image': image,
    'width': width,
    'height': height,
    'faces': faces.map((f) => f.toJson()).toList(),
  };
  factory Reference.fromJson(dynamic value) {
    final j = jsonMap(value);
    return Reference(
      j['token'],
      j['image'],
      j['width'],
      j['height'],
      (j['faces'] as List).map(Face.fromJson).toList(),
    );
  }
}

abstract class PhotoBridge {
  Stream<Json> get events;
  Future<T?> call<T>(String method, [Json? arguments]);
}

class NativePhotoBridge implements PhotoBridge {
  static const methods = MethodChannel('co.local.personas/photos');
  static const eventChannel = EventChannel('co.local.personas/events');
  @override
  late final Stream<Json> events = eventChannel.receiveBroadcastStream().map(
    jsonMap,
  );
  @override
  Future<T?> call<T>(String method, [Json? arguments]) =>
      methods.invokeMethod<T>(method, arguments);
  Future<Uint8List?> image(String id, int edge, [List<double>? crop]) =>
      call<Uint8List>('image', {
        'id': id,
        'edge': edge,
        if (crop != null) 'crop': crop,
      });
}

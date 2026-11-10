import 'package:latlong2/latlong.dart';

class CyclingRoutePoint {
  const CyclingRoutePoint({
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    required this.altitudeMeters,
    required this.accuracyMeters,
    required this.speedMetersPerSecond,
  });

  final double latitude;
  final double longitude;
  final DateTime timestamp;
  final double altitudeMeters;
  final double accuracyMeters;
  final double speedMetersPerSecond;

  LatLng get position => LatLng(latitude, longitude);

  factory CyclingRoutePoint.fromJson(Map<String, dynamic> json) {
    final latitude = json['latitude'];
    final longitude = json['longitude'];
    final altitude = json['altitudeMeters'];
    final accuracy = json['accuracyMeters'];
    final speed = json['speedMetersPerSecond'];
    final timestamp = json['timestamp'];
    if (latitude is! num ||
        longitude is! num ||
        altitude is! num ||
        accuracy is! num ||
        speed is! num ||
        timestamp is! String) {
      throw const FormatException('Un punto de ruta tiene datos inválidos.');
    }

    final point = CyclingRoutePoint(
      latitude: latitude.toDouble(),
      longitude: longitude.toDouble(),
      timestamp: DateTime.parse(timestamp),
      altitudeMeters: altitude.toDouble(),
      accuracyMeters: accuracy.toDouble(),
      speedMetersPerSecond: speed.toDouble(),
    );
    if (!point.latitude.isFinite ||
        point.latitude < -90 ||
        point.latitude > 90 ||
        !point.longitude.isFinite ||
        point.longitude < -180 ||
        point.longitude > 180 ||
        !point.altitudeMeters.isFinite ||
        !point.accuracyMeters.isFinite ||
        point.accuracyMeters < 0 ||
        !point.speedMetersPerSecond.isFinite) {
      throw const FormatException('Un punto de ruta está fuera de rango.');
    }
    return point;
  }

  Map<String, Object> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        'timestamp': timestamp.toIso8601String(),
        'altitudeMeters': altitudeMeters,
        'accuracyMeters': accuracyMeters,
        'speedMetersPerSecond': speedMetersPerSecond,
      };
}

class CyclingActivity {
  const CyclingActivity({
    required this.id,
    required this.startedAt,
    required this.endedAt,
    required this.distanceMeters,
    required this.route,
  });

  final String id;
  final DateTime startedAt;
  final DateTime endedAt;
  final double distanceMeters;
  final List<CyclingRoutePoint> route;

  Duration get duration => endedAt.difference(startedAt);

  double get averageSpeedKmh =>
      duration.inSeconds <= 0 ? 0 : distanceMeters / duration.inSeconds * 3.6;

  factory CyclingActivity.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final startedAt = json['startedAt'];
    final endedAt = json['endedAt'];
    final distanceMeters = json['distanceMeters'];
    final route = json['route'];
    if (id is! String ||
        id.isEmpty ||
        startedAt is! String ||
        endedAt is! String ||
        distanceMeters is! num ||
        route is! List) {
      throw const FormatException(
          'El recorrido guardado tiene datos inválidos.');
    }

    final startedAtDate = DateTime.parse(startedAt);
    final endedAtDate = DateTime.parse(endedAt);
    final distance = distanceMeters.toDouble();
    if (!distance.isFinite ||
        distance < 0 ||
        endedAtDate.isBefore(startedAtDate)) {
      throw const FormatException(
          'El recorrido guardado tiene fechas inválidas.');
    }

    return CyclingActivity(
      id: id,
      startedAt: startedAtDate,
      endedAt: endedAtDate,
      distanceMeters: distance,
      route: route.map((point) {
        if (point is! Map<String, dynamic>) {
          throw const FormatException(
              'El recorrido contiene un punto inválido.');
        }
        return CyclingRoutePoint.fromJson(point);
      }).toList(growable: false),
    );
  }

  Map<String, Object> toJson() => {
        'id': id,
        'startedAt': startedAt.toIso8601String(),
        'endedAt': endedAt.toIso8601String(),
        'distanceMeters': distanceMeters,
        'route': route.map((point) => point.toJson()).toList(growable: false),
      };
}

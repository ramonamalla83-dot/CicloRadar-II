import 'package:latlong2/latlong.dart';

import '../models/cycling_activity.dart';

class CyclingRouteRecorder {
  CyclingRouteRecorder(this.startedAt);

  static const double _maximumAccuracyMeters = 40;
  static const double _minimumPointSpacingMeters = 2;
  static const double _maximumSpeedMetersPerSecond = 45;
  static const int _maximumRoutePoints = 50000;

  final DateTime startedAt;
  final List<CyclingRoutePoint> _points = [];
  double _distanceMeters = 0;

  List<CyclingRoutePoint> get points => List.unmodifiable(_points);
  double get distanceMeters => _distanceMeters;

  bool addPoint(CyclingRoutePoint point) {
    if (point.timestamp.isBefore(startedAt) ||
        !point.latitude.isFinite ||
        point.latitude < -90 ||
        point.latitude > 90 ||
        !point.longitude.isFinite ||
        point.longitude < -180 ||
        point.longitude > 180 ||
        !point.accuracyMeters.isFinite ||
        point.accuracyMeters < 0 ||
        point.accuracyMeters > _maximumAccuracyMeters ||
        !point.speedMetersPerSecond.isFinite ||
        point.speedMetersPerSecond < 0 ||
        point.speedMetersPerSecond > _maximumSpeedMetersPerSecond ||
        !point.altitudeMeters.isFinite ||
        _points.length >= _maximumRoutePoints) {
      return false;
    }

    final previous = _points.isEmpty ? null : _points.last;
    if (previous != null) {
      if (!point.timestamp.isAfter(previous.timestamp)) return false;
      final segmentMeters = const Distance().as(
        LengthUnit.Meter,
        previous.position,
        point.position,
      );
      if (!segmentMeters.isFinite ||
          segmentMeters < _minimumPointSpacingMeters) {
        return false;
      }

      final elapsedSeconds =
          point.timestamp.difference(previous.timestamp).inSeconds;
      final maximumPlausibleDistance =
          _maximumSpeedMetersPerSecond * elapsedSeconds +
              previous.accuracyMeters +
              point.accuracyMeters;
      if (segmentMeters > maximumPlausibleDistance) return false;
      _distanceMeters += segmentMeters;
    }

    _points.add(point);
    return true;
  }

  CyclingActivity finish(DateTime endedAt) {
    if (endedAt.isBefore(startedAt) ||
        _points.length < 2 ||
        endedAt.isBefore(_points.last.timestamp) ||
        _distanceMeters < 50) {
      throw const FormatException(
        'El recorrido es demasiado corto o no tiene suficientes puntos GPS válidos.',
      );
    }
    return CyclingActivity(
      id: startedAt.microsecondsSinceEpoch.toString(),
      startedAt: startedAt,
      endedAt: endedAt,
      distanceMeters: _distanceMeters,
      route: points,
    );
  }
}

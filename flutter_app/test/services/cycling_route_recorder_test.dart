import 'package:cicloradar/models/cycling_activity.dart';
import 'package:cicloradar/services/cycling_route_recorder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CyclingRouteRecorder', () {
    final startedAt = DateTime.utc(2025, 1, 1);

    CyclingRoutePoint point({
      required double latitude,
      required DateTime timestamp,
      double accuracy = 5,
      double speed = 5,
      double longitude = -3,
    }) {
      return CyclingRoutePoint(
        latitude: latitude,
        longitude: longitude,
        timestamp: timestamp,
        altitudeMeters: 100,
        accuracyMeters: accuracy,
        speedMetersPerSecond: speed,
      );
    }

    test('filters inaccurate, out-of-range, and duplicate GPS points', () {
      final recorder = CyclingRouteRecorder(startedAt);

      expect(
        recorder.addPoint(
          point(latitude: 40, timestamp: startedAt, accuracy: 41),
        ),
        isFalse,
      );
      expect(
        recorder.addPoint(point(latitude: 91, timestamp: startedAt)),
        isFalse,
      );
      expect(
        recorder.addPoint(point(latitude: 40, timestamp: startedAt)),
        isTrue,
      );
      expect(
        recorder.addPoint(
          point(
            latitude: 40.001,
            timestamp: startedAt.add(const Duration(seconds: 10)),
          ),
        ),
        isTrue,
      );
      expect(
        recorder.addPoint(
          point(
            latitude: 40.001,
            timestamp: startedAt.add(const Duration(seconds: 10)),
          ),
        ),
        isFalse,
      );
      expect(recorder.points, hasLength(2));
    });

    test('rejects implausible jumps and finishes valid rides', () {
      final recorder = CyclingRouteRecorder(startedAt);
      expect(
        recorder.addPoint(point(latitude: 40, timestamp: startedAt)),
        isTrue,
      );
      expect(
        recorder.addPoint(
          point(
            latitude: 40.01,
            timestamp: startedAt.add(const Duration(seconds: 10)),
          ),
        ),
        isFalse,
      );
      expect(
        recorder.addPoint(
          point(
            latitude: 40.001,
            timestamp: startedAt.add(const Duration(seconds: 10)),
          ),
        ),
        isTrue,
      );

      final activity = recorder.finish(
        startedAt.add(const Duration(minutes: 1)),
      );
      expect(activity.route, hasLength(2));
      expect(activity.distanceMeters, greaterThan(50));
      expect(activity.averageSpeedKmh, greaterThan(0));
    });

    test('rejects a ride that ends before its last GPS point', () {
      final recorder = CyclingRouteRecorder(startedAt);
      recorder.addPoint(point(latitude: 40, timestamp: startedAt));
      final lastPointTime = startedAt.add(const Duration(seconds: 10));
      recorder.addPoint(point(latitude: 40.001, timestamp: lastPointTime));

      expect(
        () => recorder.finish(startedAt.add(const Duration(seconds: 5))),
        throwsFormatException,
      );
    });
  });
}

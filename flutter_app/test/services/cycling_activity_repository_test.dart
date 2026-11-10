import 'dart:io';

import 'package:cicloradar/models/cycling_activity.dart';
import 'package:cicloradar/services/cycling_activity_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temporaryDirectory;
  late CyclingActivityRepository repository;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'cicloradar-routes-',
    );
    repository = CyclingActivityRepository(directory: temporaryDirectory);
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  CyclingActivity activity(String id, DateTime startedAt) {
    return CyclingActivity(
      id: id,
      startedAt: startedAt,
      endedAt: startedAt.add(const Duration(minutes: 10)),
      distanceMeters: 2500,
      route: [
        CyclingRoutePoint(
          latitude: 40,
          longitude: -3,
          timestamp: startedAt,
          altitudeMeters: 100,
          accuracyMeters: 5,
          speedMetersPerSecond: 5,
        ),
        CyclingRoutePoint(
          latitude: 40.001,
          longitude: -3,
          timestamp: startedAt.add(const Duration(minutes: 10)),
          altitudeMeters: 110,
          accuracyMeters: 5,
          speedMetersPerSecond: 5,
        ),
      ],
    );
  }

  test('saves and reloads routes sorted by date, newest first', () async {
    final older = activity('older', DateTime.utc(2025, 1, 1));
    final newer = activity('newer', DateTime.utc(2025, 1, 2));
    await repository.save(newer);
    await repository.save(older);

    final loaded = await repository.loadAll();
    expect(loaded.map((ride) => ride.id), ['newer', 'older']);
    expect(loaded.first.route, hasLength(2));
    expect(loaded.first.distanceMeters, newer.distanceMeters);
  });
}

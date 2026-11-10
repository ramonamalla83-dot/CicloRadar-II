import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:health/health.dart';

import '../models/cycling_activity.dart';

class HealthSyncException implements Exception {
  const HealthSyncException(this.message);

  final String message;

  @override
  String toString() => message;
}

class HealthSyncService {
  HealthSyncService({Health? health}) : _health = health ?? Health();

  static const List<HealthDataType> _activityTypes = [
    HealthDataType.WORKOUT,
    HealthDataType.WORKOUT_ROUTE,
  ];

  final Health _health;
  bool _isConfigured = false;

  bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  String get providerName => switch (defaultTargetPlatform) {
        TargetPlatform.android => 'Health Connect',
        TargetPlatform.iOS => 'Apple Health',
        _ => 'servicio de salud',
      };

  Future<void> connect() async {
    _ensureSupported();
    await _configure();

    if (defaultTargetPlatform == TargetPlatform.android) {
      final status = await _health.getHealthConnectSdkStatus();
      if (status != HealthConnectSdkStatus.sdkAvailable) {
        await _health.installHealthConnect();
        throw const HealthSyncException(
          'Instala o actualiza Health Connect y vuelve a conectar.',
        );
      }
    }

    try {
      final granted = await _health.requestAuthorization(
        _activityTypes,
        permissions: List.filled(_activityTypes.length, HealthDataAccess.WRITE),
      );
      if (!granted) {
        throw HealthSyncException(
          'No se concedieron permisos para escribir actividades en '
          '$providerName.',
        );
      }
    } on PlatformException catch (error) {
      throw HealthSyncException(
        'No se pudo autorizar $providerName (${error.code}): '
        '${error.message ?? 'error desconocido'}.',
      );
    }
  }

  Future<void> exportActivity(CyclingActivity activity) async {
    _ensureSupported();
    await _configure();
    if (activity.route.length < 2 || activity.distanceMeters < 50) {
      throw const HealthSyncException(
        'El recorrido no tiene suficientes puntos GPS para exportarlo.',
      );
    }

    var builderId = '';
    var workoutCreated = false;
    try {
      builderId = await _health.startWorkoutRoute();
      for (var start = 0; start < activity.route.length; start += 100) {
        final end = (start + 100).clamp(0, activity.route.length);
        final points = activity.route.sublist(start, end).map((point) {
          return WorkoutRouteLocation(
            latitude: point.latitude,
            longitude: point.longitude,
            timestamp: point.timestamp,
            altitude: point.altitudeMeters,
            horizontalAccuracy: point.accuracyMeters,
            speed: point.speedMetersPerSecond,
          );
        }).toList(growable: false);
        if (!await _health.insertWorkoutRouteData(
          builderId: builderId,
          locations: points,
        )) {
          throw const HealthSyncException(
            'El proveedor rechazó los puntos GPS del recorrido.',
          );
        }
      }

      final workoutUuid = await _health.writeWorkoutDataUUID(
        activityType: HealthWorkoutActivityType.BIKING,
        start: activity.startedAt,
        end: activity.endedAt,
        totalDistance: activity.distanceMeters.round(),
        totalDistanceUnit: HealthDataUnit.METER,
        title: 'CicloRadar',
        recordingMethod: RecordingMethod.manual,
      );
      if (workoutUuid == null || workoutUuid.isEmpty) {
        throw const HealthSyncException(
          'El proveedor no confirmó el registro del entrenamiento.',
        );
      }
      workoutCreated = true;

      await _health.finishWorkoutRoute(
        builderId: builderId,
        workoutUuid: workoutUuid,
      );
    } on PlatformException catch (error) {
      if (builderId.isNotEmpty && !workoutCreated) {
        await _discardRouteBuilder(builderId);
      }
      throw HealthSyncException(
        'No se pudo exportar la ruta a $providerName (${error.code}): '
        '${error.message ?? 'error desconocido'}.',
      );
    } on HealthSyncException {
      if (builderId.isNotEmpty && !workoutCreated) {
        await _discardRouteBuilder(builderId);
      }
      rethrow;
    }
  }

  Future<void> _configure() async {
    if (_isConfigured) return;
    await _health.configure();
    _isConfigured = true;
  }

  void _ensureSupported() {
    if (!isSupported) {
      throw const HealthSyncException(
        'La sincronización con servicios de salud está disponible en Android '
        'e iOS, no en la versión web.',
      );
    }
  }

  Future<void> _discardRouteBuilder(String builderId) async {
    try {
      await _health.discardWorkoutRoute(builderId);
    } on PlatformException catch (error) {
      throw HealthSyncException(
        'No se pudo descartar una exportación incompleta (${error.code}): '
        '${error.message ?? 'error desconocido'}.',
      );
    }
  }
}

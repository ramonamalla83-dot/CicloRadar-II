import 'dart:async';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  // Coordenadas iniciales por defecto (centro urbano ciclista)
  static const LatLng defaultLocation = LatLng(40.416775, -3.703790);

  StreamSubscription<Position>? _positionStream;

  /// Verifica y solicita permisos de geolocalización al usuario
  Future<bool> requestLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return false;
    }

    return true;
  }

  /// Obtiene la posición actual de alta precisión GPS
  Future<LatLng> getCurrentLocation() async {
    try {
      final hasPermission = await requestLocationPermission();
      if (!hasPermission) return defaultLocation;

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
      return LatLng(position.latitude, position.longitude);
    } catch (_) {
      return defaultLocation;
    }
  }

  Future<LatLng?> getVerifiedCurrentLocation() async {
    try {
      final hasPermission = await requestLocationPermission();
      if (!hasPermission) return null;

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
      return LatLng(position.latitude, position.longitude);
    } on TimeoutException {
      return null;
    } on LocationServiceDisabledException {
      return null;
    } on PermissionDeniedException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Inicia el flujo de actualizaciones continuas de posición
  void startTracking(
    void Function(Position position) onLocationChanged,
  ) {
    _positionStream?.cancel();
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5, // Cada 5 metros
      ),
    ).listen(
      (Position position) {
        onLocationChanged(position);
      },
      onError: (_) {},
    );
  }

  void stopTracking() {
    _positionStream?.cancel();
    _positionStream = null;
  }
}

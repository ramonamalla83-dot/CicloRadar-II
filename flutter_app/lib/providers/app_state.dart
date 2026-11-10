import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/alarm_preset.dart';
import '../models/cycling_activity.dart';
import '../models/cyclist.dart';
import '../models/map_layer.dart';
import '../models/sos_contact.dart';
import '../services/advanced_night_mode_service.dart';
import '../services/audio_alarm_service.dart';
import '../services/cycling_activity_repository.dart';
import '../services/cycling_route_recorder.dart';
import '../services/firebase_config.dart';
import '../services/health_sync_service.dart';
import '../services/location_service.dart';
import '../services/safety_report_service.dart';
import '../services/sos_push_service.dart';
import '../models/safety_report.dart';

class AppState extends ChangeNotifier with WidgetsBindingObserver {
  // Perfil del ciclista
  String _userName = 'Alejandro';
  String _userInitials = 'AL';
  String _bikeModel = 'Cannondale Topstone Gravel';
  String _phoneNumber = '';
  String _bikeType = 'MTB';
  String _experienceLevel = 'Intermedio';
  bool _isRegistered = false;
  bool _isReady = false;
  List<SosContact> _emergencyContacts = [];
  String _emergencyMessage =
      '¡Emergencia ciclista! Necesito asistencia en mi ubicación GPS.';

  // Pantalla activa (0: Inicio, 1: Mapa, 2: Comunidad, 3: Contactos SOS, 4: Perfil)
  int _currentScreenIndex = 0;

  // Ubicación del usuario
  LatLng _userLocation = LocationService.defaultLocation;
  bool _isLoadingLocation = true;

  // Capas y Modos del Mapa (Día / Streets por defecto según AGENTS.md)
  MapLayerType _activeLayer = MapLayerType.streets;
  MapLayerType _preferredMapLayer = MapLayerType.streets;
  bool _automaticNightModeEnabled = true;
  bool _advancedNightModeEnabled = false;
  String _advancedNightModeStatus = 'Desactivado';
  Timer? _nightModeTimer;
  bool _heatmapEnabled = true;
  bool _trackingEnabled = true; // false = Modo Sigilo / Invisible
  bool _sosAlertNotificationsEnabled = false;
  bool _hasVerifiedUserLocation = false;
  double _historicalSpeedSampleSumKmh = 0;
  int _historicalSpeedSampleCount = 0;
  int _persistedHistoricalSpeedSampleCount = 0;
  Future<void>? _historicalSpeedWrite;
  String? _historicalSpeedStatus;
  bool _isDisposed = false;
  bool _healthSyncEnabled = false;
  bool _healthSyncInProgress = false;
  String? _healthSyncStatus;
  List<CyclingActivity> _cyclingActivities = [];
  final Set<String> _healthSyncedActivityIds = {};
  CyclingRouteRecorder? _activeCyclingRoute;
  String? _cyclingActivityStatus;
  String? _sosPushStatus;
  String? _activeSosId;
  Timer? _presenceTimer;
  bool _presencePublishInProgress = false;
  DateTime? _lastPresencePublishedAt;
  LatLng? _lastPresencePosition;

  // Alarmas del sistema (Radar iOS por defecto según AGENTS.md)
  AlarmPreset _activeAlarm = AlarmPreset.radarIos;

  // Estado del Sistema SOS
  bool _isCountingDown = false;
  int _countdownSeconds = 5;
  Timer? _countdownTimer;
  bool _isEmergencyActive = false;

  // Alerta comunitaria entrante (simulada o recibida)
  Cyclist? _incomingEmergency;

  // Ciclistas de la comunidad y corredores
  List<Cyclist> _communityCyclists = [];
  List<HeatmapCorridor> _corridors = [];
  List<SafetyReport> _safetyReports = [];
  String? _safetyReportsStatus =
      'Reportes comunitarios disponibles al configurar Firebase.';
  StreamSubscription<List<SafetyReport>>? _safetyReportsSubscription;
  Timer? _safetyReportExpiryTimer;
  SafetyReportRepository? _safetyReportRepository;

  late final AudioAlarmService _audioService = AudioAlarmService();
  final LocationService _locationService = LocationService();
  final CyclingActivityRepository _cyclingActivityRepository =
      CyclingActivityRepository();
  final HealthSyncService _healthSyncService = HealthSyncService();
  final SosPushService _sosPushService = SosPushService();
  final AdvancedNightModeService _nightModeService =
      const AdvancedNightModeService();
  late final DateTime Function() _localClock;
  late final Brightness Function() _platformBrightness;

  // Getters
  String get userName => _userName;
  String get userInitials => _userInitials;
  String get bikeModel => _bikeModel;
  String get phoneNumber => _phoneNumber;
  String get bikeType => _bikeType;
  String get experienceLevel => _experienceLevel;
  bool get isRegistered => _isRegistered;
  bool get isReady => _isReady;
  List<SosContact> get emergencyContacts =>
      List.unmodifiable(_emergencyContacts);
  String get emergencyContact => _emergencyContacts.isEmpty
      ? 'Sin configurar'
      : _emergencyContacts.first.phone;
  String get emergencyMessage => _emergencyMessage;
  int get currentScreenIndex => _currentScreenIndex;
  LatLng get userLocation => _userLocation;
  bool get isLoadingLocation => _isLoadingLocation;
  bool get hasVerifiedUserLocation => _hasVerifiedUserLocation;
  bool get isRecordingCyclingActivity => _activeCyclingRoute != null;
  bool get cyclingRouteRecordingSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  DateTime? get cyclingActivityStartedAt => _activeCyclingRoute?.startedAt;
  double get activeCyclingDistanceMeters =>
      _activeCyclingRoute?.distanceMeters ?? 0;
  List<CyclingRoutePoint> get activeCyclingRoute =>
      _activeCyclingRoute?.points ?? const [];
  List<CyclingActivity> get cyclingActivities =>
      List.unmodifiable(_cyclingActivities);
  String? get cyclingActivityStatus => _cyclingActivityStatus;
  bool get healthSyncSupported => _healthSyncService.isSupported;
  bool get healthSyncEnabled => _healthSyncEnabled;
  bool get healthSyncInProgress => _healthSyncInProgress;
  String? get healthSyncStatus => _healthSyncStatus;
  String get healthProviderName => _healthSyncService.providerName;
  bool isCyclingActivitySynced(String id) =>
      _healthSyncedActivityIds.contains(id);
  static const double referenceCyclingSpeedKmh = 16.7;
  double get historicalAverageSpeedKmh => _historicalSpeedSampleCount == 0
      ? referenceCyclingSpeedKmh
      : _historicalSpeedSampleSumKmh / _historicalSpeedSampleCount;
  bool get hasHistoricalSpeedData => _historicalSpeedSampleCount > 0;
  String? get historicalSpeedStatus => _historicalSpeedStatus;
  MapLayerType get activeLayer => _activeLayer;
  MapLayerType get preferredMapLayer => _preferredMapLayer;
  bool get automaticNightModeEnabled => _automaticNightModeEnabled;
  bool get advancedNightModeEnabled => _advancedNightModeEnabled;
  String get advancedNightModeStatus => _advancedNightModeStatus;

  bool get heatmapEnabled => _heatmapEnabled;
  bool get trackingEnabled => _trackingEnabled;
  bool get sosPushConfigured => _sosPushService.isConfigured;
  bool get sosAlertNotificationsEnabled => _sosAlertNotificationsEnabled;
  String? get sosPushStatus => _sosPushStatus;
  AlarmPreset get activeAlarm => _activeAlarm;
  bool get isCountingDown => _isCountingDown;
  int get countdownSeconds => _countdownSeconds;
  bool get isEmergencyActive => _isEmergencyActive;
  Cyclist? get incomingEmergency => _incomingEmergency;
  List<Cyclist> get communityCyclists => _communityCyclists;
  List<HeatmapCorridor> get corridors => _corridors;
  List<SafetyReport> get safetyReports => List.unmodifiable(_safetyReports);
  String? get safetyReportsStatus => _safetyReportsStatus;
  bool get safetyReportsAvailable => _safetyReportRepository != null;

  AppState() {
    _localClock = DateTime.now;
    _platformBrightness =
        () => WidgetsBinding.instance.platformDispatcher.platformBrightness;
    WidgetsBinding.instance.addObserver(this);
    _nightModeTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => refreshNightMode(),
    );
    refreshNightMode(notify: false);
    _initApp();
  }

  AppState.forTesting({
    DateTime Function()? localClock,
    Brightness platformBrightness = Brightness.light,
  })  : _localClock = localClock ?? (() => DateTime(2026, 1, 1, 12)),
        _platformBrightness = (() => platformBrightness),
        _isReady = true {
    refreshNightMode(notify: false);
  }

  Future<void> _initApp() async {
    final preferences = await SharedPreferences.getInstance();
    _loadPreferences(preferences);
    _loadHistoricalSpeed(preferences);
    _healthSyncEnabled = preferences.getBool('health.syncEnabled') ?? false;
    _healthSyncedActivityIds
        .addAll(preferences.getStringList('health.syncedActivityIds') ?? []);
    await _loadCyclingActivities();
    _isReady = true;
    notifyListeners();

    await _audioService.init();
    try {
      await _sosPushService.initialize(
        onIncomingSos: _handleIncomingPush,
        onError: (message) {
          _sosPushStatus = message;
          notifyListeners();
        },
      );
    } on SosPushException catch (error) {
      _sosPushStatus = error.message;
      notifyListeners();
    }
    _startSafetyReportUpdates();

    await refreshLocation();
    _corridors = CommunityData.getSampleCorridors(_userLocation);
    _communityCyclists = CommunityData.getInitialCyclists(_userLocation);
    notifyListeners();

    // Iniciar rastreo continuo
    _locationService.startTracking((position) {
      _userLocation = LatLng(position.latitude, position.longitude);
      _hasVerifiedUserLocation = true;
      _recordHistoricalSpeed(position.speed);
      _recordCyclingRoutePoint(position);
      if (_sosAlertNotificationsEnabled &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        unawaited(_publishSosPresence());
      }
      notifyListeners();
    });
    if (_sosAlertNotificationsEnabled && _sosPushService.isInitialized) {
      _startPresenceUpdates();
    }
  }

  Future<void> _loadCyclingActivities() async {
    if (!cyclingRouteRecordingSupported) return;
    try {
      _cyclingActivities = await _cyclingActivityRepository.loadAll();
    } on FormatException catch (error) {
      _cyclingActivityStatus = error.message;
    } on FileSystemException catch (error) {
      _cyclingActivityStatus =
          'No se pudieron cargar los recorridos guardados: ${error.message}';
    } on MissingPluginException {
      _cyclingActivityStatus =
          'El almacenamiento local de recorridos no está disponible.';
    }
  }

  void _recordCyclingRoutePoint(Position position) {
    final recorder = _activeCyclingRoute;
    if (recorder == null) return;
    recorder.addPoint(
      CyclingRoutePoint(
        latitude: position.latitude,
        longitude: position.longitude,
        timestamp: position.timestamp,
        altitudeMeters: position.altitude,
        accuracyMeters: position.accuracy,
        speedMetersPerSecond: position.speed,
      ),
    );
  }

  Future<void> startCyclingActivity() async {
    if (!cyclingRouteRecordingSupported) {
      throw StateError(
        'El registro de recorridos está disponible en Android e iOS.',
      );
    }
    if (!_hasVerifiedUserLocation) {
      throw StateError(
        'Espera a que el GPS confirme tu ubicación antes de iniciar el recorrido.',
      );
    }
    if (_activeCyclingRoute != null) {
      throw StateError('Ya hay un recorrido en curso.');
    }

    _activeCyclingRoute = CyclingRouteRecorder(DateTime.now());
    _cyclingActivityStatus =
        'Recorrido en curso; mantén CicloRadar abierto para registrar el GPS.';
    notifyListeners();
  }

  void cancelCyclingActivity() {
    if (_activeCyclingRoute == null) return;
    _activeCyclingRoute = null;
    _cyclingActivityStatus = 'Se descartó el recorrido en curso.';
    notifyListeners();
  }

  Future<CyclingActivity> finishCyclingActivity() async {
    final recorder = _activeCyclingRoute;
    if (recorder == null) {
      throw StateError('No hay un recorrido en curso.');
    }

    final activity = recorder.finish(DateTime.now());
    _activeCyclingRoute = null;
    _cyclingActivityStatus = 'Guardando recorrido en este dispositivo...';
    notifyListeners();

    try {
      await _cyclingActivityRepository.save(activity);
    } on Exception catch (error) {
      _activeCyclingRoute = recorder;
      _cyclingActivityStatus =
          'No se pudo guardar el recorrido: $error';
      notifyListeners();
      rethrow;
    }
    _cyclingActivities = [
      activity,
      ..._cyclingActivities.where((entry) => entry.id != activity.id),
    ];
    _cyclingActivityStatus = 'Recorrido guardado en este dispositivo.';
    notifyListeners();

    if (_healthSyncEnabled) {
      await exportCyclingActivity(activity.id);
    }
    return activity;
  }

  Future<void> setHealthSyncEnabled(bool enabled) async {
    if (!enabled) {
      final preferences = await SharedPreferences.getInstance();
      if (!await preferences.setBool('health.syncEnabled', false)) {
        throw StateError(
          'No se pudo guardar la preferencia de sincronización.',
        );
      }
      _healthSyncEnabled = false;
      _healthSyncStatus = 'Sincronización con $healthProviderName desactivada.';
      notifyListeners();
      return;
    }

    _healthSyncInProgress = true;
    _healthSyncStatus = 'Solicitando permisos de $healthProviderName...';
    notifyListeners();
    try {
      await _healthSyncService.connect();
      final preferences = await SharedPreferences.getInstance();
      if (!await preferences.setBool('health.syncEnabled', true)) {
        throw StateError(
          'No se pudo guardar la preferencia de sincronización.',
        );
      }
      _healthSyncEnabled = true;
      _healthSyncStatus =
          'Conectado. Los próximos recorridos se sincronizarán automáticamente; '
          'los anteriores se pueden exportar manualmente.';
    } on HealthSyncException catch (error) {
      _healthSyncStatus = error.message;
      rethrow;
    } finally {
      _healthSyncInProgress = false;
      notifyListeners();
    }
  }

  Future<void> exportCyclingActivity(String activityId) async {
    if (!_healthSyncEnabled) {
      throw const HealthSyncException(
        'Conecta primero Apple Health o Health Connect.',
      );
    }
    if (_healthSyncedActivityIds.contains(activityId)) return;
    if (!_healthSyncInProgress) {
      _healthSyncInProgress = true;
      notifyListeners();
    }

    try {
      final activity = _cyclingActivities.firstWhere(
        (entry) => entry.id == activityId,
        orElse: () => throw StateError('No se encontró el recorrido guardado.'),
      );
      await _healthSyncService.exportActivity(activity);
      final updatedIds = {..._healthSyncedActivityIds, activityId};
      final preferences = await SharedPreferences.getInstance();
      if (!await preferences.setStringList(
        'health.syncedActivityIds',
        updatedIds.toList(growable: false),
      )) {
        throw StateError(
          'La actividad se exportó, pero no se pudo guardar su estado de sincronización.',
        );
      }
      _healthSyncedActivityIds
        ..clear()
        ..addAll(updatedIds);
      _healthSyncStatus = 'Recorrido exportado a $healthProviderName.';
    } on HealthSyncException catch (error) {
      _healthSyncStatus = error.message;
      rethrow;
    } finally {
      _healthSyncInProgress = false;
      notifyListeners();
    }
  }

  void _loadHistoricalSpeed(SharedPreferences preferences) {
    final storedHistory = preferences.getString('activity.speedHistory');
    if (storedHistory == null) return;

    final Object? decoded;
    try {
      decoded = jsonDecode(storedHistory);
    } on FormatException {
      _historicalSpeedStatus =
          'El historial de velocidad guardado no es válido y se ignoró.';
      return;
    }
    if (decoded is! Map<String, dynamic> ||
        decoded['sumKmh'] is! num ||
        decoded['sampleCount'] is! int) {
      _historicalSpeedStatus =
          'El historial de velocidad guardado no es válido y se ignoró.';
      return;
    }
    final sum = (decoded['sumKmh'] as num).toDouble();
    final count = decoded['sampleCount'] as int;
    if (!sum.isFinite ||
        count < 0 ||
        (count == 0 && sum != 0) ||
        (count > 0 && (sum < count * 4 || sum > count * 50))) {
      _historicalSpeedStatus =
          'El historial de velocidad guardado no es válido y se ignoró.';
      return;
    }
    _historicalSpeedSampleSumKmh = sum;
    _historicalSpeedSampleCount = count;
    _persistedHistoricalSpeedSampleCount = count;
  }

  void _recordHistoricalSpeed(double speedMetersPerSecond) {
    final speedKmh = speedMetersPerSecond * 3.6;
    if (!speedKmh.isFinite || speedKmh < 4 || speedKmh > 50) return;

    _historicalSpeedSampleSumKmh += speedKmh;
    _historicalSpeedSampleCount++;
    if (_historicalSpeedSampleCount - _persistedHistoricalSpeedSampleCount >=
        10) {
      unawaited(_persistHistoricalSpeed());
    }
  }

  Future<void> _persistHistoricalSpeed() async {
    if (_historicalSpeedWrite != null) {
      await _historicalSpeedWrite;
      if (_persistedHistoricalSpeedSampleCount < _historicalSpeedSampleCount) {
        await _persistHistoricalSpeed();
      }
      return;
    }
    final write = _writeHistoricalSpeedSnapshot();
    _historicalSpeedWrite = write;
    try {
      await write;
    } finally {
      _historicalSpeedWrite = null;
    }
  }

  Future<void> _writeHistoricalSpeedSnapshot() async {
    final sampleCount = _historicalSpeedSampleCount;
    try {
      final preferences = await SharedPreferences.getInstance();
      final saved = await preferences.setString(
        'activity.speedHistory',
        jsonEncode({
          'sumKmh': _historicalSpeedSampleSumKmh,
          'sampleCount': sampleCount,
        }),
      );
      if (!saved) {
        _historicalSpeedStatus =
            'No se pudo guardar el promedio de velocidad GPS.';
        if (!_isDisposed) notifyListeners();
        return;
      }
      _persistedHistoricalSpeedSampleCount = sampleCount;
      _historicalSpeedStatus = null;
    } on PlatformException catch (error) {
      _historicalSpeedStatus =
          'No se pudo guardar el promedio de velocidad GPS (${error.code}).';
      if (!_isDisposed) notifyListeners();
    } on MissingPluginException {
      _historicalSpeedStatus =
          'El almacenamiento local de velocidad no está disponible.';
      if (!_isDisposed) notifyListeners();
    }
  }

  void _startSafetyReportUpdates() {
    if (!FirebaseConfig.isCoreConfigured) {
      _safetyReportsStatus =
          'Reportes comunitarios en tiempo real pendientes de configurar Firebase.';
      return;
    }
    if (!_sosPushService.isFirebaseInitialized) {
      _safetyReportsStatus =
          'Reportes comunitarios no disponibles: Firebase no se inicializó.';
      return;
    }

    final repository = FirestoreSafetyReportService();
    _safetyReportRepository = repository;
    _safetyReportsStatus = 'Conectando con reportes comunitarios...';
    _safetyReportsSubscription = repository.watchActiveReports().listen(
      (reports) {
        _safetyReports = reports
            .where((report) => report.isActiveAt(DateTime.now()))
            .toList(growable: false);
        _safetyReportsStatus = null;
        notifyListeners();
      },
      onError: (Object error, StackTrace stackTrace) {
        _safetyReportsStatus =
            'No se pudieron cargar los reportes comunitarios: $error';
        notifyListeners();
      },
    );
    _safetyReportExpiryTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) {
        final activeReports = _safetyReports
            .where((report) => report.isActiveAt(DateTime.now()))
            .toList(growable: false);
        if (activeReports.length != _safetyReports.length) {
          _safetyReports = activeReports;
          notifyListeners();
        }
      },
    );
  }

  Future<void> createSafetyReport({
    required SafetyHazardType type,
    required LatLng position,
  }) async {
    final repository = _safetyReportRepository;
    if (repository == null) {
      throw SafetyReportException(
        _safetyReportsStatus ??
            'El servicio de reportes comunitarios no está disponible.',
      );
    }

    await repository.createReport(type: type, position: position);
    _safetyReportsStatus =
        'Reporte de ${type.label.toLowerCase()} compartido con la comunidad por 24 horas.';
    notifyListeners();
  }

  void _loadPreferences(SharedPreferences preferences) {
    _userName = preferences.getString('profile.name') ?? _userName;
    _userInitials = _initialsFor(_userName);
    _bikeModel = preferences.getString('profile.bikeModel') ?? _bikeModel;
    _phoneNumber = preferences.getString('profile.phone') ?? _phoneNumber;
    _bikeType = preferences.getString('profile.bikeType') ?? _bikeType;
    _experienceLevel =
        preferences.getString('profile.experienceLevel') ?? _experienceLevel;
    _isRegistered = preferences.getBool('profile.isRegistered') ?? false;
    _trackingEnabled =
        preferences.getBool('privacy.trackingEnabled') ?? _trackingEnabled;
    _heatmapEnabled =
        preferences.getBool('map.heatmapEnabled') ?? _heatmapEnabled;
    _automaticNightModeEnabled =
        preferences.getBool('map.automaticNightModeEnabled') ?? true;
    _sosAlertNotificationsEnabled =
        preferences.getBool('sos.alertsEnabled') ?? false;

    final layerName = preferences.getString('map.activeLayer');
    if (layerName != null) {
      _preferredMapLayer = MapLayerType.values.firstWhere(
        (layer) => layer.name == layerName,
        orElse: () => MapLayerType.streets,
      );
    }
    refreshNightMode(notify: false);

    final alarmName = preferences.getString('sos.activeAlarm');
    if (alarmName != null) {
      _activeAlarm = AlarmPreset.values.firstWhere(
        (preset) => preset.name == alarmName,
        orElse: () => AlarmPreset.radarIos,
      );
    }

    final contactsJson = preferences.getString('sos.contacts');
    if (contactsJson != null) {
      final decoded = jsonDecode(contactsJson);
      if (decoded is! List) {
        throw const FormatException(
            'La lista de contactos SOS guardada no es válida.');
      }
      _emergencyContacts = decoded.map((entry) {
        if (entry is! Map<String, dynamic>) {
          throw const FormatException(
              'Contacto SOS guardado con formato inválido.');
        }
        return SosContact.fromJson(entry);
      }).toList();
    }

    _emergencyMessage =
        preferences.getString('sos.message') ?? _emergencyMessage;
  }

  Future<void> completeRegistration({
    required String phone,
    required String name,
    required String bikeType,
    required String experienceLevel,
  }) async {
    final trimmedName = name.trim();
    final trimmedPhone = phone.trim();
    final preferences = await SharedPreferences.getInstance();
    final results = await Future.wait([
      preferences.setString('profile.phone', trimmedPhone),
      preferences.setString('profile.name', trimmedName),
      preferences.setString('profile.bikeType', bikeType),
      preferences.setString('profile.experienceLevel', experienceLevel),
      preferences.setString('profile.bikeModel', bikeType),
      preferences.setBool('profile.isRegistered', true),
    ]);
    if (results.any((saved) => !saved)) {
      throw StateError(
          'El almacenamiento local rechazó uno o más datos del perfil.');
    }

    _phoneNumber = trimmedPhone;
    _userName = trimmedName;
    _userInitials = _initialsFor(trimmedName);
    _bikeType = bikeType;
    _experienceLevel = experienceLevel;
    _bikeModel = bikeType;
    _isRegistered = true;
    notifyListeners();
  }

  String _initialsFor(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty);
    final words = parts.toList();
    if (words.isEmpty) return 'U';
    if (words.length > 1) {
      return '${words.first[0]}${words[1][0]}'.toUpperCase();
    }
    return words.first
        .substring(0, words.first.length >= 2 ? 2 : 1)
        .toUpperCase();
  }

  void _savePreference(Future<bool> Function(SharedPreferences) save) {
    unawaited(() async {
      final preferences = await SharedPreferences.getInstance();
      if (!await save(preferences)) {
        throw StateError('No se pudo guardar la preferencia de CicloRadar.');
      }
    }());
  }

  Future<void> refreshLocation() async {
    _isLoadingLocation = true;
    notifyListeners();

    final verifiedLocation =
        await _locationService.getVerifiedCurrentLocation();
    _hasVerifiedUserLocation = verifiedLocation != null;
    _userLocation = verifiedLocation ?? LocationService.defaultLocation;
    _isLoadingLocation = false;
    _corridors = CommunityData.getSampleCorridors(_userLocation);
    _communityCyclists = CommunityData.getInitialCyclists(_userLocation);
    notifyListeners();
  }

  void setScreenIndex(int index) {
    _currentScreenIndex = index;
    notifyListeners();
  }

  Future<void> setSosAlertNotificationsEnabled(bool enabled) async {
    if (!enabled) {
      final preferences = await SharedPreferences.getInstance();
      if (!await preferences.setBool('sos.alertsEnabled', false)) {
        throw StateError('No se pudo guardar la preferencia de alertas SOS.');
      }
      _sosAlertNotificationsEnabled = false;
      _presenceTimer?.cancel();
      _presenceTimer = null;
      _sosPushStatus = null;
      notifyListeners();
      if (_sosPushService.isInitialized) {
        try {
          await _sosPushService.disableSosAlerts();
        } on SosPushException catch (error) {
          _sosPushStatus = error.message;
          notifyListeners();
          rethrow;
        }
      }
      return;
    }

    if (!_sosPushService.isConfigured || !_sosPushService.isInitialized) {
      throw const SosPushException(
        'Firebase aún no está configurado. No se activaron las alertas SOS.',
      );
    }

    final granted = await _sosPushService.enableSosAlerts();
    if (!granted) {
      throw const SosPushException(
        'El permiso de notificaciones fue rechazado; las alertas SOS siguen desactivadas.',
      );
    }
    final preferences = await SharedPreferences.getInstance();
    if (!await preferences.setBool('sos.alertsEnabled', true)) {
      await _sosPushService.disableSosAlerts();
      throw StateError('No se pudo guardar la preferencia de alertas SOS.');
    }

    _sosAlertNotificationsEnabled = true;
    _sosPushStatus = 'Recibirás alertas SOS grupales y de ciclistas cercanos.';
    notifyListeners();
    _startPresenceUpdates();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      refreshNightMode();
    }
    if (!_sosAlertNotificationsEnabled || !_sosPushService.isInitialized) {
      return;
    }
    if (state == AppLifecycleState.resumed) {
      _startPresenceUpdates();
    } else {
      _presenceTimer?.cancel();
      _presenceTimer = null;
      _lastPresencePublishedAt = null;
      _lastPresencePosition = null;
      unawaited(_clearSosPresence());
    }
  }

  @override
  void didChangePlatformBrightness() {
    refreshNightMode();
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    refreshNightMode();
  }

  void refreshNightMode({
    DateTime? localTime,
    Brightness? platformBrightness,
    bool notify = true,
  }) {
    final now = localTime ?? _localClock();
    final brightness = platformBrightness ?? _platformBrightness();
    final shouldEnable = _automaticNightModeEnabled &&
        _nightModeService.shouldEnable(
          localTime: now,
          platformBrightness: brightness,
        );
    final status = !_automaticNightModeEnabled
        ? 'Desactivado (activación automática deshabilitada)'
        : _nightModeService.activationReason(
            localTime: now,
            platformBrightness: brightness,
          );
    final didChange = shouldEnable != _advancedNightModeEnabled;
    final didStatusChange = status != _advancedNightModeStatus;
    _advancedNightModeEnabled = shouldEnable;
    _advancedNightModeStatus = status;
    _activeLayer = shouldEnable ? MapLayerType.dark : _preferredMapLayer;
    if ((didChange || didStatusChange) && notify) {
      notifyListeners();
    }
  }

  Future<void> setAutomaticNightModeEnabled(bool enabled) async {
    final preferences = await SharedPreferences.getInstance();
    if (!await preferences.setBool('map.automaticNightModeEnabled', enabled)) {
      throw StateError('No se pudo guardar la preferencia del modo nocturno.');
    }
    _automaticNightModeEnabled = enabled;
    refreshNightMode();
  }

  void _startPresenceUpdates() {
    _presenceTimer?.cancel();
    unawaited(_publishSosPresence(force: true));
    _presenceTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => unawaited(_publishSosPresence(force: true)),
    );
  }

  Future<void> _publishSosPresence({bool force = false}) async {
    if (!_sosAlertNotificationsEnabled ||
        !_sosPushService.isInitialized ||
        _presencePublishInProgress) {
      return;
    }
    if (!_hasVerifiedUserLocation) {
      _sosPushStatus =
          'Alertas activas, pero tu GPS no está disponible para aparecer en el radio de 10 km.';
      notifyListeners();
      return;
    }
    final now = DateTime.now();
    final previousPosition = _lastPresencePosition;
    final movedMeters = previousPosition == null
        ? double.infinity
        : const Distance().as(
            LengthUnit.Meter,
            previousPosition,
            _userLocation,
          );
    if (!force &&
        _lastPresencePublishedAt != null &&
        now.difference(_lastPresencePublishedAt!) <
            const Duration(seconds: 30) &&
        movedMeters < 100) {
      return;
    }
    _presencePublishInProgress = true;
    try {
      await _sosPushService.updateSosPresence(
        latitude: _userLocation.latitude,
        longitude: _userLocation.longitude,
      );
      _lastPresencePublishedAt = now;
      _lastPresencePosition = _userLocation;
      _sosPushStatus = 'Ubicación compartida solo mientras usas la app.';
    } on SosPushException catch (error) {
      _sosPushStatus = error.message;
    } finally {
      _presencePublishInProgress = false;
    }
    notifyListeners();
  }

  Future<void> _clearSosPresence() async {
    try {
      await _sosPushService.clearSosPresence();
    } on SosPushException catch (error) {
      _sosPushStatus = error.message;
      notifyListeners();
    }
  }

  void _handleIncomingPush(RemoteMessage message) {
    final data = message.data;
    final latitude = double.tryParse(data['latitude']?.toString() ?? '');
    final longitude = double.tryParse(data['longitude']?.toString() ?? '');
    final sosId = data['sosId']?.toString();
    if (latitude == null ||
        longitude == null ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180 ||
        sosId == null ||
        sosId.isEmpty) {
      _sosPushStatus = 'Se recibió una alerta SOS con datos incompletos.';
      notifyListeners();
      return;
    }

    if (data['senderId'] == _sosPushService.currentUserId) {
      _activeSosId = sosId;
      final shouldStartAlarm = !_isEmergencyActive;
      _isEmergencyActive = true;
      _sosPushStatus = 'Tu SOS sigue activo.';
      if (shouldStartAlarm) {
        _audioService.triggerEmergencyAlarm(preset: _activeAlarm);
      }
    } else {
      if (_incomingEmergency?.id == sosId) return;
      final position = LatLng(latitude, longitude);
      final distanceKm =
          const Distance().as(LengthUnit.Kilometer, _userLocation, position);
      final name = data['riderName']?.toString() ?? 'Ciclista cercano';
      _incomingEmergency = Cyclist(
        id: sosId,
        name: name,
        initials: _initialsFor(name),
        distanceKm: distanceKm,
        position: position,
        isEmergency: true,
        lastSeen: 'SOS activo',
        bikeModel: 'No informado',
      );
      _audioService.triggerEmergencyAlarm(preset: _activeAlarm);
    }
    _currentScreenIndex = 1;
    notifyListeners();
  }

  void setMapLayer(MapLayerType layer) {
    _preferredMapLayer = layer;
    _activeLayer =
        _advancedNightModeEnabled ? MapLayerType.dark : _preferredMapLayer;
    _savePreference(
        (preferences) => preferences.setString('map.activeLayer', layer.name));
    notifyListeners();
  }

  void toggleHeatmap() {
    _heatmapEnabled = !_heatmapEnabled;
    _savePreference((preferences) =>
        preferences.setBool('map.heatmapEnabled', _heatmapEnabled));
    notifyListeners();
  }

  void toggleTracking() {
    _trackingEnabled = !_trackingEnabled;
    _savePreference((preferences) =>
        preferences.setBool('privacy.trackingEnabled', _trackingEnabled));
    notifyListeners();
  }

  void setActiveAlarm(AlarmPreset preset) {
    _activeAlarm = preset;
    _savePreference(
        (preferences) => preferences.setString('sos.activeAlarm', preset.name));
    notifyListeners();
  }

  void previewAlarmSound(AlarmPreset preset) {
    _audioService.previewAlarm(preset);
  }

  void updateProfile({
    String? name,
    String? bikeModel,
    String? contact,
    String? message,
  }) {
    if (name != null && name.isNotEmpty) {
      _userName = name.trim();
      _userInitials = _initialsFor(_userName);
      _savePreference(
          (preferences) => preferences.setString('profile.name', _userName));
    }
    if (bikeModel != null) {
      _bikeModel = bikeModel;
      _savePreference((preferences) =>
          preferences.setString('profile.bikeModel', _bikeModel));
    }
    if (contact != null && contact.trim().isNotEmpty) {
      _emergencyContacts = [
        SosContact(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          name: 'Contacto SOS',
          phone: contact.trim(),
        ),
      ];
      _saveContacts();
    }
    if (message != null) {
      _emergencyMessage = message;
      _savePreference(
          (preferences) => preferences.setString('sos.message', message));
    }
    notifyListeners();
  }

  void addEmergencyContact(SosContact contact) {
    _emergencyContacts = [..._emergencyContacts, contact];
    _saveContacts();
    notifyListeners();
  }

  void removeEmergencyContact(String id) {
    _emergencyContacts =
        _emergencyContacts.where((contact) => contact.id != id).toList();
    _saveContacts();
    notifyListeners();
  }

  void _saveContacts() {
    final contactsJson = jsonEncode(
      _emergencyContacts.map((contact) => contact.toJson()).toList(),
    );
    _savePreference(
        (preferences) => preferences.setString('sos.contacts', contactsJson));
  }

  // --- FLUJO DE EMERGENCIA SOS ---

  /// Inicia la cuenta regresiva de 5 segundos contra pulsaciones accidentales
  void startSosCountdown() {
    if (_isCountingDown || _isEmergencyActive) return;

    _isCountingDown = true;
    _countdownSeconds = 5;
    notifyListeners();

    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdownSeconds > 1) {
        _countdownSeconds--;
        notifyListeners();
      } else {
        timer.cancel();
        _isCountingDown = false;
        triggerEmergencySos();
      }
    });
  }

  /// Cancela la cuenta regresiva inmediatamente
  void cancelSosCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _isCountingDown = false;
    _countdownSeconds = 5;
    notifyListeners();
  }

  /// Dispara la alerta SOS activa con volumen forzado al máximo
  void triggerEmergencySos() {
    if (_isEmergencyActive) return;
    _isEmergencyActive = true;
    _sosPushStatus = null;
    notifyListeners();
    _audioService.triggerEmergencyAlarm(preset: _activeAlarm);
    unawaited(_sendSosToBackend());
  }

  Future<void> _sendSosToBackend() async {
    final recipientPhones = normalizeSosRecipientPhones(_emergencyContacts);
    final invalidContactCount = _emergencyContacts
        .where((contact) => contact.normalizedPhone == null)
        .length;

    if (!_sosPushService.isConfigured) {
      _sosPushStatus =
          'SOS local activo; Firebase no está configurado y no se envió un push grupal. '
          'La alerta remota requiere backend desplegado y contactos con cuenta verificada.';
      notifyListeners();
      return;
    }
    if (!_sosPushService.isInitialized) {
      _sosPushStatus = _sosPushStatus ??
          'SOS local activo; Firebase no pudo inicializarse y no se envió un push grupal.';
      notifyListeners();
      return;
    }

    final position = await _locationService.getVerifiedCurrentLocation();
    if (!_isEmergencyActive) return;
    if (position == null) {
      _sosPushStatus =
          'SOS local activo; no se envió el push porque no se pudo obtener tu ubicación GPS.';
      notifyListeners();
      return;
    }

    try {
      final result = await _sosPushService.activateSos(
        riderName: _userName,
        latitude: position.latitude,
        longitude: position.longitude,
        recipientPhones: recipientPhones,
      );
      if (!_isEmergencyActive) {
        await _sosPushService.resolveSos(result.sosId);
        _sosPushStatus = 'SOS remoto desactivado.';
        notifyListeners();
        return;
      }
      _activeSosId = result.sosId;
      final invalidContactsMessage = invalidContactCount > 0
          ? ' $invalidContactCount contacto(s) omitido(s): verifica el teléfono con código de país.'
          : '';
      _sosPushStatus = result.groupNotifiedCount > 0
          ? 'SOS grupal aceptado para ${result.groupNotifiedCount} dispositivo(s). '
              'La entrega final depende de la conexión del destinatario.'
              '${result.groupSkippedCount > 0 ? ' ${result.groupSkippedCount} contacto(s) sin cuenta verificada o sin consentimiento.' : ''}'
              '$invalidContactsMessage'
          : 'SOS remoto activo, pero ningún contacto grupal confirmó elegibilidad.'
              '${result.groupSkippedCount > 0 ? ' ${result.groupSkippedCount} contacto(s) sin cuenta verificada o sin consentimiento.' : ''}'
              '$invalidContactsMessage';
    } on SosPushException catch (error) {
      _sosPushStatus =
          'SOS local activo, pero no se pudo enviar la alerta remota: ${error.message}';
    }
    notifyListeners();
  }

  /// Detiene la alarma activa y silencia la sirena
  void dismissEmergencySos() {
    _isEmergencyActive = false;
    _audioService.stopAlarm();
    final sosId = _activeSosId;
    _activeSosId = null;
    if (sosId != null) unawaited(_resolveSosOnBackend(sosId));
    notifyListeners();
  }

  Future<void> _resolveSosOnBackend(String sosId) async {
    try {
      await _sosPushService.resolveSos(sosId);
      _sosPushStatus = 'SOS desactivado.';
    } on SosPushException catch (error) {
      _sosPushStatus = 'No se pudo cerrar el SOS remoto: ${error.message}';
    }
    notifyListeners();
  }

  /// Simula una alerta entrante de un ciclista cercano para probar el radar
  void simulateIncomingEmergency() {
    final alertPos = LatLng(
        _userLocation.latitude + 0.0019, _userLocation.longitude + 0.0014);
    _incomingEmergency = Cyclist(
      id: 'alert-sim-1',
      name: 'Elena Gómez (Alerta SOS)',
      initials: 'EG',
      distanceKm: 0.28,
      position: alertPos,
      isEmergency: true,
      lastSeen: '¡Caída detectada hace 1 min!',
      bikeModel: 'Cannondale Trail 5',
    );
    notifyListeners();

    // Activar sonido con boost
    _audioService.triggerEmergencyAlarm(preset: _activeAlarm);
  }

  void dismissIncomingEmergency() {
    dismissIncomingSos();
  }

  void dismissIncomingSos() {
    _incomingEmergency = null;
    _audioService.stopAlarm();
    notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _countdownTimer?.cancel();
    _nightModeTimer?.cancel();
    _safetyReportExpiryTimer?.cancel();
    unawaited(_safetyReportsSubscription?.cancel());
    _presenceTimer?.cancel();
    _locationService.stopTracking();
    if (_historicalSpeedSampleCount > _persistedHistoricalSpeedSampleCount) {
      unawaited(_persistHistoricalSpeed());
    }
    _audioService.dispose();
    unawaited(_sosPushService.dispose());
    super.dispose();
  }
}

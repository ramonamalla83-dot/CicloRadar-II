import 'package:cicloradar/providers/app_state.dart';
import 'package:cicloradar/main.dart';
import 'package:cicloradar/models/map_layer.dart';
import 'package:cicloradar/services/firebase_config.dart';
import 'package:cicloradar/screens/home_screen.dart';
import 'package:cicloradar/screens/registration_screen.dart';
import 'package:cicloradar/screens/sos_contacts_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('push integration is not configured without Firebase options', () {
    expect(FirebaseConfig.isConfigured, isFalse);
  });

  test('automatic night mode temporarily overrides and restores the map layer',
      () async {
    SharedPreferences.setMockInitialValues({});
    final appState = AppState.forTesting();
    appState.setMapLayer(MapLayerType.satellite);

    appState.refreshNightMode(
      localTime: DateTime(2026, 1, 1, 20),
      platformBrightness: Brightness.light,
    );
    expect(appState.advancedNightModeEnabled, isTrue);
    expect(appState.activeLayer, MapLayerType.dark);
    expect(appState.preferredMapLayer, MapLayerType.satellite);

    appState.refreshNightMode(
      localTime: DateTime(2026, 1, 2, 7),
      platformBrightness: Brightness.light,
    );
    expect(appState.advancedNightModeEnabled, isFalse);
    expect(appState.activeLayer, MapLayerType.satellite);
  });

  test('automatic night mode follows system darkness outside night hours', () {
    final appState = AppState.forTesting();

    appState.refreshNightMode(
      localTime: DateTime(2026, 1, 1, 12),
      platformBrightness: Brightness.dark,
    );

    expect(appState.advancedNightModeEnabled, isTrue);
    expect(appState.activeLayer, MapLayerType.dark);
  });

  test('disabling automatic night mode restores the preferred map layer',
      () async {
    SharedPreferences.setMockInitialValues({});
    final appState = AppState.forTesting();
    appState.setMapLayer(MapLayerType.terrain);
    appState.refreshNightMode(
      localTime: DateTime(2026, 1, 1, 20),
      platformBrightness: Brightness.light,
    );
    expect(appState.activeLayer, MapLayerType.dark);

    await appState.setAutomaticNightModeEnabled(false);

    expect(appState.automaticNightModeEnabled, isFalse);
    expect(appState.advancedNightModeEnabled, isFalse);
    expect(appState.activeLayer, MapLayerType.terrain);
    expect(appState.advancedNightModeStatus, contains('Desactivado'));
  });

  testWidgets('a new profile opens on registration instead of the map',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final appState = AppState.forTesting();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: appState,
        child: const CicloRadarFlutterApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Tu número'), findsOneWidget);
    expect(find.text('Radar Mapa'), findsNothing);
  });

  testWidgets('home dashboard shows clearly marked example activity',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final appState = AppState.forTesting();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: appState,
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Kilómetros recorridos'), findsOneWidget);
    expect(find.text('75,5'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);

    await tester.scrollUntilVisible(
      find.text('4 h 32 min'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('4 h 32 min'), findsOneWidget);
    expect(find.text('Rutas guardadas'), findsOneWidget);

    await tester.drag(find.byType(ListView).first, const Offset(0, 1000));
    await tester.pumpAndSettle();
    expect(find.textContaining('son de ejemplo.'), findsOneWidget);

    final mapButton = find.text('Abrir radar del mapa');
    await tester.scrollUntilVisible(
      mapButton,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(mapButton);
    await tester.pumpAndSettle();
    expect(appState.currentScreenIndex, 1);
  });

  testWidgets('registration saves the rider profile after the demo code step',
      (tester) async {
    String? registeredPhone;
    String? registeredName;
    String? registeredBike;
    String? registeredLevel;

    await tester.pumpWidget(
      MaterialApp(
        home: RegistrationScreen(
          onComplete: ({
            required String phone,
            required String name,
            required String bikeType,
            required String experienceLevel,
          }) async {
            registeredPhone = phone;
            registeredName = name;
            registeredBike = bikeType;
            registeredLevel = experienceLevel;
          },
        ),
      ),
    );

    expect(find.text('Tu número'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), '+54 11 1234-5678');
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    expect(find.textContaining('no está conectada'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), '123456');
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), 'Tatu Ciclista');
    await tester.tap(find.text('Comenzar a rodar'));
    await tester.pumpAndSettle();

    expect(registeredPhone, '+54 11 1234-5678');
    expect(registeredName, 'Tatu Ciclista');
    expect(registeredBike, 'MTB');
    expect(registeredLevel, 'Intermedio');
  });

  testWidgets('SOS contacts can be added and removed', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final appState = AppState.forTesting();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: appState,
        child: const MaterialApp(home: SosContactsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byType(TextFormField).at(0), 'Contacto de prueba');
    await tester.enterText(
        find.byType(TextFormField).at(1), '+54 11 1234 5678');
    await tester.tap(find.text('Añadir contacto'));
    await tester.pumpAndSettle();

    expect(find.text('Contacto de prueba'), findsOneWidget);
    expect(find.text('+54 11 1234 5678'), findsOneWidget);

    await tester.tap(find.byTooltip('Eliminar contacto'));
    await tester.pumpAndSettle();

    expect(find.text('Contacto de prueba'), findsNothing);
    expect(find.text('Todavía no agregaste contactos de emergencia.'),
        findsOneWidget);
  });
}

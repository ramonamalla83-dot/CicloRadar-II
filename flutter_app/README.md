# CicloRadar Flutter

Implementación única de CicloRadar para Android, iOS y Web. El código de la app está en `lib/`; `web/` contiene la entrada y metadatos de Flutter Web.

## Requisitos

- Flutter 3.41 o superior (Dart 3.11).
- Android Studio o VS Code con el SDK Flutter para Android.
- macOS, Xcode y CocoaPods para compilar iOS.

## Desarrollo

Desde este directorio:

```powershell
flutter pub get
flutter run
```

Para navegador: `flutter run -d chrome`.

## Validación y compilación

```powershell
flutter analyze
flutter test
flutter build web
```

Android: `flutter build apk --release`. iOS: `flutter build ipa --release` desde macOS.

## Funcionalidad y límites

La app inicia con un registro local de tres pasos (teléfono, código de demostración y perfil ciclista) y continúa a Inicio, con un dashboard ilustrativo, y al mapa. Incluye mapas raster, GPS con ubicación de respaldo, datos de comunidad de ejemplo, privacidad local, perfil y contactos SOS guardados en el dispositivo. Las alarmas se sintetizan localmente; vibración y bloqueo de pantalla dependen de la plataforma.

**Prototipo solamente:** el código de registro no se envía por SMS ni se valida con un servicio; solo sirve para avanzar el flujo de demostración. La comunidad no se conecta a otros usuarios. El cliente FCM de alertas SOS requiere un proyecto Firebase y las Cloud Functions documentadas antes de poder enviar notificaciones remotas. No usar como sistema de emergencia real. El nivel de volumen también depende del dispositivo.
Las métricas, recorridos recientes y rutas predefinidas de Inicio son datos de ejemplo. En Android e iOS se pueden grabar recorridos GPS reales desde el mapa; se guardan localmente en el dispositivo. Para registrar una actividad, mantén CicloRadar abierto durante el recorrido.
La tarjeta «Sincronización de salud» permite exportar actividades y trazas GPS a Health Connect (Android) o Apple Health (iOS), con permisos explícitos. Las rutas antiguas se exportan manualmente y los recorridos nuevos se sincronizan automáticamente mientras la opción siga activada. La API de Google Fit está obsoleta; Android usa Health Connect. El APK requiere Android 8.0 (API 26) o superior por la dependencia Health; Health Connect está disponible en dispositivos Android compatibles (Android 9 o superior). En iOS, HealthKit debe habilitarse en Signing & Capabilities y requiere una cuenta de desarrollador para firmar la app. Antes de distribuir en Play Store, publica una política de privacidad accesible y completa la declaración de permisos de Health Connect.
El mapa consulta el pronóstico horario de Open-Meteo para la ubicación GPS verificada y avisa sobre tormentas o ráfagas de viento de 40 km/h o más durante las próximas tres horas. No requiere una clave API. Como todavía no hay rutas activas con coordenadas, el widget describe el clima en la posición actual y no el riesgo de todo el recorrido.
El botón ETA permite marcar un destino en el mapa y estima la llegada usando un perfil de elevación de Open-Meteo y el promedio GPS local de velocidades ciclistas válidas. Hasta reunir historial real, usa una referencia inicial de 16,7 km/h, indicada como tal. La distancia y la altimetría corresponden a una línea directa entre origen y destino, no al trayecto por calles o senderos. La pantalla atribuye la altimetría a Open-Meteo y Copernicus DEM.
El modo nocturno avanzado se activa automáticamente si el sistema operativo usa el tema oscuro o si la hora local está entre las 20:00 y las 07:00. Cambia temporalmente el mapa a la capa oscura y atenúa la interfaz; al desactivarse, restaura la capa que el ciclista había elegido. Se puede deshabilitar desde Ajustes y Perfil.
El botón SOS incluye a los contactos con teléfono E.164 en la solicitud grupal. El backend debe resolver únicamente cuentas CicloRadar con teléfono verificado y consentimiento SOS; los pushes incluyen coordenadas exactas para abrir la ubicación del emisor en el mapa. Esta entrega no está activa hasta configurar Firebase, verificación de cuenta y Cloud Functions; consulta [FIREBASE_PUSH_SETUP.md](./FIREBASE_PUSH_SETUP.md).
En el mapa se pueden publicar hitos de seguridad (obras, baches, rutas peligrosas y obstáculos). Con Firestore configurado, los reportes aparecen en tiempo real para la comunidad y caducan a las 24 horas. Las coordenadas de los reportes son públicas; activa App Check y despliega [firestore.rules](./firestore.rules) antes de habilitar escrituras.

Consulta [FIREBASE_PUSH_SETUP.md](./FIREBASE_PUSH_SETUP.md) para configuración, privacidad y contrato del backend requerido para recibir alertas SOS en segundo plano.

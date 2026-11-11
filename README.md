# 📱 MediTrack Mobile

App móvil de **MediTrack** hecha con **Flutter**. Permite a una persona (o a su cuidador) llevar el control de sus medicamentos desde el teléfono: ver las dosis del día, registrarlas, escanear una receta con la cámara, guardar alergias y mostrar una tarjeta de emergencia. Usa la API de [`meditrack-backend`](../meditrack-backend).

## 🧭 Qué incluye

- Registro, inicio de sesión y recuperación de contraseña.
- Alta de tratamientos, a mano o **escaneando la receta**.
- Dosis programadas y recordatorios (con preferencias de notificación).
- Modo **cuidador**: gestionar personas a cargo y su consentimiento.
- Tarjeta de emergencia (SOS) con contacto y alergias.

## 🚀 Empezar

La forma más simple **no requiere instalar Flutter ni el SDK de Android**: los scripts usan un contenedor Docker con todo lo necesario.

**Necesitas:** Docker.

### Compilar el APK de Android

```bash
./build-apk.sh                 # release, apunta al emulador (10.0.2.2)
./build-apk.sh debug           # debug, permite HTTP a cualquier host
API_BASE_URL=http://192.168.1.50/api/v1 ./build-apk.sh debug   # teléfono físico en tu red
```

El APK queda en `build/app/outputs/flutter-apk/`.

> ⚠️ Un APK **release** solo permite HTTP sin cifrar hacia `10.0.2.2`/`localhost`. Para un teléfono físico usa `debug` hasta que el backend tenga HTTPS.

### ¿A qué API se conecta?

La URL base se decide **al compilar** (no se puede cambiar después de instalar la app):

| Situación | URL usada |
|---|---|
| Emulador de Android | `http://10.0.2.2/api/v1` (alias del `localhost` de tu PC) |
| Web / otras plataformas | `http://localhost/api/v1` |
| Cualquier otra | La que pases con `--dart-define=API_BASE_URL=...` |

Necesitas el backend corriendo: mira cómo en [`meditrack-infra`](../meditrack-infra). La URL de la API **no es un secreto** (queda dentro del APK), por eso no hay `.env` en este proyecto.

### Previsualizar en el navegador

```bash
./preview-web.sh      # compila la versión web; sírvela en http://localhost:9090
```

Vuelve a ejecutarlo después de cada cambio en `lib/` y refresca el navegador (Ctrl+Shift+R).

## 🧪 Pruebas

```bash
./run-tests.sh
```

Ejecuta `flutter analyze` y toda la suite de tests **tres veces, una por zona horaria** (`UTC`, `Europe/Madrid`, `America/Bogota`). Es intencional: el backend trabaja en hora de Bogotá y las fechas deben mostrarse bien sea cual sea la zona del teléfono.

## 📁 Estructura

```text
meditrack-mobile/
├── lib/
│   ├── main.dart       # Punto de entrada
│   ├── api/            # Cliente HTTP y almacenamiento seguro de tokens
│   ├── models/         # Modelos de datos (Treatment, ScheduledDose, EmergencyCard…)
│   ├── screens/        # Pantallas (login, home, escaneo de receta, cuenta…)
│   ├── services/       # Lógica de negocio (recordatorios, etc.)
│   ├── widgets/        # Componentes reutilizables
│   ├── theme/          # Colores y estilos
│   └── utils/          # Utilidades y formateadores
├── test/               # Tests unitarios y de widgets
├── android/ ios/ web/ …# Proyectos de cada plataforma (generados por Flutter)
├── build-apk.sh        # Compila el APK dentro de Docker
├── preview-web.sh      # Compila y previsualiza la versión web
└── run-tests.sh        # Análisis + tests en 3 zonas horarias
```

## 🤖 Compilar desde GitHub

El workflow **Build APK (manual)** (`.github/workflows/build-apk.yml`) se lanza a mano desde la pestaña *Actions*: eliges `debug` o `release`, opcionalmente la URL de la API, y descarga el APK como artefacto (se conserva 14 días). No publica nada.

## 🔐 Pendiente antes de publicar

- El build **release se firma hoy con la clave de debug** (`android/app/build.gradle.kts`). Para publicar en Play Store hay que crear un *keystore* propio.
- Ese keystore y `key.properties` **nunca deben subirse al repositorio** (ya están en `.gitignore`); en CI se guardan como GitHub Secrets.

## 📚 Si es tu primera vez con Flutter

- [Aprende Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Tu primera app](https://docs.flutter.dev/get-started/codelab)

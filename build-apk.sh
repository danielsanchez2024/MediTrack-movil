#!/usr/bin/env bash
# Compila el APK de Android dentro de un contenedor con el SDK de Flutter,
# sin necesidad de instalar Flutter en la máquina host.
#
# Uso:
#   ./build-apk.sh                 # release, apunta al emulador (10.0.2.2)
#   ./build-apk.sh debug           # debug, admite HTTP a cualquier host
#   API_BASE_URL=http://192.168.1.50/api/v1 ./build-apk.sh debug
#                                  # para un móvil físico en la misma red
#
# Un APK release solo permite HTTP sin cifrar hacia 10.0.2.2/localhost (ver
# android/app/src/main/res/xml/network_security_config.xml): para un móvil
# físico usá debug hasta que el backend tenga HTTPS.
set -euo pipefail
cd "$(dirname "$0")"

MODE="${1:-release}"
case "$MODE" in
  release|debug) ;;
  *) echo "Modo desconocido: $MODE (usa release o debug)" >&2; exit 1 ;;
esac

DART_DEFINES=""
if [ -n "${API_BASE_URL:-}" ]; then
  DART_DEFINES="--dart-define=API_BASE_URL=$API_BASE_URL"
fi

IMAGE=meditrack-mobile-builder

docker build -t "$IMAGE" .

# Same persistent pub-cache volume preview-web.sh uses — keeps package
# paths stable across separate container runs instead of dangling once the
# container that first fetched them is removed.
docker run --rm \
  -v "$(pwd):/app" \
  -v meditrack_flutter_pubcache:/root/.pub-cache \
  -w /app \
  "$IMAGE" \
  sh -c "flutter pub get && flutter build apk --$MODE $DART_DEFINES"

# El contenedor compila como root; devolvemos la propiedad de los artefactos
# generados al usuario del host.
docker run --rm -v "$(pwd):/app" alpine chown -R "$(id -u):$(id -g)" /app/build

echo "APK generado en: $(pwd)/build/app/outputs/flutter-apk/app-$MODE.apk"

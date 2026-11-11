#!/usr/bin/env bash
# Corre `flutter analyze` y la suite de tests dentro de Docker, una vez por cada zona
# horaria: los tests de fechas tienen que pasar sea cual sea la zona del teléfono
# (el backend trabaja en hora de Bogotá; ver ApiDateTimeConfig en meditrack-backend).
set -euo pipefail
cd "$(dirname "$0")"

ZONES=(UTC Europe/Madrid America/Bogota)
IMAGE=ghcr.io/cirruslabs/flutter:stable

docker run --rm \
  -v "$(pwd):/app" -v meditrack_flutter_pubcache:/root/.pub-cache -w /app \
  "$IMAGE" sh -c "flutter pub get >/dev/null && flutter analyze"

for zone in "${ZONES[@]}"; do
  echo "== Tests con TZ=$zone"
  docker run --rm -e TZ="$zone" \
    -v "$(pwd):/app" -v meditrack_flutter_pubcache:/root/.pub-cache -w /app \
    "$IMAGE" flutter test
done

docker run --rm -v "$(pwd):/app" alpine chown -R "$(id -u):$(id -g)" /app/build /app/.dart_tool

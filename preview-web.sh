#!/usr/bin/env bash
# Recompila la app para web (usa el SDK de Flutter dentro de Docker) y la deja
# lista para servir en http://localhost:9090. Corré esto después de cada
# cambio en lib/ y refrescá el navegador (Ctrl+Shift+R para forzar recarga).
set -euo pipefail
cd "$(dirname "$0")"

# The pub-cache volume persists between runs — each `docker run` is a fresh
# container otherwise, so without it package_config.json ends up pointing at
# an already-destroyed container's cache paths and every build after the
# first fails with "No such file or directory" on some pub.dev package.
docker run --rm \
  -v "$(pwd):/app" \
  -v meditrack_flutter_pubcache:/root/.pub-cache \
  -w /app \
  ghcr.io/cirruslabs/flutter:stable \
  sh -c "flutter pub get && flutter build web"

docker run --rm -v "$(pwd):/app" alpine chown -R "$(id -u):$(id -g)" /app/build /app/.dart_tool

echo "Listo. Refrescá http://localhost:9090"

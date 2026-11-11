# Entorno de build para compilar el APK sin instalar el SDK de Flutter/Android
# en la máquina del desarrollador. No es una imagen "de servicio": no expone
# puertos ni tiene ENTRYPOINT de larga duración, solo compila y deja el APK
# en /app/build (montado desde el host por build-apk.sh).
FROM ghcr.io/cirruslabs/flutter:stable
WORKDIR /app

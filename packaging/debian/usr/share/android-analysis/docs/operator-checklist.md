# Checklist del operador

## Antes de instalar

Confirma Ubuntu soportado, snapshot de la estación, espacio disponible, proxy de salida, repositorios aprobados y SHA-256 de JADX si existe. Ejecuta primero `--dry-run` y registra el directorio de destino.

## Antes del análisis

Registra APK y hash, versión del toolchain y autorización de la aplicación. Para ADB, verifica el serial exacto con `adb devices`; no uses dispositivos personales. Para proxy o instrumentación, confirma que el emulador/dispositivo y la red son de laboratorio.

## Después

Guarda versiones, logs y hashes aprobados. Revoca certificados de proxy de prueba, desconecta el dispositivo, elimina credenciales temporales y clasifica APKs, dumps, capturas PCAP y resultados de Frida como material sensible. Registra fallos de instalación parcial y limpia el directorio antes de reutilizar la estación.

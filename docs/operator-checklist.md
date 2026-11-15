# Checklist del operador

## Antes de instalar

Confirma Ubuntu soportado, snapshot de la estación, espacio disponible, proxy de salida, repositorios aprobados y SHA-256 de JADX si existe. Ejecuta primero `--dry-run` y registra el directorio de destino.

## Antes del análisis

Registra APK y hash, versión del toolchain y autorización de la aplicación. Para ADB, verifica el serial exacto con `adb devices`; no uses dispositivos personales. Para proxy o instrumentación, confirma que el emulador/dispositivo y la red son de laboratorio. Para trazas, revisa primero el plan con `--traces --dry-run` (o la vista previa de la pestaña TRAZAS ADB) y confirma el serial y el directorio de evidencia; logcat, dmesg y bugreport son material sensible. Para auditoría, revisa primero el plan con `--audit --dry-run` (o la vista previa de la pestaña AUDITORÍA ADB), confirma el serial, la clave del operador y si se sondea el 5555 desde la red; no audites un dispositivo con un veredicto CRÍTICO pendiente sin resolverlo.

## Después

Guarda versiones, logs y hashes aprobados. Revoca certificados de proxy de prueba, desconecta el dispositivo, elimina credenciales temporales y clasifica APKs, dumps, capturas PCAP y resultados de Frida como material sensible. Registra fallos de instalación parcial y limpia el directorio antes de reutilizar la estación. Las trazas quedan en `~/security-tools/traces/<fecha>_<serial>/` con su `MANIFIESTO.txt`; consérvalas solo según la retención autorizada y no las subas al repo. Las auditorías quedan en `~/security-tools/audits/AUDITORIA-<fecha>_<serial>/` con `RESUMEN.txt` y `MANIFIESTO.txt`; las claves RSA autorizadas y los hallazgos son material sensible y tampoco se suben al repo.

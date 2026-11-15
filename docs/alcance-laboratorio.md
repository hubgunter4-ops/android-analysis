# Alcance de laboratorio

Qué dispositivos y redes están autorizados para `android-analysis`.
Es la allowlist que aplican las trazas, la auditoría y la conexión
ADB: un objetivo fuera de alcance se rechaza antes de ejecutar nada.

## Archivo de alcance

Ruta por defecto: `~/security-tools/scope` (0600). También se puede
pasar explícita con `--scope-file PATH` (CLI) o en la pestaña
**CONEXIÓN ADB** de la GUI, que además tiene el botón **Crear
plantilla de alcance**.

Formato (una entrada por línea; `#` son comentarios):

```text
# Un serial autorizado por línea:
serial:emulator-5554
serial:RF8M123ABC

# Una IP o red autorizada para adb connect por línea:
tcp:192.168.1.42
tcp:192.168.1.0/24
```

## Reglas

- **Sin archivo de alcance, la allowlist está inactiva.** Los scripts
  lo anotan en el reporte (`sin archivo de alcance`) y el operador
  responde por cada objetivo. Crear el archivo activa la allowlist.
- **Serial**: si el archivo tiene entradas `serial:`, un serial dado
  debe estar listado; sin entradas `serial:`, el serial no se restringe.
- **TCP**: si se pide `--tcp`, la IP debe estar listada (exacta o
  dentro de una red CIDR); sin entradas `tcp:`, TCP no está autorizado.
- **Archivo explícito inexistente**: pasar `--scope-file` con una ruta
  que no existe es un error, no una allowlist vacía: el operador pidió
  enforcement desde un archivo que no está.
- La auditoría no necesita entradas `tcp:` para su sonda al 5555:
  esa sonda va solo contra las IP del propio dispositivo, no contra
  objetivos de la red.

## Qué está dentro y fuera del alcance

Dentro: emuladores y dispositivos de laboratorio registrados por
serial, en la red Wi-Fi del laboratorio, con depuración USB aceptada
por el operador del laboratorio.

Fuera: dispositivos personales, dispositivos de terceros, redes
públicas, IPs de internet y cualquier objetivo sin autorización
escrita. La conexión por TCP exige que el teléfono esté en la misma
Wi-Fi que la estación; en datos móviles no es alcanzable y el puerto
5555 no debe exponerse.

## Mantenimiento

Revisa el archivo cuando cambie el laboratorio: añade el serial de
cada dispositivo nuevo, quita los retirados y ajusta las redes TCP.
El archivo contiene seriales e IPs internas: es material sensible,
no se sube al repo y se conserva con permisos 0600.

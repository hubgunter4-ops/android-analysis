# Apps, uso, conexiones y datos

Listado de apps, uso en primer plano, conexiones de red y desglose de
datos por app, más las acciones solicitadas por cada app (servicios,
trabajos, alarmas y wakelocks) y el árbol de procesos (de quién hereda
cada proceso). Solo sobre dispositivos de laboratorio autorizados y
dentro del alcance de laboratorio (`docs/alcance-laboratorio.md`).

## Qué hace

`src/android_toolchain/apps.sh` (solo lectura; exige `--confirm`):

1. **Apps** (`pm list packages -3 -U`, y `-s -U` con `--todas`):
   paquete, UID y versionCode si el `pm` del dispositivo lo soporta
   (`--show-versioncode`). Si no lo soporta, se degrada solo a
   paquete+UID; si ni `-U` existe (pm antiguo), se degrada a solo
   paquete y el informe avisa de que conexiones y datos no se pueden
   atribuir por app.
2. **Uso** (`dumpsys usagestats`): tiempo total en primer plano y
   último uso por paquete. Si el volcado sale vacío o no se puede
   interpretar, el informe dice "sin datos de uso" en vez de fallar.
3. **Conexiones** (`cat /proc/net/tcp`, `tcp6`, `udp`, `udp6`):
   protocolo, extremo local y remoto (IP:puerto) y estado, unidas al
   paquete por UID. Solo extremos, sin cargas útiles. Las direcciones
   hexadecimales little-endian de `/proc/net/*` se decodifican en
   local (IPv4, o IPv6 entre corchetes `[::1]:443`).
4. **Desglose de datos** (`dumpsys netstats`): bytes recibidos y
   enviados por UID, separados por tipo de red (MOBILE y WIFI) y
   agregados por paquete. Tabla `paquete | rx móvil | tx móvil |
   rx wifi | tx wifi | total` en el informe y en `resumen.json`.
   Los contadores son acumulados desde el arranque del contador, no
   de la última hora. Si el volcado no trae contadores por UID, el
   informe dice "sin datos".
5. **Acciones solicitadas por apps y daemons** (metadatos, no el
   contenido de la acción):
   - servicios en ejecución (`dumpsys activity services`): líneas
     `ServiceRecord{...} com.ejemplo.app/.Servicio`;
   - trabajos programados (`dumpsys jobscheduler`): bloques `JOB #...`
     con el componente del servicio o el usuario `u0aNNN`
     (UID = 10000 + NNN);
   - alarmas programadas (`dumpsys alarm`): bloques `Alarm{...}` con
     el paquete de la propia línea o de la línea `tag=`;
   - wakelocks retenidos (`dumpsys power`): sección `Wake Locks:`
     con `uid=<n>` y el nombre del candado entre comillas.
   Por app se cuentan servicios, trabajos, alarmas y wakelocks, con
   hasta 5 muestras de cada uno en el informe. Si un volcado sale
   vacío o no se puede interpretar, esa fuente queda como "sin datos"
   en vez de fallar.
6. **PID heredado** (`ps -A -o PID,PPID,NAME`, con fallback a `ps -A`
   si la forma `-o` no existe): mapa padre → hijos. La tabla por app
   muestra PID y PPID (de quién hereda: init, zygote u otro proceso)
   y el informe añade la sección **Árbol de procesos** con los hijos
   de init, los hijos de zygote y los padres inusuales con sus hijos.
   Un proceso se marca como **herencia inusual** en `resumen.json`
   cuando su padre no es init ni zygote (zygote, zygote64, zygote32);
   quedan fuera los hilos del kernel (`[...]`) y los PID 1 y 2.

El análisis y la clasificación se hacen en local con python3, que
lee los archivos de fuente y escribe `APPS.txt` (informe en español:
resumen, tabla por app, desglose de datos, acciones solicitadas,
árbol de procesos, herencia inusual y conexiones sin app conocida) y
`resumen.json` (por app: paquete, UID, sistema, versionCode,
uso_segundos, ultimo_uso, conexiones, datos móvil/wifi, acciones con
muestras, y proceso con PID/PPID/padre).

## Qué NO recoge

- Contenido de apps, mensajes, archivos ni cargas útiles de red:
  solo metadatos (paquetes, tiempos, extremos IP:puerto y
  contadores de bytes).
- Qué hace cada servicio, trabajo, alarma o wakelock por dentro:
  solo que existe, a qué app pertenece y (en la muestra) su nombre.
- La salida de `dumpsys` puede contener nombres de actividades o
  servicios con datos personales: trátala como material sensible.

## Uso

```bash
# Plan (sin cambios) y plan JSON
./src/android_toolchain/apps.sh --dry-run
./src/android_toolchain/apps.sh --dry-run --serial emulator-5554 --todas
./src/android_toolchain/apps.sh --plan-json

# Recogida real (exige --confirm)
./src/android_toolchain/apps.sh --serial emulator-5554 --confirm
./src/android_toolchain/apps.sh --serial emulator-5554 --todas --confirm
```

## Evidencia

Cada ejecución crea `~/security-tools/apps/APPS-AAAAMMDD-HHMMSS_<serial>/`
(0700) con los archivos de fuente (`01-apps-terceros.txt`,
`02-apps-sistema.txt` solo con `--todas`, `03-uso.txt`,
`04-conexiones.txt`, `05-datos.txt`, `06-servicios.txt`,
`07-trabajos.txt`, `08-alarmas.txt`, `09-wakelocks.txt`,
`10-procesos.txt`), `APPS.txt`, `resumen.json` y `MANIFIESTO.txt`
(comando, código, bytes y SHA-256 por fuente y por salida). Los
paquetes, UID y extremos de red son material sensible: consérvalos
según la autorización vigente y no los subas al repo.

## Formato de las fuentes (supuestos)

Los volcados de Android cambian entre versiones; el parser es
tolerante y documenta lo que asume:

- `pm list packages`: líneas `package:<pkg>[ versionCode:<n>][ uid:<n>]`.
- `dumpsys usagestats`: líneas `package[:=]<pkg>` seguidas de
  `lastTimeUsed` (época en ms o fecha) y `totalTimeInForeground`
  (ms o duración `1h 23m 45s`); si un paquete aparece varias veces
  se toma el mayor tiempo y el último uso más reciente.
- `dumpsys netstats`: bloques `iface=... ident=[{type=MOBILE|WIFI,
  ...}]` con `UID <n> set=...` y `rxBytes=/rb=` y `txBytes=/tb=`.
- `dumpsys activity services`: líneas `ServiceRecord{...}` con el
  componente dentro o fuera de las llaves.
- `dumpsys jobscheduler`: bloques `JOB #...` con el componente del
  servicio o el usuario `u0aNNN`.
- `dumpsys alarm`: bloques `Alarm{...}` con el paquete en la propia
  línea o en la línea `tag=`.
- `dumpsys power`: sección `Wake Locks:` con `uid=<n>` por línea.
- `ps -A -o PID,PPID,NAME`: cabecera `PID PPID NAME`; el fallback
  `ps -A` tiene columnas `USER PID PPID VSZ RSS WCHAN ADDR S NAME`.

Si un volcado no sigue estos formatos, la fuente queda como "sin
datos" y el resto del informe se genera igual.

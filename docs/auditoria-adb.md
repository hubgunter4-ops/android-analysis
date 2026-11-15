# Auditoría ADB — claves RSA, depuración, red, puerto 5555, fugas y apps depurables

Apartado para auditar, **antes de cualquier conexión**, si un dispositivo
de laboratorio autorizado es seguro para conectarse: qué equipos tienen
su clave RSA autorizada, si es depurable, qué expone en red, si el
puerto TCP 5555 escucha, si sus registros filtran datos sensibles y
qué apps de terceros son depurables. Cada comprobación queda en su
propio archivo, con `RESUMEN.txt` (veredicto OK / ADVERTENCIA /
CRÍTICO por comprobación) y `MANIFIESTO.txt` (comando, código, bytes
y SHA-256 por comprobación).

## Qué comprueba cada comprobación

| Comprobación | Qué hace | Archivo |
|---|---|---|
| `claves-rsa` | Lee `/data/misc/adb/adb_keys` (con `su` si no es legible directo), cuenta las claves, calcula la SHA-256 de cada una y la contrasta con la clave del operador (`~/.android/adbkey.pub` o `--expected-key`) | `01-claves-rsa-autorizadas.txt` |
| `propiedades-depuracion` | Lee con `getprop`: `ro.debuggable`, `ro.secure`, `ro.adb.secure`, `service.adb.tcp.port`, `persist.adb.tcp.port`, `sys.usb.config`, `persist.sys.usb.config`, `ro.build.type`, `ro.build.tags`, `ro.product.model`, `ro.build.version.release` | `02-propiedades-depuracion.txt` |
| `exposicion-red` | `ip addr show`, `ip route` y puertos TCP en escucha (`ss -tlnp`, fallback `netstat`, luego `/proc/net/tcp`) | `03-exposicion-red.txt` |
| `puerto-5555` | Estado interno en `/proc/net/tcp` y `/proc/net/tcp6` (puerto `15B3` en hexadecimal, estado `0A` = LISTEN) y sonda TCP desde la red a `<IP del dispositivo>:5555` | `04-puerto-5555.txt` |
| `fuga-datos` | Busca en logcat (main, system, events, crash) credenciales/tokens (`password`, `api_key`, `secret`, `access_token`, `Bearer …`), correos y RFC/CURP | `05-fuga-datos-sensibles.txt` |
| `apps-terceros` | `pm list packages -3` y `dumpsys package`: qué apps de terceros existen y cuáles tienen el flag `DEBUGGABLE` | `06-apps-terceros-depurables.txt` |

## Veredictos

- **OK**: sin hallazgos en esa comprobación.
- **ADVERTENCIA**: revisa antes de conectar (p. ej. `adb_keys` no legible
  sin root, un puerto en escucha fuera de loopback, PII en los registros).
- **CRÍTICO**: no conectes sin resolverlo. Lo dan una clave RSA
  desconocida autorizada, `ro.debuggable=1`, `ro.secure=0`, ADB por TCP
  en el 5555, el 5555 aceptando conexiones desde la red, credenciales o
  tokens en los registros, o una app de terceros depurable.

## Aleatorización

La auditoría no sigue siempre el mismo orden ni los mismos tiempos,
para que la sonda no tenga una firma predecible:

- el orden de las comprobaciones se baraja (Fisher-Yates) con una
  semilla (`--seed`; sin ella se genera una aleatoria por ejecución);
- hay una pausa aleatoria entre comprobaciones (0,2–1,5 s);
- el timeout de la sonda al 5555 es aleatorio (2–5 s);
- el orden de las IP sondeadas también se baraja.

Con la misma semilla, el plan (`--dry-run` o `--plan-json`) y la
ejecución usan el mismo orden. La semilla y el orden ejecutado quedan
registrados en `RESUMEN.txt` y en `MANIFIESTO.txt`.

## Uso

Desde la GUI, pestaña **AUDITORÍA ADB**: indica el serial (vacío exige
un único dispositivo), el directorio de evidencia, la clave del
operador, la semilla (vacío: aleatoria) y las comprobaciones, revisa la
vista previa dry-run y audita. La auditoría real pide confirmación.

Desde el CLI:

```bash
./src/no4nn.sh --audit --dry-run --serial emulator-5554
./src/no4nn.sh --audit --dry-run --serial emulator-5554 --audit-seed 42
./src/no4nn.sh --audit --plan-json --checks claves-rsa,puerto-5555
./src/no4nn.sh --audit --serial emulator-5554 --audit-confirm
./src/no4nn.sh --audit --serial emulator-5554 --audit-confirm --audit-sin-sonda-red
./src/no4nn.sh --audit --serial emulator-5554 --audit-confirm \
  --audit-expected-key ~/.android/adbkey.pub --audit-seed 42
```

El script directo también funciona:

```bash
./src/android_toolchain/audit.sh --dry-run
./src/android_toolchain/audit.sh --serial emulator-5554 --confirm
```

Sin `--dry-run` ni `--confirm`, la auditoría real se rechaza. `--audit`
no se combina con `--traces`, `--static-only` ni `--dynamic-only`, y no
instala nada.

## Salida

Cada auditoría crea `<out-dir>/AUDITORIA-AAAAMMDD-HHMMSS_<serial>/`
(directorio `0700`, archivos `0600`) con un archivo por comprobación,
su `.err` si el comando escribió en stderr, `RESUMEN.txt` con los
veredictos y `MANIFIESTO.txt` con fecha UTC, serial, semilla, comando,
código, bytes y SHA-256 por comprobación. La evidencia vive fuera del
árbol del proyecto (por defecto `~/security-tools/audits`); no se sube
a Git.

## Límites honestos

- No conecta dispositivos automáticamente: el serial debe aparecer
  como `device` en `adb devices`, y sin serial debe haber exactamente
  un dispositivo. La única sonda de red es un intento TCP (SYN) contra
  el 5555 de las IP del propio dispositivo, sin iniciar sesión ADB; se
  omite con `--sin-sonda-red` (o su casilla en la GUI).
- `/data/misc/adb/adb_keys` no es legible sin root en builds de
  usuario: en ese caso la comprobación lo indica y el veredicto es
  ADVERTENCIA (no se puede verificar qué equipos están autorizados).
  Con `su` se intenta una sola vez con timeout de 10 s.
- `fuga-datos` busca patrones, no entiende el contexto: un falso
  positivo es posible (p. ej. la palabra "secret" dentro de otra
  palabra) y una fuga con otro formato puede no detectarse. El registro
  crudo **nunca** se guarda: solo conteos por clase y muestras
  redactadas (fecha, tag y clase; el valor no se escribe). El temporal
  del registro se borra siempre al terminar.
- `apps-terceros` depende de `dumpsys package`, que en dispositivos
  con muchas apps puede tardar; el parseo busca el flag `DEBUGGABLE`
  en el bloque de cada paquete y lo cruza con la lista de terceros.
- Un plan, un dry-run o un diagnóstico no equivalen a una ejecución
  real ni a una vulnerabilidad confirmada. Un veredicto OK significa
  "sin hallazgos en lo revisado", no "dispositivo seguro".

## Solución de problemas

- `serial no aparece como 'device'`: verifica el serial con
  `adb devices`, la Depuración USB y la autorización RSA del equipo.
- `se esperaba exactamente un dispositivo`: indica `--serial` o
  desconecta los demás dispositivos/emuladores.
- `adb_keys no legible sin root`: repite la auditoría con un
  dispositivo rooteado o userdebug; sin eso no se puede contrastar
  las claves autorizadas.
- `auditoría real sin --confirm`: revisa primero el plan con
  `--dry-run` y añade `--confirm` (GUI: desmarca dry-run y confirma
  el diálogo).
- `la clave del operador no existe`: indica una ruta válida con
  `--audit-expected-key` o deja el campo vacío para auditar sin
  contraste (las claves se listan con su huella, pero no se marcan
  como conocidas o desconocidas).

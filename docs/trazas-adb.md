# Trazas ADB — procesos, fallos/errores y registro del kernel

Apartado para capturar, desde un dispositivo de laboratorio autorizado,
qué procesos están en ejecución, qué fallos y errores ha registrado el
sistema y qué dice el registro del kernel. Cada fuente queda en su
propio archivo, con un manifiesto que registra el comando exacto, el
código de salida, los bytes y el SHA-256 de cada archivo.

## Qué captura cada fuente

| Fuente | Comando | Archivo |
|---|---|---|
| `procesos` | `adb shell ps -A` | `01-procesos-ps-A.txt` |
| `procesos-top` | `adb shell top -n 1 -b` | `02-procesos-top.txt` |
| `logcat-errores` | `adb logcat -d -v threadtime *:E` | `03-logcat-errores.txt` |
| `logcat-crash` | `adb logcat -d -b crash -v threadtime` | `04-logcat-crash.txt` |
| `logcat-sistema` | `adb logcat -d -b system -b main -b events -v threadtime *:W` | `05-logcat-sistema.txt` |
| `kernel-dmesg` | `adb shell dmesg -T` (reintenta `dmesg` si `-T` falla) | `06-kernel-dmesg.txt` |
| `kernel-anterior` | `ls -l /sys/fs/pstore`, `cat /sys/fs/pstore/*`, fallback `cat /proc/last_kmsg` | `07-kernel-anterior-pstore.txt` |
| `fallos-dropbox` | `adb shell dumpsys dropbox --print` | `08-fallos-dropbox.txt` |
| `bugreport` | `adb bugreport` (solo con `--include-bugreport` o su casilla) | `09-bugreport.zip` |

Por defecto se capturan las ocho primeras; `bugreport` está apagado
porque es pesado y concentra datos sensibles del dispositivo.

## Uso

Desde la GUI, pestaña **TRAZAS ADB**: indica el serial (vacío exige
un único dispositivo), el directorio de evidencia y las fuentes, revisa
la vista previa dry-run y captura. La captura real pide confirmación.

Desde el CLI:

```bash
./src/no4nn.sh --traces --dry-run --serial emulator-5554
./src/no4nn.sh --traces --plan-json --sources procesos,kernel-dmesg
./src/no4nn.sh --traces --serial emulator-5554 --traces-confirm
./src/no4nn.sh --traces --serial emulator-5554 --traces-confirm \
  --traces-dir ~/security-tools/traces --traces-sources procesos,logcat-errores,kernel-dmesg
```

El script directo también funciona:

```bash
./src/android_toolchain/traces.sh --dry-run
./src/android_toolchain/traces.sh --serial emulator-5554 --confirm
```

Sin `--dry-run` ni `--confirm`, la captura real se rechaza. `--traces`
no se combina con `--static-only` ni `--dynamic-only` y no instala nada.

## Salida

Cada captura crea `<out-dir>/AAAAMMDD-HHMMSS_<serial>/` (directorio
`0700`, archivos `0600`) con un archivo por fuente, su `.err` si el
comando escribió en stderr, y `MANIFIESTO.txt` con fecha UTC, serial,
comando, código, bytes y SHA-256 por fuente. La evidencia vive fuera
del árbol del proyecto (por defecto `~/security-tools/traces`); no se
sube a Git.

## Límites honestos

- No conecta dispositivos automáticamente: el serial debe aparecer
  como `device` en `adb devices`, y sin serial debe haber exactamente
  un dispositivo. No se ejecuta ninguna aplicación objetivo.
- `dmesg` y `pstore` suelen necesitar root o permisos de sistema; si
  fallan, la captura sigue con el resto y lo registra en el manifiesto
  y en el `.err` de esa fuente.
- En kernels modernos `/proc/last_kmsg` es una ruta legacy: sale vacío
  por diseño. El registro del kernel anterior vive en `pstore` /
  `ramoops`; si el dispositivo no lo expone, el archivo lo indica.
- `logcat`, `dmesg` y `bugreport` pueden contener datos personales,
  tokens o credenciales en texto. Trátalos como material sensible:
  retención solo según la autorización vigente, sin subirlos al repo.
- Un plan, un dry-run o un diagnóstico no equivalen a una ejecución
  real ni a una vulnerabilidad confirmada.

## Solución de problemas

- `serial no aparece como 'device'`: verifica el serial con
  `adb devices`, la Depuración USB y la autorización RSA del equipo.
- `se esperaba exactamente un dispositivo`: indica `--serial` o
  desconecta los demás dispositivos/emuladores.
- `dmesg -T falló; reintentando con dmesg`: el dispositivo no acepta
  `-T`; si el segundo intento también falla, falta permiso (root).
- Archivo `07-...` con `sin archivos legibles en pstore`: el kernel no
  guardó un registro anterior o no es legible sin root.
- `captura real sin --confirm`: revisa primero el plan con `--dry-run`
  y añade `--confirm` (GUI: desmarca dry-run y confirma el diálogo).

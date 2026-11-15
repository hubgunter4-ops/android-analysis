# Conexión ADB

Verificar el estado de un dispositivo y forzar la conexión (USB y TCP),
solo sobre dispositivos de laboratorio autorizados y dentro del alcance
de laboratorio (`docs/alcance-laboratorio.md`).

## Qué hace

`src/android_toolchain/connect.sh`:

1. **Verifica** (solo lectura, no exige confirmación): versión y arranque
   del servidor ADB, `adb devices -l`, y por dispositivo `get-state`
   y modelo (`getprop ro.product.model`). Clasifica cada estado:
   `device` → CONECTADO, `unauthorized` → NO AUTORIZADO, `offline` →
   FUERA DE LÍNEA, sin permisos → SIN PERMISOS.
2. **Fuerza** (`--force`, exige `--confirm`): `adb kill-server`,
   `adb start-server`, `adb reconnect` y `adb wait-for-device` con
   timeout (`--timeout`, default 15 s, 1–300).
3. **Conecta por TCP** (`--tcp IP[:PUERTO]`, exige `--confirm`): `adb
   connect` contra una IP explícita del operador (puerto default 5555).
   Nunca se buscan dispositivos en la red: la IP se escribe a mano y
   debe estar en el alcance de laboratorio si hay archivo de alcance.
   El teléfono debe estar en la misma Wi-Fi que la estación.

Un dispositivo `unauthorized` **no se puede forzar**: la autorización
RSA se acepta en la pantalla del teléfono y no hay forma legítima de
saltársela. El reporte lo marca como NO AUTORIZADO y explica cómo
resolverlo (aceptar el diálogo de depuración USB, o revocar las
autorizaciones y volver a enchufar el USB).

## Uso

```bash
# Plan (sin cambios) y plan JSON
./src/android_toolchain/connect.sh --dry-run
./src/android_toolchain/connect.sh --dry-run --serial emulator-5554 --plan-json

# Solo verificación (no exige --confirm)
./src/android_toolchain/connect.sh --serial emulator-5554

# Forzar la conexión del dispositivo
./src/android_toolchain/connect.sh --serial emulator-5554 --force --confirm

# Conectar por TCP a una IP explícita
./src/android_toolchain/connect.sh --tcp 192.168.1.42 --confirm
./src/android_toolchain/connect.sh --tcp 192.168.1.42:5555 --force --confirm --timeout 30
```

Vía el instalador (`./src/no4nn.sh`), con las mismas reglas:

```bash
./src/no4nn.sh --connect --dry-run --serial emulator-5554
./src/no4nn.sh --connect --serial emulator-5554 --connect-force --connect-confirm
./src/no4nn.sh --connect --connect-tcp 192.168.1.42 --connect-confirm
```

En la GUI, la pestaña **CONEXIÓN ADB** tiene: serial con botón
**Detectar** (rellena el serial con el dispositivo visible), IP TCP,
alcance de laboratorio, forzar, espera máxima y directorio de
evidencia. **Verificar conexión** solo lee el estado; **Forzar
conexión** pide confirmación y ejecuta el plan.

## Evidencia

Cada ejecución crea `~/security-tools/connections/CONEXION-AAAAMMDD-HHMMSS_<serial|todos>/`
(0700) con `REPORTE.txt` (estado por dispositivo, salida de cada paso
y veredicto final) y `MANIFIESTO.txt` (código y SHA-256 del reporte).
Los seriales y modelos del reporte son material sensible: consérvalos
según la autorización vigente y no los subas al repo.

## Antes de conectar por TCP

El teléfono debe tener la depuración USB activada y estar en la misma
red Wi-Fi que la estación. En datos móviles no funciona: la IP del
operador no es alcanzable desde la LAN y el puerto 5555 no debe
exponerse a internet. Si `adb devices` no muestra el dispositivo,
revisa el cable, el puerto USB, la depuración USB y que sea el único
servidor ADB en ejecución.

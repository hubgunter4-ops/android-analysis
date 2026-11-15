# ENCRYPT — cifrado Android (verificar sistema + cifrar archivos)

Apartado para verificar el cifrado del sistema de un dispositivo de
laboratorio autorizado y cifrar/descifrar archivos, desde Ubuntu y
desde la app compañera DeviceCrypt en el dispositivo. Cada operación
deja `RESUMEN.txt` y `MANIFIESTO.txt` con comando, código, bytes y
SHA-256, en `~/security-tools/encrypt/<fecha>_<serial|local>/`
(directorio `0700`, archivos `0600`).

## Límite honesto: esto NO activa el cifrado del sistema

Desde Android 10 el cifrado es por archivos (FBE) y viene activo de
fábrica; lo controla el sistema, no una app ni ADB. Ninguna parte de
esta herramienta afirma activar el cifrado del sistema:

- Ubuntu solo **verifica** el estado con `getprop ro.crypto.state`,
  `ro.crypto.type`, `ro.crypto.fde_algorithm` y
  `ro.crypto.metadata.enabled`, y da el veredicto **CIFRADO /
  SIN CIFRAR / DESCONOCIDO**.
- La app DeviceCrypt solo **muestra** el estado con
  `DevicePolicyManager.getStorageEncryptionStatus()` (API pública).
- Si el dispositivo no está cifrado, la guía es ir a **Ajustes >
  Seguridad > Cifrado y credenciales** y seguir el asistente del
  sistema (exige batería y bloqueo de pantalla).

## Qué hace cada modo

| Modo | Qué hace | Requiere |
|---|---|---|
| `verify` | Lee `ro.crypto.*` por ADB y da el veredicto | Dispositivo `device` en `adb devices` |
| `encrypt-file` | Cifra un archivo local con OpenSSL AES-256-CBC + PBKDF2 | `--file`, `--password-file` (0600) |
| `decrypt-file` | Descifra un `.aes256` con la misma contraseña | `--file`, `--password-file` (0600) |
| `install-app` | Instala DeviceCrypt con `adb install -r` | Dispositivo `device`, APK presente |

Sin `--dry-run` ni `--confirm` la operación real se rechaza.
`--encrypt` no se combina con `--traces`, `--audit`, `--connect`,
`--analyze`, `--static-only` ni `--dynamic-only`. El serial se
contrasta con el alcance de laboratorio (`~/security-tools/scope`)
cuando se indica; sin archivo de alcance, la allowlist está inactiva.

## Formatos: dos rutas distintas, NO intercambiables

### Ubuntu: `.aes256` (OpenSSL)

```
openssl enc -aes-256-cbc -pbkdf2 -salt -pass file:<archivo-0600>
```

Salida con cabecera `Salted__` + salt de 8 bytes. La clave se deriva
de la contraseña con PBKDF2. La contraseña nunca va en argv ni en el
log: solo `-pass file:<archivo-0600>`. Con
`--delete-password-file` el script borra ese archivo tras usarlo
(solo en ejecución real, nunca en dry-run). **Sin la contraseña el
archivo no se puede recuperar.**

### App DeviceCrypt: `.crypt` (Android Keystore)

```
magic "DCRYPT01" (8 bytes) + IV aleatorio (12 bytes)
+ ciphertext con el tag GCM de 16 bytes al final
```

Algoritmo: AES/GCM/NoPadding, clave AES de 256 bits generada en el
Android Keystore (alias `DeviceCryptKey`), que nunca sale del
Keystore. Si se borra la clave o se restablece el dispositivo, los
`.crypt` ya no se pueden descifrar. La app no cifra con contraseña:
usa la clave del Keystore.

**Un archivo `.aes256` de Ubuntu no lo abre la app, y un `.crypt` de
la app no lo abre Ubuntu.** Son dos rutas con distinta gestión de
claves, documentadas aquí a propósito para no mezclarlas.

## Uso

Desde la GUI, pestaña **ENCRYPT**: indica el serial (vacío exige un
único dispositivo), el modo, el archivo y la contraseña para
cifrar/descifrar, revisa la vista previa dry-run y ejecuta. La
contraseña se escribe en un archivo temporal 0600 que el script borra
tras usarla. El botón **Instalar app en dispositivo** instala
`android-app/app-debug.apk` (DeviceCrypt 1.0,
`com.zapia.devicecrypt`).

Desde el CLI:

```bash
./src/no4nn.sh --encrypt --dry-run --serial emulator-5554
./src/no4nn.sh --encrypt --serial emulator-5554 --encrypt-confirm
./src/no4nn.sh --encrypt --plan-json --encrypt-mode encrypt-file --encrypt-file /tmp/nota.txt
./src/no4nn.sh --encrypt --encrypt-mode encrypt-file --encrypt-file ~/nota.txt \
  --encrypt-password-file ~/.config/devicecrypt.pw --encrypt-confirm
./src/no4nn.sh --encrypt --encrypt-mode decrypt-file --encrypt-file ~/nota.txt.aes256 \
  --encrypt-password-file ~/.config/devicecrypt.pw --encrypt-confirm
./src/no4nn.sh --encrypt --encrypt-mode install-app --serial emulator-5554 --encrypt-confirm
```

El script directo también funciona:

```bash
./src/android_toolchain/encrypt.sh --dry-run
./src/android_toolchain/encrypt.sh --mode encrypt-file --file ~/nota.txt \
  --password-file ~/.config/devicecrypt.pw --confirm
```

Crea el archivo de contraseña así (nunca lo subas a Git):

```bash
printf 'tu-contraseña-larga' > ~/.config/devicecrypt.pw
chmod 600 ~/.config/devicecrypt.pw
```

El script rechaza el archivo si no tiene permisos 400 o 600.

## La app DeviceCrypt (android-app/)

App Java sin dependencias, paquete `com.zapia.devicecrypt`, minSdk 26,
targetSdk 34, versión 1.0 (versionCode 1). Sin permisos de red ni
root. Pantalla única dentro de un `ScrollView`:

- Estado del cifrado del sistema (solo lectura) y botón de actualizar.
- Elegir archivo a cifrar / a descifrar (selector del sistema, SAF):
  la app solo ve los archivos que tú eliges.
- Cifrar / Descifrar: el destino se elige con el selector del
  sistema; el trabajo pesado corre fuera del hilo de interfaz.
- Borrar el original: solo con confirmación explícita en un diálogo,
  después de cifrar.
- Lista de archivos `.crypt` de la sesión y registro de operaciones.

Compilación canónica en CI (`assembleDebug`, job `android-app`).
Compilación manual en local (el daemon de Gradle no arranca en esta
VM): `./android-app/build-local.sh` (aapt2 + javac + d8 + zipalign +
apksigner, con JDK 17 y el SDK). La APK debug queda en
`android-app/app-debug.apk` y es la que instala el modo
`install-app` y la pestaña ENCRYPT.

Llamadas framework verificadas contra el SDK público (todas existen
en el SDK para el nivel objetivo; sin APIs ocultas ni reflexión):

- `DevicePolicyManager.getStorageEncryptionStatus()` (API 11)
- `KeyStore.getInstance("AndroidKeyStore")` (API 18)
- `KeyGenerator.getInstance("AES", "AndroidKeyStore")` (API 23)
- `KeyGenParameterSpec.Builder` con `BLOCK_MODE_GCM` y
  `ENCRYPTION_PADDING_NONE`, clave de 256 bits (API 23)
- `Cipher.getInstance("AES/GCM/NoPadding")` y
  `GCMParameterSpec(128, iv)` (API 19)
- `Intent.ACTION_OPEN_DOCUMENT` / `ACTION_CREATE_DOCUMENT` (API 19)
- `DocumentsContract.deleteDocument()` (API 19)
- `ContentResolver.openInputStream()` / `openOutputStream()`
- `startActivityForResult` (obsoleto desde API 30 pero público y
  vigente; se usa para no depender de AndroidX)

## Salida

Cada operación crea `<out-dir>/AAAAMMDD-HHMMSS_<serial|local>/` con
`RESUMEN.txt` (veredicto o algoritmo, archivos y SHA-256) y
`MANIFIESTO.txt`. En `verify`, además, `01-cifrado-sistema.txt` con
cada propiedad `ro.crypto.*` y el veredicto. En `install-app`,
`01-instalar-app.txt` con la salida de `adb install` (debe contener
`Success`). En `encrypt-file` / `decrypt-file`, el archivo de salida
queda donde indique `--out` (por defecto `<entrada>.aes256` al
cifrar; al descifrar quita `.aes256` o añade `.dec`).

## Qué NO se pudo verificar en vivo

Sin adb/USB en esta VM y con el Redmi en datos móviles, no se pudo
probar `verify` ni `install-app` contra un dispositivo real: ambas
rutas se verificaron con un adb falso (veredicto CIFRADO y `Success`
de instalación simulados) y la ruta de archivos con un roundtrip
OpenSSL real. La instalación en el Redmi y el cifrado con la app
quedan pendientes de probar en la estación donde esté enchufado el
teléfono.

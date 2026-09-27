# Revisión de seguridad y código — `android-analysis`

**Fecha:** 2026-09-26  
**Commit revisado:** `89b71e9efb2e00b9a5142bfb2c57ba61e3bcfe52`  
**Alcance:** scripts Bash, GUI Tkinter, catálogo de acciones ADB, empaquetado Debian, pruebas y artefacto `.deb` incluido.

## Resumen ejecutivo

El repositorio está razonablemente bien estructurado para una herramienta de laboratorio autorizada: usa `subprocess.Popen()` con listas de argumentos en la GUI, evita `shell=True`, cita las variables Bash en las ejecuciones principales, solicita confirmación para la mayoría de las acciones mutables y no contiene credenciales detectables.

No obstante, **no recomendaría instalarlo sin corregir primero la cadena de suministro**. El instalador descarga e instala componentes no fijados a versiones o hashes reproducibles, incluyendo paquetes Python, clones Git y el release `latest` de JADX. Un compromiso de PyPI/GitHub, un repositorio sustituido o una nueva versión maliciosa podría ejecutar código en la estación del operador.

También existe un **escape de ruta reproducible** en la validación de `--tools-dir`, y la GUI clasifica como “solo lectura” algunas operaciones ADB que pueden revelar información sensible o generar artefactos de gran tamaño sin mostrar confirmación.

## Estado posterior a la remediación

Se aplicaron las correcciones en el árbol de trabajo: JADX quedó fijado a v1.5.6 con SHA-256 obligatorio, dex2jar y MobSF a commits concretos, las dependencias Python directas y transitivas quedaron en `requirements.lock` con hashes y `pip --require-hashes`, se corrigió el traversal de rutas, las capturas/logs/SQLite/bugreports vuelven a pedir confirmación, y el empaquetado normaliza permisos. La suite ampliada, la comprobación de resolución de pip en dry-run, la sintaxis Bash/Python y la inspección del `.deb` pasan correctamente.

## Hallazgos priorizados

| ID | Severidad | Estado | Hallazgo |
|---|---|---|---|
| SEC-01 | Alta | Abierto | Dependencias externas no fijadas ni verificadas de forma obligatoria |
| SEC-02 | Media | Abierto | Validación incompleta de traversal en `--tools-dir` |
| SEC-03 | Media | Abierto | Acciones ADB sensibles sin confirmación en la GUI |
| Q-01 | Baja | Abierto | Artefacto Debian conserva permisos `0600` para un documento de uso |
| Q-02 | Baja | Abierto | Cobertura de pruebas insuficiente para la GUI y la cadena de suministro |

## Detalle de hallazgos

### SEC-01 — Dependencias externas no fijadas ni verificadas obligatoriamente

**Severidad:** Alta en estaciones de análisis con privilegios o datos sensibles.

**Evidencia:**

- `src/android_toolchain/core.sh:203-207` consulta la API de GitHub y descarga el primer release `*-all.zip` de JADX, sin fijar una versión.
- `src/android_toolchain/core.sh:208-212` solo verifica el hash si el usuario define `JADX_SHA256`; por defecto continúa sin checksum criptográfico.
- `src/android_toolchain/core.sh:219` clona `dex2jar` desde la rama/estado por defecto con `--depth 1`, sin commit, tag ni firma fijados.
- `src/android_toolchain/core.sh:236-238` instala con `pip install --user --upgrade` seis paquetes sin versiones ni hashes.
- `src/android_toolchain/core.sh:246` clona MobSF igualmente sin revisión fija.
- No hay `requirements.txt`, `pyproject.toml`, lockfile ni manifiesto de hashes.

**Impacto:** la instalación no es reproducible y la confianza efectiva se delega a cambios futuros de PyPI/GitHub. La ejecución de una herramienta comprometida puede afectar al usuario y leer APKs, capturas, tokens de sesión o archivos de laboratorio.

**Recomendación:**

1. Fijar versiones exactas y, preferiblemente, hashes para todos los paquetes Python.
2. Fijar JADX a una versión concreta y hacer obligatorio el SHA-256 publicado en el repositorio.
3. Fijar `dex2jar` y MobSF a commits o tags inmutables; validar el commit después del clone.
4. Preferir un artefacto interno o mirror verificable para una estación de auditoría.
5. Rechazar la instalación si falta un hash esperado, en vez de solo registrar un warning.
6. Añadir un SBOM y un proceso documentado de actualización de dependencias.

### SEC-02 — Escape de ruta mediante traversal relativo

**Severidad:** Media.

**Evidencia:** `validate_path()` en `src/android_toolchain/core.sh:109-113` intenta rechazar `..`, pero solo cubre algunos patrones. La entrada `foo/../../outside` pasa la validación. Después, en `src/android_toolchain/core.sh:299-311`, se convierte en una ruta bajo `$PWD` y se ejecuta `mkdir -p`.

Prueba reproducible realizada:

```text
$ bash src/no4nn.sh --dry-run --plan-json --static-only \
    --tools-dir foo/../../outside
# acepta la ruta y produce /home/ubuntu/android-analysis/foo/../../outside
```

En una instalación real, los clones y herramientas pueden terminar fuera de la raíz prevista. La validación actual tampoco canonicaliza symlinks ni verifica que la ruta final permanezca dentro de una raíz permitida.

**Recomendación:**

- Convertir la ruta a una ruta absoluta canónica antes de usarla (`realpath -m` con cuidado, o una función equivalente).
- Rechazar cualquier componente `..` por segmento, no solo tres formas parciales.
- Si se necesita una raíz controlada, verificar con `realpath` que el destino esté dentro de `$HOME/security-tools` o de la raíz explícitamente autorizada.
- Considerar aceptar únicamente rutas absolutas para el modo no interactivo.
- Añadir casos de prueba para `a/../../b`, `a/../..`, symlinks y rutas existentes.

### SEC-03 — Operaciones ADB sensibles marcadas como solo lectura

**Severidad:** Media, principalmente por confidencialidad y riesgo operativo.

**Evidencia:** `src/no4nn_gui.py:20-34` incluye `screencap`, `logcat`, `sqlite3` y `bugreport` en `READ_ONLY`. `src/no4nn_gui.py:280-285` omite la confirmación para esos comandos.

Aunque no sean necesariamente mutaciones del dispositivo, pueden:

- exponer pantalla, logs, bases de datos y datos de aplicaciones;
- producir informes muy grandes o con información personal/credenciales;
- crear o sobrescribir archivos según los argumentos usados;
- generar evidencia que debe estar dentro del alcance y la política de retención.

Además, el campo de argumentos adicionales (`src/no4nn_gui.py:307-309`) acepta opciones ADB controladas por el operador y se ejecuta sin una política adicional de destino, aunque correctamente como `argv` y no como shell.

**Recomendación:**

- Separar “no mutante” de “no sensible”.
- Pedir confirmación para `bugreport`, `logcat`, `sqlite3`, `screencap`, `pull`, `shell`, `connect`, `pair`, `forward`, `reverse` y cualquier captura/exportación.
- Mostrar una advertencia de posible exposición de datos y solicitar un directorio de salida aprobado.
- Limitar o validar argumentos adicionales; no permitir que cambien silenciosamente el host/puerto del servidor ADB si no es necesario.
- Registrar serial, acción, hora y resultado en un log protegido, sin almacenar secretos en texto plano.

## Problemas de calidad y hardening

### Q-01 — Permisos `0600` en el paquete Debian

El artefacto versionado contiene `docs/Funciones_de_ADB_por_módulo.md` con permisos `0600` según `dpkg-deb -c`. El script `packaging/build-deb.sh:11-13` usa `cp -a`, conservando permisos de origen. El paquete instala el documento como root y otros usuarios pueden no poder leerlo.

**Recomendación:** normalizar permisos del árbol empaquetado (`0644` para documentos, `0755` solo para ejecutables) y añadir una prueba que inspeccione el contenido del `.deb`.

### Q-02 — Pruebas insuficientes

`tests/test_installer.sh` valida sintaxis, ayuda, dry-run, opciones y algunos rechazos, pero no cubre:

- traversal con componentes intermedios;
- symlinks y rutas canónicas;
- clasificación de acciones sensibles de la GUI;
- construcción y permisos del `.deb`;
- verificación obligatoria de hashes;
- fijación de versiones o commits;
- comportamiento de cancelación y errores del proceso en la GUI.

El análisis estático ejecutado confirmó que Bash y Python compilan y que las pruebas actuales pasan. `shellcheck` y `lintian` no estaban instalados en el sandbox, por lo que no se pudo ejecutar esa validación adicional.

## Controles positivos observados

- No se detectaron claves, tokens, contraseñas ni claves privadas en el árbol ni en el historial Git revisado.
- `git fsck --full` no reportó objetos corruptos.
- La GUI usa `subprocess.Popen(command, ...)` con una lista de argumentos y no usa `shell=True`.
- La GUI usa `shlex.split()` para separar argumentos; no se observó concatenación en un shell.
- La mayoría de las variables y argumentos Bash están entrecomillados.
- ADB no se conecta ni ejecuta una aplicación objetivo automáticamente durante la instalación.
- Se impide combinar `--static-only` y `--dynamic-only`.
- Las pruebas existentes pasan y `python3 -m py_compile src/no4nn_gui.py` finaliza correctamente.

## Plan de corrección recomendado

1. **Antes de distribuir:** corregir SEC-01 y SEC-02; hacer fallar la instalación sin hashes/versionset aprobado.
2. **Antes de usar en un laboratorio real:** corregir SEC-03 y definir una política de destino, retención y red ADB.
3. **En el próximo cambio:** normalizar permisos del `.deb`, añadir pruebas de packaging y ampliar la matriz de pruebas de rutas.
4. **Proceso continuo:** revisión de dependencias, SBOM, actualización firmada y CI con ShellCheck, Lintian, análisis de secretos y pruebas de instalación en una VM limpia.

## Verificaciones ejecutadas

- `bash tests/test_installer.sh` — OK.
- `bash -n src/no4nn.sh` y `bash -n src/android_toolchain/core.sh` — OK.
- `python3 -m py_compile src/no4nn_gui.py` — OK.
- `git fsck --full --no-reflogs` — OK.
- Búsqueda de secretos en el árbol e historial revisado — sin coincidencias relevantes.
- `git diff --check` — OK.
- Inspección de contenido y metadatos del paquete Debian — completada.

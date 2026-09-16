# Recomendaciones de automatización para Claude Code

El repositorio es un instalador Bash con una interfaz Tkinter opcional. Estas recomendaciones priorizan seguridad, regresión y revisión de cambios sin alterar el flujo operativo.

## Perfil del código

- **Runtime:** Bash y Python 3/Tkinter.
- **Entrada principal:** `install.sh` y `src/no4nn.sh`.
- **Lógica:** `src/android_toolchain/core.sh`.
- **Pruebas:** `tests/test_installer.sh`.
- **Riesgo operativo:** APT, `sudo`, clones Git, descargas HTTPS y herramientas de análisis dinámico.

## Hooks

### Validación después de editar shell o Python

Configurar un hook `PostToolUse` que ejecute `bash -n` sobre los scripts Bash y `python3 -m py_compile` sobre los archivos Python modificados. Para este repositorio, la prueba completa debe ejecutarse después de cambios en `core.sh`, `no4nn.sh` o la GUI.

### Protección de operaciones sensibles

Configurar un hook `PreToolUse` que bloquee ediciones automáticas de credenciales, certificados, capturas y artefactos de laboratorio (`.env`, `*.pem`, `*.key`, `evidence/`, `screenshots/`). El bloqueo complementa el `.gitignore`; no lo sustituye.

## Subagentes

### `shell-safety-reviewer`

Revisar expansión de variables, validación de rutas, quoting, uso de `sudo`, descargas, traps y condiciones de dry-run. Debe rechazar cualquier cambio que conecte dispositivos o ejecute aplicaciones objetivo automáticamente.

### `ui-accessibility-reviewer`

Revisar la GUI Tkinter en ejecución o mediante lectura de código: navegación por teclado, estados disabled/running, contraste, cancelación de subprocesos, mensajes de confirmación y funcionamiento cuando `python3-tk` no está instalado.

## Skills

### `installer-regression`

Skill específica para ejecutar el conjunto de pruebas, validar `--help`, generar planes JSON y comprobar que `--dry-run` no modifica el host. Invocación sugerida: `/installer-regression`.

### `authorized-lab-ops`

Skill de contexto para mantener explícitos el alcance autorizado, la revisión del plan y el cleanup. Debe ser informativa y no tener invocación automática para impedir acciones operativas accidentales.

## MCP servers

- **GitHub:** útil para revisar issues, PRs y Actions del repositorio.
- **Playwright:** no es necesario para la GUI nativa; solo recomendarlo si se añade una interfaz web.
- **Context7:** útil para consultar documentación actualizada de Tkinter, Bash y librerías incorporadas.

Estas recomendaciones son deliberadamente conservadoras: la interfaz gráfica facilita la operación, pero no debe convertir una instalación autorizada en una acción automática sin revisión humana.

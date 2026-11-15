"""Vista de auditoría ADB: claves RSA, depuración, red y puerto 5555."""
from __future__ import annotations

import os
import tkinter as tk
from collections.abc import Callable
from tkinter import messagebox, ttk

from . import theme

# Comprobación -> (etiqueta, activada por defecto).
CHECKS: tuple[tuple[str, str, bool], ...] = (
    ("claves-rsa", "Claves RSA autorizadas · /data/misc/adb/adb_keys", True),
    ("propiedades-depuracion", "Propiedades de depuración · getprop", True),
    ("exposicion-red", "Exposición en red · interfaces y puertos en escucha", True),
    ("puerto-5555", "Puerto TCP 5555 · estado interno + sonda de red", True),
    ("fuga-datos", "Fuga de datos sensibles · tokens, PII", True),
    ("apps-terceros", "Apps de terceros depurables · pm + dumpsys package", True),
)


class AuditView(ttk.Frame):
    """Cuarta pestaña: auditoría ADB antes de cualquier conexión."""

    def __init__(self, parent: tk.Misc,
                 on_start: Callable[[list[str], str, tk.Text], None],
                 on_cancel: Callable[[], None]) -> None:
        super().__init__(parent, style="App.TFrame", padding=(0, 12, 0, 0))
        self.on_start = on_start
        self.on_cancel = on_cancel
        self.serial = tk.StringVar()
        self.out_dir = tk.StringVar(value=os.path.expanduser("~/security-tools/audits"))
        self.expected_key = tk.StringVar(value=os.path.expanduser("~/.android/adbkey.pub"))
        self.seed = tk.StringVar()
        self.no_network_probe = tk.BooleanVar(value=False)
        self.dry_run = tk.BooleanVar(value=True)
        self.check_vars: dict[str, tk.BooleanVar] = {
            key: tk.BooleanVar(value=default) for key, _label, default in CHECKS
        }
        self._build()

    def _build(self) -> None:
        self.columnconfigure(0, weight=0, minsize=320)
        self.columnconfigure(1, weight=1)
        self.rowconfigure(0, weight=1)
        # La tarjeta es más alta que la ventana con las seis comprobaciones:
        # va dentro de un lienzo con barra de desplazamiento.
        container = ttk.Frame(self, style="App.TFrame")
        container.grid(row=0, column=0, sticky="nsew", padx=(0, 16))
        container.columnconfigure(0, weight=1)
        container.rowconfigure(0, weight=1)
        canvas = tk.Canvas(container, bg=theme.BG, highlightthickness=0)
        scroll = ttk.Scrollbar(container, orient="vertical", command=canvas.yview)
        canvas.configure(yscrollcommand=scroll.set)
        canvas.grid(row=0, column=0, sticky="nsew")
        scroll.grid(row=0, column=1, sticky="ns")
        card = ttk.Frame(canvas, style="Card.TFrame", padding=22)
        window = canvas.create_window((0, 0), window=card, anchor="nw")
        card.bind("<Configure>", lambda _e: canvas.configure(scrollregion=canvas.bbox("all")))
        canvas.bind("<Configure>", lambda e: canvas.itemconfigure(window, width=e.width))
        card.columnconfigure(0, weight=1)
        ttk.Label(card, text="AUDITORÍA ADB", style="Section.TLabel").grid(row=0, column=0, sticky="w")
        ttk.Label(card, text="Claves RSA, depuración, red y puerto 5555", style="CardTitle.TLabel").grid(
            row=1, column=0, sticky="w", pady=(4, 6))
        ttk.Label(card, text="Antes de conectar: qué equipos están autorizados, si el dispositivo "
                             "es depurable y si el 5555 escucha en la red. Veredicto por comprobación.",
                  style="Muted.TLabel", wraplength=295).grid(row=2, column=0, sticky="w", pady=(0, 14))
        ttk.Label(card, text="1  ·  DISPOSITIVO", style="Section.TLabel").grid(row=3, column=0, sticky="w")
        ttk.Label(card, text="Serial (vacío: exige un único dispositivo)", style="Panel.TLabel").grid(
            row=4, column=0, sticky="w", pady=(6, 4))
        ttk.Entry(card, textvariable=self.serial, style="Panel.TEntry").grid(row=5, column=0, sticky="ew")
        ttk.Label(card, text="2  ·  DIRECTORIO DE EVIDENCIA", style="Section.TLabel").grid(
            row=6, column=0, sticky="w", pady=(10, 6))
        ttk.Entry(card, textvariable=self.out_dir, style="Panel.TEntry").grid(row=7, column=0, sticky="ew")
        ttk.Label(card, text="Cada auditoría crea una subcarpeta con fecha y serial (0700).",
                  style="Muted.TLabel", wraplength=295).grid(row=8, column=0, sticky="w", pady=(5, 0))
        ttk.Label(card, text="3  ·  CLAVE DEL OPERADOR", style="Section.TLabel").grid(
            row=9, column=0, sticky="w", pady=(10, 6))
        ttk.Entry(card, textvariable=self.expected_key, style="Panel.TEntry").grid(row=10, column=0, sticky="ew")
        ttk.Label(card, text="Tu .pub para contrastar las claves autorizadas (vacío: sin contraste).",
                  style="Muted.TLabel", wraplength=295).grid(row=11, column=0, sticky="w", pady=(5, 0))
        ttk.Label(card, text="4  ·  COMPROBACIONES", style="Section.TLabel").grid(row=12, column=0, sticky="w", pady=(10, 6))
        row = 13
        for key, label, _default in CHECKS:
            ttk.Checkbutton(card, text=label, variable=self.check_vars[key],
                            style="Panel.TCheckbutton").grid(row=row, column=0, sticky="w", pady=2)
            row += 1
        ttk.Label(card, text="Semilla de aleatorización (vacío: aleatoria por ejecución)",
                  style="Panel.TLabel").grid(row=row, column=0, sticky="w", pady=(6, 2))
        row += 1
        ttk.Entry(card, textvariable=self.seed, style="Panel.TEntry").grid(row=row, column=0, sticky="ew")
        row += 1
        ttk.Checkbutton(card, text="Omitir la sonda de red al 5555 (solo estado interno)",
                        variable=self.no_network_probe,
                        style="Panel.TCheckbutton").grid(row=row, column=0, sticky="w", pady=(6, 2))
        row += 1
        ttk.Checkbutton(card, text="Vista previa / dry-run (no llama a adb)", variable=self.dry_run,
                        style="Panel.TCheckbutton").grid(row=row, column=0, sticky="w", pady=(2, 2))
        row += 1
        ttk.Separator(card).grid(row=row, column=0, sticky="ew", pady=10)
        row += 1
        ttk.Button(card, text="VISTA PREVIA  ·  DRY-RUN", command=self.run_preview,
                   style="Accent.TButton").grid(row=row, column=0, sticky="ew", pady=(0, 6))
        row += 1
        ttk.Button(card, text="Auditar dispositivo", command=self.run_audit,
                   style="Secondary.TButton").grid(row=row, column=0, sticky="ew", pady=(0, 6))
        row += 1
        self.cancel_button = ttk.Button(card, text="Cancelar proceso", command=self.on_cancel,
                                        state="disabled", style="Danger.TButton")
        self.cancel_button.grid(row=row, column=0, sticky="ew")
        row += 1
        ttk.Label(card, text="No inicia sesión ADB. Un CRÍTICO en claves o en el 5555 significa que el "
                             "dispositivo puede aceptar conexiones no autorizadas.",
                  style="Muted.TLabel", wraplength=295).grid(row=row, column=0, sticky="w", pady=(10, 0))

        self.output = theme.make_output(
            self, 0, "SALIDA DE AUDITORÍA", "Progreso en vivo · resumen y manifiesto al terminar",
            on_clear=self.clear_output, on_copy=self.copy_output,
        )
        self.set_output("$ terminal de auditoría esperando una operación…\n\nListo. Revisa el plan dry-run antes de auditar.\n")

    def selected_checks(self) -> list[str]:
        return [key for key, _label, _default in CHECKS if self.check_vars[key].get()]

    def command(self) -> list[str]:
        command = ["bash", "src/android_toolchain/audit.sh"]
        if self.serial.get().strip():
            command.extend(["--serial", self.serial.get().strip()])
        command.extend(["--out-dir", self.out_dir.get(), "--checks", ",".join(self.selected_checks())])
        if self.expected_key.get().strip() and os.path.isfile(self.expected_key.get().strip()):
            # Solo se pasa si el archivo existe: si no, audit.sh audita
            # sin contraste en vez de rechazar la operación.
            command.extend(["--expected-key", self.expected_key.get().strip()])
        if self.seed.get().strip():
            command.extend(["--seed", self.seed.get().strip()])
        if self.no_network_probe.get():
            command.append("--sin-sonda-red")
        return command

    def run_preview(self) -> None:
        if not self.selected_checks():
            messagebox.showinfo("Sin comprobaciones", "Selecciona al menos una comprobación.")
            return
        self.on_start(self.command() + ["--dry-run"], "vista previa de auditoría", self.output)

    def run_audit(self) -> None:
        if not self.selected_checks():
            messagebox.showinfo("Sin comprobaciones", "Selecciona al menos una comprobación.")
            return
        if self.dry_run.get():
            self.run_preview()
            return
        checks = ", ".join(self.selected_checks())
        if not messagebox.askyesno(
                "Confirmar auditoría ADB",
                f"Serial: {self.serial.get().strip() or 'único dispositivo'}\n"
                f"Destino: {self.out_dir.get()}\nComprobaciones: {checks}\n\n"
                "La auditoría lee las claves RSA autorizadas y sondea el puerto 5555 "
                "desde la red. Úsala únicamente sobre un dispositivo autorizado "
                "y conserva la evidencia según el alcance.",
                icon="warning"):
            return
        self.on_start(self.command() + ["--confirm"], "auditando dispositivo", self.output)

    def set_running(self, running: bool) -> None:
        self.cancel_button.configure(state="normal" if running else "disabled")

    def set_output(self, text: str) -> None:
        self.output.configure(state="normal")
        self.output.delete("1.0", "end")
        self.output.insert("end", text)
        self.output.see("end")
        self.output.configure(state="disabled")

    def clear_output(self) -> None:
        self.set_output("$ terminal limpia\n\nListo para una nueva operación.\n")

    def copy_output(self) -> None:
        text = self.output.get("1.0", "end-1c")
        self.clipboard_clear()
        self.clipboard_append(text)

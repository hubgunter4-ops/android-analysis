"""Vista de trazas ADB: procesos, fallos/errores y registro del kernel."""
from __future__ import annotations

import os
import tkinter as tk
from collections.abc import Callable
from tkinter import messagebox, ttk

from . import device_detect, theme

# Fuente -> (etiqueta, activada por defecto). `bugreport` apagado por
# defecto: es pesado y concentra datos sensibles del dispositivo.
SOURCES: tuple[tuple[str, str, bool], ...] = (
    ("procesos", "Procesos · ps -A", True),
    ("procesos-top", "Procesos por CPU/memoria · top", True),
    ("logcat-errores", "Fallos y errores · logcat *:E", True),
    ("logcat-crash", "Crashes · logcat -b crash", True),
    ("logcat-sistema", "Sistema · logcat system/main/events *:W", True),
    ("kernel-dmesg", "Kernel en vivo · dmesg", True),
    ("kernel-anterior", "Kernel anterior · pstore / last_kmsg", True),
    ("fallos-dropbox", "Fallos y ANR · dumpsys dropbox", True),
    ("bugreport", "Bugreport completo (pesado y sensible)", False),
)


class TracesView(ttk.Frame):
    """Tercera pestaña: captura de trazas ADB a archivos de evidencia."""

    def __init__(self, parent: tk.Misc,
                 on_start: Callable[[list[str], str, tk.Text], bool],
                 on_cancel: Callable[[], None]) -> None:
        super().__init__(parent, style="App.TFrame", padding=(0, 12, 0, 0))
        self.on_start = on_start
        self.on_cancel = on_cancel
        self.serial = tk.StringVar()
        self.out_dir = tk.StringVar(value=os.path.expanduser("~/security-tools/traces"))
        self.dry_run = tk.BooleanVar(value=True)
        self.source_vars: dict[str, tk.BooleanVar] = {
            key: tk.BooleanVar(value=default) for key, _label, default in SOURCES
        }
        self._build()

    def _build(self) -> None:
        self.columnconfigure(0, weight=0, minsize=320)
        self.columnconfigure(1, weight=1)
        self.rowconfigure(0, weight=1)
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
        ttk.Label(card, text="TRAZAS ADB", style="Section.TLabel").grid(row=0, column=0, sticky="w")
        ttk.Label(card, text="Procesos, fallos y kernel a archivos", style="CardTitle.TLabel").grid(
            row=1, column=0, sticky="w", pady=(4, 6))
        ttk.Label(card, text="Cada fuente queda en su propio archivo con manifiesto y SHA-256.",
                  style="Muted.TLabel", wraplength=295).grid(row=2, column=0, sticky="w", pady=(0, 14))
        ttk.Label(card, text="1  ·  DISPOSITIVO", style="Section.TLabel").grid(row=3, column=0, sticky="w")
        ttk.Label(card, text="Serial (vacío: exige un único dispositivo)", style="Panel.TLabel").grid(
            row=4, column=0, sticky="w", pady=(6, 4))
        serial_row = ttk.Frame(card, style="Card.TFrame")
        serial_row.grid(row=5, column=0, sticky="ew")
        serial_row.columnconfigure(0, weight=1)
        ttk.Entry(serial_row, textvariable=self.serial, style="Panel.TEntry").grid(row=0, column=0, sticky="ew")
        ttk.Button(serial_row, text="Detectar", command=self.detect_device,
                   style="Secondary.TButton").grid(row=0, column=1, padx=(8, 0))
        ttk.Label(card, text="2  ·  DIRECTORIO DE EVIDENCIA", style="Section.TLabel").grid(
            row=6, column=0, sticky="w", pady=(16, 8))
        ttk.Entry(card, textvariable=self.out_dir, style="Panel.TEntry").grid(row=7, column=0, sticky="ew")
        ttk.Label(card, text="Cada captura crea una subcarpeta con fecha y serial (0700).",
                  style="Muted.TLabel", wraplength=295).grid(row=8, column=0, sticky="w", pady=(5, 0))
        ttk.Label(card, text="3  ·  FUENTES", style="Section.TLabel").grid(row=9, column=0, sticky="w", pady=(16, 8))
        row = 10
        for key, label, _default in SOURCES:
            ttk.Checkbutton(card, text=label, variable=self.source_vars[key],
                            style="Panel.TCheckbutton").grid(row=row, column=0, sticky="w", pady=2)
            row += 1
        ttk.Checkbutton(card, text="Vista previa / dry-run (no llama a adb)", variable=self.dry_run,
                        style="Panel.TCheckbutton").grid(row=row, column=0, sticky="w", pady=(14, 3))
        row += 1
        ttk.Separator(card).grid(row=row, column=0, sticky="ew", pady=14)
        row += 1
        ttk.Button(card, text="VISTA PREVIA  ·  DRY-RUN", command=self.run_preview,
                   style="Accent.TButton").grid(row=row, column=0, sticky="ew", pady=(0, 8))
        row += 1
        ttk.Button(card, text="Capturar trazas", command=self.run_capture,
                   style="Secondary.TButton").grid(row=row, column=0, sticky="ew", pady=(0, 8))
        row += 1
        self.cancel_button = ttk.Button(card, text="Cancelar proceso", command=self.on_cancel,
                                        state="disabled", style="Danger.TButton")
        self.cancel_button.grid(row=row, column=0, sticky="ew")
        row += 1
        ttk.Label(card, text="Los logs pueden contener datos personales. Captura solo con "
                             "autorización vigente y conserva la evidencia según el alcance.",
                  style="Muted.TLabel", wraplength=295).grid(row=row, column=0, sticky="w", pady=(18, 0))

        self.output = theme.make_output(
            self, 0, "SALIDA DE TRAZAS", "Progreso en vivo · archivos y manifiesto al terminar",
            on_clear=self.clear_output, on_copy=self.copy_output,
        )
        self.set_output("$ terminal de trazas esperando una operación…\n\nListo. Revisa el plan dry-run antes de capturar.\n")

    def detect_device(self) -> None:
        device_detect.detect_and_fill(self, self.serial)

    def selected_sources(self) -> list[str]:
        return [key for key, _label, _default in SOURCES if self.source_vars[key].get()]

    def command(self) -> list[str]:
        command = ["bash", "src/android_toolchain/traces.sh"]
        if self.serial.get().strip():
            command.extend(["--serial", self.serial.get().strip()])
        command.extend(["--out-dir", self.out_dir.get(), "--sources", ",".join(self.selected_sources())])
        return command

    def run_preview(self) -> None:
        if not self.selected_sources():
            messagebox.showinfo("Sin fuentes", "Selecciona al menos una fuente de trazas.")
            return
        self.on_start(self.command() + ["--dry-run"], "vista previa de trazas", self.output)

    def run_capture(self) -> None:
        if not self.selected_sources():
            messagebox.showinfo("Sin fuentes", "Selecciona al menos una fuente de trazas.")
            return
        if self.dry_run.get():
            self.run_preview()
            return
        sources = ", ".join(self.selected_sources())
        if not messagebox.askyesno(
                "Confirmar captura de trazas",
                f"Serial: {self.serial.get().strip() or 'único dispositivo'}\n"
                f"Destino: {self.out_dir.get()}\nFuentes: {sources}\n\n"
                "logcat y el registro del kernel pueden revelar datos sensibles "
                "del dispositivo. Úsalo únicamente sobre un dispositivo autorizado "
                "y conserva la evidencia según el alcance.",
                icon="warning"):
            return
        self.on_start(self.command() + ["--confirm"], "capturando trazas", self.output)

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

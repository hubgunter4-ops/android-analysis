"""Vista de listado de apps: uso, conexiones y desglose de datos."""
from __future__ import annotations

import os
from collections.abc import Callable
import tkinter as tk
from tkinter import ttk

from . import device_detect, theme


class AppsView(ttk.Frame):
    """Séptima pestaña: listado de apps con uso, conexiones y datos."""

    def __init__(self, parent: tk.Misc,
                 on_start: Callable[[list[str], str, tk.Text], bool],
                 on_cancel: Callable[[], None]) -> None:
        super().__init__(parent, style="App.TFrame", padding=(0, 12, 0, 0))
        self.on_start = on_start
        self.on_cancel = on_cancel
        self.serial = tk.StringVar()
        self.todas = tk.BooleanVar(value=False)
        self.out_dir = tk.StringVar(value=os.path.expanduser("~/security-tools/apps"))
        self.dry_run = tk.BooleanVar(value=True)
        self._build()

    def _build(self) -> None:
        self.columnconfigure(0, weight=0, minsize=320)
        self.columnconfigure(1, weight=1)
        self.rowconfigure(0, weight=1)
        # La tarjeta es más alta que la ventana con todos los apartados:
        # va dentro de un lienzo con barra de desplazamiento, como Auditoría.
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
        ttk.Label(card, text="APPS · USO Y CONEXIONES", style="Section.TLabel").grid(row=0, column=0, sticky="w")
        ttk.Label(card, text="Listado de apps, uso y datos", style="CardTitle.TLabel").grid(
            row=1, column=0, sticky="w", pady=(4, 6))
        ttk.Label(card, text="Lista las apps del dispositivo con su uso, sus conexiones "
                             "activas y su desglose de datos (móvil y Wi-Fi), más las "
                             "acciones que piden apps y daemons y el árbol de procesos "
                             "con el PID heredado.",
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
        ttk.Label(card, text="2  ·  QUÉ LISTAR", style="Section.TLabel").grid(
            row=6, column=0, sticky="w", pady=(10, 6))
        ttk.Checkbutton(card, text="Incluir también las apps del sistema (por defecto solo terceros)",
                        variable=self.todas, style="Panel.TCheckbutton").grid(row=7, column=0, sticky="w", pady=2)
        ttk.Label(card, text="3  ·  DIRECTORIO DE EVIDENCIA", style="Section.TLabel").grid(
            row=8, column=0, sticky="w", pady=(10, 6))
        ttk.Entry(card, textvariable=self.out_dir, style="Panel.TEntry").grid(row=9, column=0, sticky="ew")
        ttk.Label(card, text="Cada recogida crea una subcarpeta APPS-<fecha>_<serial> (0700) "
                             "con APPS.txt, resumen.json y MANIFIESTO.txt.",
                  style="Muted.TLabel", wraplength=295).grid(row=10, column=0, sticky="w", pady=(5, 0))
        ttk.Checkbutton(card, text="Vista previa / dry-run (no llama a adb)", variable=self.dry_run,
                        style="Panel.TCheckbutton").grid(row=11, column=0, sticky="w", pady=(10, 2))
        ttk.Separator(card).grid(row=12, column=0, sticky="ew", pady=10)
        ttk.Button(card, text="VISTA PREVIA  ·  DRY-RUN", command=self.run_preview,
                   style="Accent.TButton").grid(row=13, column=0, sticky="ew", pady=(0, 6))
        ttk.Button(card, text="Listar apps, uso y conexiones", command=self.run_apps,
                   style="Secondary.TButton").grid(row=14, column=0, sticky="ew", pady=(0, 6))
        self.cancel_button = ttk.Button(card, text="Cancelar proceso", command=self.on_cancel,
                                        state="disabled", style="Danger.TButton")
        self.cancel_button.grid(row=15, column=0, sticky="ew")
        ttk.Label(card, text="Solo metadatos: paquetes, uso, extremos de conexión y "
                             "bytes por app. No recoge contenido, ni mensajes, ni "
                             "payloads de red.",
                  style="Muted.TLabel", wraplength=295).grid(row=16, column=0, sticky="w", pady=(10, 0))

        self.output = theme.make_output(
            self, 0, "SALIDA DE APPS", "Progreso en vivo · reporte y manifiesto al terminar",
            on_clear=self.clear_output, on_copy=self.copy_output,
        )
        self.set_output("$ terminal de apps esperando una operación…\n\nListo. Revisa el plan dry-run antes de recoger.\n")

    def detect_device(self) -> None:
        device_detect.detect_and_fill(self, self.serial)

    def command(self) -> list[str]:
        command = ["bash", "src/android_toolchain/apps.sh"]
        if self.serial.get().strip():
            command.extend(["--serial", self.serial.get().strip()])
        if self.todas.get():
            command.append("--todas")
        command.extend(["--out-dir", self.out_dir.get()])
        return command

    def run_preview(self) -> None:
        self.on_start(self.command() + ["--dry-run"], "vista previa de apps", self.output)

    def run_apps(self) -> None:
        if self.dry_run.get():
            self.run_preview()
            return
        self.on_start(self.command() + ["--confirm"], "listando apps", self.output)

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

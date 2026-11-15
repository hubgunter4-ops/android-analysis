"""Vista de análisis de trazas: clasificar capturas y bugreports subidos."""
from __future__ import annotations

import os
from collections.abc import Callable
import tkinter as tk
from tkinter import filedialog, messagebox, ttk

from . import device_detect, theme


class AnalyzeView(ttk.Frame):
    """Sexta pestaña: analizar y clasificar trazas ADB y bugreports."""

    def __init__(self, parent: tk.Misc,
                 on_start: Callable[[list[str], str, tk.Text], bool],
                 on_cancel: Callable[[], None]) -> None:
        super().__init__(parent, style="App.TFrame", padding=(0, 12, 0, 0))
        self.on_start = on_start
        self.on_cancel = on_cancel
        self.input_dir = tk.StringVar(value=os.path.expanduser("~/security-tools/traces"))
        self.input_files = tk.StringVar()
        self.serial = tk.StringVar()
        self.max_muestras = tk.StringVar(value="5")
        self.out_dir = tk.StringVar(value=os.path.expanduser("~/security-tools/analyses"))
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
        ttk.Label(card, text="ANALIZAR TRAZAS", style="Section.TLabel").grid(row=0, column=0, sticky="w")
        ttk.Label(card, text="Clasificar capturas y bugreports", style="CardTitle.TLabel").grid(
            row=1, column=0, sticky="w", pady=(4, 6))
        ttk.Label(card, text="Sube una carpeta de captura o archivos sueltos (.txt o "
                             "bugreport.zip) y clasifica cada línea por fuente, severidad "
                             "y clase: reinicio, crash, ANR, memoria, red, permisos, kernel.",
                  style="Muted.TLabel", wraplength=295).grid(row=2, column=0, sticky="w", pady=(0, 14))
        ttk.Label(card, text="1  ·  ENTRADA", style="Section.TLabel").grid(row=3, column=0, sticky="w")
        ttk.Label(card, text="Carpeta de captura", style="Panel.TLabel").grid(
            row=4, column=0, sticky="w", pady=(6, 4))
        dir_row = ttk.Frame(card, style="Card.TFrame")
        dir_row.grid(row=5, column=0, sticky="ew")
        dir_row.columnconfigure(0, weight=1)
        ttk.Entry(dir_row, textvariable=self.input_dir, style="Panel.TEntry").grid(row=0, column=0, sticky="ew")
        ttk.Button(dir_row, text="Examinar", command=self.pick_dir,
                   style="Secondary.TButton").grid(row=0, column=1, padx=(8, 0))
        ttk.Label(card, text="Archivos subidos (.txt o .zip, separados por comas)",
                  style="Panel.TLabel").grid(row=6, column=0, sticky="w", pady=(10, 4))
        file_row = ttk.Frame(card, style="Card.TFrame")
        file_row.grid(row=7, column=0, sticky="ew")
        file_row.columnconfigure(0, weight=1)
        ttk.Entry(file_row, textvariable=self.input_files, style="Panel.TEntry").grid(row=0, column=0, sticky="ew")
        ttk.Button(file_row, text="Subir archivo(s)", command=self.pick_files,
                   style="Secondary.TButton").grid(row=0, column=1, padx=(8, 0))
        ttk.Label(card, text="Si hay archivos subidos, se analizan esos; si no, la carpeta.",
                  style="Muted.TLabel", wraplength=295).grid(row=8, column=0, sticky="w", pady=(5, 0))
        ttk.Label(card, text="2  ·  BUGREPORT DESDE EL DISPOSITIVO", style="Section.TLabel").grid(
            row=9, column=0, sticky="w", pady=(10, 6))
        ttk.Label(card, text="Serial (vacío: exige un único dispositivo)", style="Panel.TLabel").grid(
            row=10, column=0, sticky="w", pady=(6, 4))
        serial_row = ttk.Frame(card, style="Card.TFrame")
        serial_row.grid(row=11, column=0, sticky="ew")
        serial_row.columnconfigure(0, weight=1)
        ttk.Entry(serial_row, textvariable=self.serial, style="Panel.TEntry").grid(row=0, column=0, sticky="ew")
        ttk.Button(serial_row, text="Detectar", command=self.detect_device,
                   style="Secondary.TButton").grid(row=0, column=1, padx=(8, 0))
        ttk.Button(card, text="Solicitar bugreport al dispositivo", command=self.run_request_bugreport,
                   style="Secondary.TButton").grid(row=12, column=0, sticky="ew", pady=(8, 0))
        ttk.Label(card, text="Pide el bugreport con adb, lo guarda y lo analiza solo. "
                             "Tarda unos minutos y exige un dispositivo autorizado.",
                  style="Muted.TLabel", wraplength=295).grid(row=13, column=0, sticky="w", pady=(5, 0))
        ttk.Label(card, text="3  ·  SALIDA", style="Section.TLabel").grid(
            row=14, column=0, sticky="w", pady=(10, 6))
        ttk.Label(card, text="Directorio de evidencia", style="Panel.TLabel").grid(
            row=15, column=0, sticky="w", pady=(6, 4))
        ttk.Entry(card, textvariable=self.out_dir, style="Panel.TEntry").grid(row=16, column=0, sticky="ew")
        muestras_row = ttk.Frame(card, style="Card.TFrame")
        muestras_row.grid(row=17, column=0, sticky="ew", pady=(8, 0))
        muestras_row.columnconfigure(1, weight=1)
        ttk.Label(muestras_row, text="Muestras por clase", style="Panel.TLabel").grid(row=0, column=0, sticky="w")
        ttk.Entry(muestras_row, textvariable=self.max_muestras, width=6, style="Panel.TEntry").grid(
            row=0, column=1, sticky="w", padx=(8, 0))
        ttk.Label(card, text="Cada análisis crea una subcarpeta ANALISIS-<fecha>_<etiqueta> (0700) "
                             "con ANALISIS.txt, resumen.json y MANIFIESTO.txt.",
                  style="Muted.TLabel", wraplength=295).grid(row=18, column=0, sticky="w", pady=(5, 0))
        ttk.Checkbutton(card, text="Vista previa / dry-run (no analiza ni escribe)", variable=self.dry_run,
                        style="Panel.TCheckbutton").grid(row=19, column=0, sticky="w", pady=(10, 2))
        ttk.Separator(card).grid(row=20, column=0, sticky="ew", pady=10)
        ttk.Button(card, text="VISTA PREVIA  ·  DRY-RUN", command=self.run_preview,
                   style="Accent.TButton").grid(row=21, column=0, sticky="ew", pady=(0, 6))
        ttk.Button(card, text="Analizar y clasificar", command=self.run_analyze,
                   style="Secondary.TButton").grid(row=22, column=0, sticky="ew", pady=(0, 6))
        self.cancel_button = ttk.Button(card, text="Cancelar proceso", command=self.on_cancel,
                                        state="disabled", style="Danger.TButton")
        self.cancel_button.grid(row=23, column=0, sticky="ew")
        ttk.Label(card, text="El análisis es de solo lectura sobre la entrada y muestra "
                             "conteos y muestras de una línea; el crudo nunca se copia al "
                             "reporte. Un bugreport.zip se extrae a un temporal y se borra.",
                  style="Muted.TLabel", wraplength=295).grid(row=24, column=0, sticky="w", pady=(10, 0))

        self.output = theme.make_output(
            self, 0, "SALIDA DE ANÁLISIS", "Progreso en vivo · reporte y manifiesto al terminar",
            on_clear=self.clear_output, on_copy=self.copy_output,
        )
        self.set_output("$ terminal de análisis esperando una operación…\n\nListo. Revisa el plan dry-run antes de analizar.\n")

    def detect_device(self) -> None:
        device_detect.detect_and_fill(self, self.serial)

    def pick_dir(self) -> None:
        chosen = filedialog.askdirectory(
            title="Carpeta de captura de trazas",
            initialdir=os.path.expanduser(self.input_dir.get().strip() or "~/security-tools/traces"))
        if chosen:
            self.input_dir.set(chosen)
            self.input_files.set("")

    def pick_files(self) -> None:
        chosen = filedialog.askopenfilenames(
            title="Subir trazas o bugreport",
            filetypes=[("Trazas y bugreports", "*.txt *.zip"),
                       ("Texto", "*.txt"), ("Bugreport (zip)", "*.zip"),
                       ("Todos", "*.*")])
        if chosen:
            self.input_files.set(", ".join(chosen))

    def command(self) -> list[str] | None:
        files = [f.strip() for f in self.input_files.get().split(",") if f.strip()]
        command = ["python3", "src/android_toolchain/analyze_traces.py"]
        if files:
            for f in files:
                command.extend(["--file", f])
        elif self.input_dir.get().strip():
            command.extend(["--dir", self.input_dir.get().strip()])
        else:
            messagebox.showinfo(
                "Analizar trazas",
                "Indica una carpeta de captura o sube al menos un archivo "
                "(.txt o bugreport.zip).")
            return None
        if self.max_muestras.get().strip():
            command.extend(["--max-muestras", self.max_muestras.get().strip()])
        command.extend(["--out-dir", self.out_dir.get()])
        return command

    def run_preview(self) -> None:
        cmd = self.command()
        if cmd is None:
            return
        self.on_start(cmd + ["--dry-run"], "vista previa de análisis", self.output)

    def run_analyze(self) -> None:
        if self.dry_run.get():
            self.run_preview()
            return
        cmd = self.command()
        if cmd is None:
            return
        self.on_start(cmd, "analizando trazas", self.output)

    def run_request_bugreport(self) -> None:
        if self.dry_run.get():
            messagebox.showinfo(
                "Solicitar bugreport",
                "Desmarca «Vista previa / dry-run» para pedir el bugreport "
                "al dispositivo. El pedido tarda unos minutos y se analiza solo.")
            return
        detail = (f"Serial: {self.serial.get().strip() or 'único dispositivo'}\n"
                  f"Salida: {self.out_dir.get()}\n\n"
                  "Pide el bugreport con `adb bugreport`, lo guarda como zip "
                  "y lo analiza y clasifica solo. Tarda unos minutos. Úsalo "
                  "únicamente sobre un dispositivo autorizado y dentro del "
                  "alcance de laboratorio.")
        if not messagebox.askyesno("Confirmar petición de bugreport", detail, icon="warning"):
            return
        command = ["bash", "src/no4nn.sh", "--analyze", "--analyze-pedir-bugreport",
                   "--analyze-confirm"]
        if self.serial.get().strip():
            command.extend(["--analyze-serial", self.serial.get().strip()])
        if self.out_dir.get().strip():
            command.extend(["--analyze-out-dir", self.out_dir.get().strip()])
        self.on_start(command, "pidiendo bugreport y analizando", self.output)

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

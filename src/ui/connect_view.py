"""Vista de conexión ADB: verificar el estado y forzar la conexión."""
from __future__ import annotations

import os
from collections.abc import Callable
from pathlib import Path
import tkinter as tk
from tkinter import messagebox, ttk

from . import device_detect, theme

SCOPE_TEMPLATE = """# Alcance de laboratorio — android-analysis
# Solo estos objetivos están autorizados. Edita este archivo para
# añadir o quitar dispositivos y redes; sin él, la allowlist está
# inactiva y el operador responde por cada objetivo.
#
# Un serial autorizado por línea:
# serial:emulator-5554
#
# Una IP o red autorizada para adb connect por línea:
# tcp:192.168.1.42
# tcp:192.168.1.0/24
"""


class ConnectView(ttk.Frame):
    """Quinta pestaña: verificar y forzar la conexión ADB (USB y TCP)."""

    def __init__(self, parent: tk.Misc,
                 on_start: Callable[[list[str], str, tk.Text], bool],
                 on_cancel: Callable[[], None]) -> None:
        super().__init__(parent, style="App.TFrame", padding=(0, 12, 0, 0))
        self.on_start = on_start
        self.on_cancel = on_cancel
        self.serial = tk.StringVar()
        self.tcp_target = tk.StringVar()
        self.timeout = tk.StringVar(value="15")
        self.out_dir = tk.StringVar(value=os.path.expanduser("~/security-tools/connections"))
        self.scope_file = tk.StringVar(value=os.path.expanduser("~/security-tools/scope"))
        self.force = tk.BooleanVar(value=False)
        self.dry_run = tk.BooleanVar(value=True)
        self._build()
        self.refresh_scope_status()

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
        ttk.Label(card, text="CONEXIÓN ADB", style="Section.TLabel").grid(row=0, column=0, sticky="w")
        ttk.Label(card, text="Verificar el estado y forzar la conexión", style="CardTitle.TLabel").grid(
            row=1, column=0, sticky="w", pady=(4, 6))
        ttk.Label(card, text="Comprueba qué dispositivos ve adb, su estado (device, "
                             "unauthorized, offline) y, si hace falta, reinicia el servidor, "
                             "reconecta o conecta por TCP.",
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
        ttk.Label(card, text="2  ·  CONEXIÓN TCP (OPCIONAL)", style="Section.TLabel").grid(
            row=6, column=0, sticky="w", pady=(10, 6))
        ttk.Label(card, text="IP del dispositivo (puerto default 5555)", style="Panel.TLabel").grid(
            row=7, column=0, sticky="w", pady=(6, 4))
        ttk.Entry(card, textvariable=self.tcp_target, style="Panel.TEntry").grid(row=8, column=0, sticky="ew")
        ttk.Label(card, text="La IP la escribe el operador; nunca se buscan dispositivos en la red. "
                             "El teléfono debe estar en la misma Wi-Fi.",
                  style="Muted.TLabel", wraplength=295).grid(row=9, column=0, sticky="w", pady=(5, 0))
        ttk.Label(card, text="3  ·  ALCANCE DE LABORATORIO", style="Section.TLabel").grid(
            row=10, column=0, sticky="w", pady=(10, 6))
        ttk.Entry(card, textvariable=self.scope_file, style="Panel.TEntry").grid(row=11, column=0, sticky="ew")
        self.scope_status = ttk.Label(card, text="", style="Muted.TLabel", wraplength=295)
        self.scope_status.grid(row=12, column=0, sticky="w", pady=(5, 0))
        scope_row = ttk.Frame(card, style="Card.TFrame")
        scope_row.grid(row=13, column=0, sticky="ew", pady=(6, 0))
        ttk.Button(scope_row, text="Crear plantilla de alcance", command=self.create_scope_template,
                   style="Secondary.TButton").pack(side="left")
        ttk.Button(scope_row, text="Actualizar", command=self.refresh_scope_status,
                   style="Secondary.TButton").pack(side="left", padx=(8, 0))
        ttk.Label(card, text="4  ·  FORZAR", style="Section.TLabel").grid(
            row=14, column=0, sticky="w", pady=(10, 6))
        ttk.Checkbutton(card, text="Forzar conexión (reiniciar servidor, reconectar, esperar)",
                        variable=self.force, style="Panel.TCheckbutton").grid(row=15, column=0, sticky="w", pady=2)
        timeout_row = ttk.Frame(card, style="Card.TFrame")
        timeout_row.grid(row=16, column=0, sticky="ew", pady=(6, 0))
        timeout_row.columnconfigure(1, weight=1)
        ttk.Label(timeout_row, text="Espera máxima (s)", style="Panel.TLabel").grid(row=0, column=0, sticky="w")
        ttk.Entry(timeout_row, textvariable=self.timeout, width=6, style="Panel.TEntry").grid(
            row=0, column=1, sticky="w", padx=(8, 0))
        ttk.Label(card, text="5  ·  DIRECTORIO DE EVIDENCIA", style="Section.TLabel").grid(
            row=17, column=0, sticky="w", pady=(10, 6))
        ttk.Entry(card, textvariable=self.out_dir, style="Panel.TEntry").grid(row=18, column=0, sticky="ew")
        ttk.Label(card, text="Cada verificación crea una subcarpeta con fecha y serial (0700).",
                  style="Muted.TLabel", wraplength=295).grid(row=19, column=0, sticky="w", pady=(5, 0))
        ttk.Checkbutton(card, text="Vista previa / dry-run (no llama a adb)", variable=self.dry_run,
                        style="Panel.TCheckbutton").grid(row=20, column=0, sticky="w", pady=(10, 2))
        ttk.Separator(card).grid(row=21, column=0, sticky="ew", pady=10)
        ttk.Button(card, text="VISTA PREVIA  ·  DRY-RUN", command=self.run_preview,
                   style="Accent.TButton").grid(row=22, column=0, sticky="ew", pady=(0, 6))
        ttk.Button(card, text="Verificar conexión", command=self.run_verify,
                   style="Secondary.TButton").grid(row=23, column=0, sticky="ew", pady=(0, 6))
        ttk.Button(card, text="Forzar conexión", command=self.run_force,
                   style="Secondary.TButton").grid(row=24, column=0, sticky="ew", pady=(0, 6))
        self.cancel_button = ttk.Button(card, text="Cancelar proceso", command=self.on_cancel,
                                        state="disabled", style="Danger.TButton")
        self.cancel_button.grid(row=25, column=0, sticky="ew")
        ttk.Label(card, text="Un dispositivo NO AUTORIZADO no se puede forzar: la huella RSA "
                             "se acepta en la pantalla del teléfono. Verificar solo lee el estado.",
                  style="Muted.TLabel", wraplength=295).grid(row=26, column=0, sticky="w", pady=(10, 0))

        self.output = theme.make_output(
            self, 0, "SALIDA DE CONEXIÓN", "Progreso en vivo · reporte y manifiesto al terminar",
            on_clear=self.clear_output, on_copy=self.copy_output,
        )
        self.set_output("$ terminal de conexión esperando una operación…\n\nListo. Revisa el plan dry-run antes de forzar.\n")

    def detect_device(self) -> None:
        device_detect.detect_and_fill(self, self.serial)

    def refresh_scope_status(self) -> None:
        path = Path(os.path.expanduser(self.scope_file.get().strip()))
        if not self.scope_file.get().strip():
            self.scope_status.configure(text="Sin archivo de alcance (allowlist inactiva).")
            return
        if not path.is_file():
            self.scope_status.configure(text=f"Sin archivo de alcance en {path} (allowlist inactiva).")
            return
        serials = tcps = 0
        for line in path.read_text(encoding="utf-8", errors="ignore").splitlines():
            line = line.strip()
            if line.startswith("serial:"):
                serials += 1
            elif line.startswith("tcp:"):
                tcps += 1
        self.scope_status.configure(
            text=f"Alcance activo: {serials} serial(es), {tcps} entrada(s) TCP en {path}.")

    def create_scope_template(self) -> None:
        path = Path(os.path.expanduser(self.scope_file.get().strip()))
        if not self.scope_file.get().strip():
            messagebox.showinfo("Alcance de laboratorio", "Indica primero la ruta del archivo de alcance.")
            return
        if path.exists():
            if not messagebox.askyesno(
                    "Alcance de laboratorio",
                    f"El archivo ya existe:\n{path}\n\n¿Sobrescribirlo con la plantilla?",
                    icon="warning"):
                return
        try:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(SCOPE_TEMPLATE, encoding="utf-8")
            os.chmod(path, 0o600)
        except OSError as exc:
            messagebox.showerror("Alcance de laboratorio", f"No se pudo crear la plantilla:\n{exc}")
            return
        self.refresh_scope_status()
        messagebox.showinfo(
            "Alcance de laboratorio",
            f"Plantilla creada en:\n{path}\n\nEdítala para listar los seriales y las IP/redes "
            "autorizadas. Mientras no tenga entradas, la allowlist no restringe nada.")

    def command(self, include_actions: bool = True) -> list[str]:
        command = ["bash", "src/android_toolchain/connect.sh"]
        if self.serial.get().strip():
            command.extend(["--serial", self.serial.get().strip()])
        if include_actions and self.tcp_target.get().strip():
            command.extend(["--tcp", self.tcp_target.get().strip()])
        if include_actions and self.force.get():
            command.append("--force")
        if self.timeout.get().strip():
            command.extend(["--timeout", self.timeout.get().strip()])
        if self.scope_file.get().strip() and os.path.isfile(
                os.path.expanduser(self.scope_file.get().strip())):
            # Solo se pasa si el archivo existe: si no, connect.sh usa
            # la allowlist inactiva en vez de rechazar la operación.
            command.extend(["--scope-file", self.scope_file.get().strip()])
        command.extend(["--out-dir", self.out_dir.get()])
        return command

    def run_preview(self) -> None:
        self.refresh_scope_status()
        self.on_start(self.command() + ["--dry-run"], "vista previa de conexión", self.output)

    def run_verify(self) -> None:
        # Solo lectura: sin --force ni --tcp, así que nunca conecta.
        self.refresh_scope_status()
        self.on_start(self.command(include_actions=False), "verificando conexión", self.output)

    def run_force(self) -> None:
        if self.dry_run.get():
            self.run_preview()
            return
        if not self.force.get() and not self.tcp_target.get().strip():
            messagebox.showinfo(
                "Forzar conexión",
                "Marca «Forzar conexión» o indica una IP TCP para conectar.\n\n"
                "Si solo quieres ver el estado, usa «Verificar conexión».")
            return
        detail = (f"Serial: {self.serial.get().strip() or 'único dispositivo'}\n"
                  f"TCP: {self.tcp_target.get().strip() or 'ninguno'}\n"
                  f"Forzar: {'sí' if self.force.get() else 'no'} · "
                  f"Espera: {self.timeout.get().strip() or '15'} s\n"
                  f"Alcance: {self.scope_file.get().strip() or 'sin archivo'}\n\n"
                  "Reinicia el servidor ADB, reconecta los dispositivos y, si hay "
                  "IP, conecta por TCP. Úsalo únicamente sobre un dispositivo "
                  "autorizado y dentro del alcance de laboratorio.")
        if not messagebox.askyesno("Confirmar conexión forzada", detail, icon="warning"):
            return
        self.on_start(self.command() + ["--confirm"], "forzando conexión", self.output)

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

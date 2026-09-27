"""Vista modular para acciones ADB autorizadas."""
from __future__ import annotations

import shlex
import tkinter as tk
from collections.abc import Callable
from pathlib import Path
from tkinter import messagebox, scrolledtext, ttk

from . import theme


READ_ONLY = {
    "devices", "help", "version", "mdns check", "mdns services", "get-state", "get-serialno", "get-devpath",
    "host-features", "features", "server-status", "jdwp", "get-current-user", "is-user-stopped",
    "get-started-user-state", "get-inactive", "get-bg-restriction-level", "supports-multiwindow",
    "supports-split-screen-multi-window", "get-standby-bucket", "get-exit-info", "get-parcel-size",
    "get-bg-abusive-uids", "get-harmful-app-warning", "get-privapp-permissions", "get-oem-permissions",
    "get-moduleinfo", "get-stagedsessions", "path", "dump", "query-activities", "query-services",
    "query-receivers", "resolve-activity", "list packages", "list permission-groups", "list permissions",
    "list instrumentation", "list features", "list libraries", "list users", "list shared-users",
    "list bridges", "list staged-sessions", "list dnssd", "is-package-device-admin", "list-unknown-sources",
    "list-owners", "list-policy-exempt-apps",
}


class ADBView(ttk.Frame):
    def __init__(self, parent: tk.Misc, catalog_path: Path,
                 on_command: Callable[[list[str], str, tk.Text], None]) -> None:
        super().__init__(parent, style="App.TFrame", padding=(0, 12, 0, 0))
        self.catalog_path = catalog_path
        self.on_command = on_command
        self.serial = tk.StringVar()
        self.adb_args = tk.StringVar()
        self.module_states: dict[str, bool] = {}
        self._build()

    def _build(self) -> None:
        self.columnconfigure(0, weight=1)
        self.columnconfigure(1, weight=1)
        self.rowconfigure(1, weight=1)
        header = ttk.Frame(self, style="Card.TFrame", padding=16)
        header.grid(row=0, column=0, columnspan=2, sticky="ew", pady=(0, 10))
        header.columnconfigure(2, weight=1)
        ttk.Label(header, text="ADB CONTROL", style="Section.TLabel").grid(row=0, column=0, padx=(0, 18))
        ttk.Label(header, text="Serial opcional", style="Panel.TLabel").grid(row=0, column=1, sticky="e", padx=(0, 8))
        ttk.Entry(header, textvariable=self.serial, width=22, style="Panel.TEntry").grid(row=0, column=2, sticky="ew")
        ttk.Label(header, text="Argumentos adicionales", style="Panel.TLabel").grid(row=0, column=3, padx=(20, 8))
        ttk.Entry(header, textvariable=self.adb_args, width=30, style="Panel.TEntry").grid(row=0, column=4, sticky="ew")
        ttk.Label(header, text="Se interpretan como argumentos, no como shell.", style="Muted.TLabel").grid(
            row=1, column=0, columnspan=5, sticky="w", pady=(8, 0))

        modules = ttk.Frame(self, style="Card.TFrame", padding=12)
        modules.grid(row=1, column=0, sticky="nsew", padx=(0, 10))
        modules.columnconfigure(0, weight=1); modules.rowconfigure(0, weight=1)
        canvas = tk.Canvas(modules, bg=theme.PANEL, highlightthickness=0, borderwidth=0)
        scrollbar = ttk.Scrollbar(modules, orient="vertical", command=canvas.yview)
        canvas.configure(yscrollcommand=scrollbar.set)
        canvas.grid(row=0, column=0, sticky="nsew"); scrollbar.grid(row=0, column=1, sticky="ns")
        self.module_frame = ttk.Frame(canvas, style="Panel.TFrame")
        window = canvas.create_window((0, 0), window=self.module_frame, anchor="nw")
        self.module_frame.bind("<Configure>", lambda _e: canvas.configure(scrollregion=canvas.bbox("all")))
        canvas.bind("<Configure>", lambda e: canvas.itemconfigure(window, width=e.width))
        self._populate_modules()

        panel = ttk.Frame(self, style="Card.TFrame", padding=18)
        panel.grid(row=1, column=1, sticky="nsew", padx=(10, 0))
        panel.rowconfigure(4, weight=1); panel.columnconfigure(0, weight=1)
        ttk.Label(panel, text="ACTIVIDAD ADB", style="Section.TLabel").grid(row=0, column=0, sticky="w", pady=(0, 4))
        ttk.Label(panel, text="Cada acción queda visible antes de ejecutarse.", style="Muted.TLabel").grid(row=1, column=0, sticky="w", pady=(0, 12))
        self.request_log = ttk.Treeview(panel, style="App.Treeview", columns=("module", "command", "status"), show="headings", height=6)
        for column, label, width in (("module", "Módulo", 150), ("command", "Petición", 260), ("status", "Estado", 90)):
            self.request_log.heading(column, text=label); self.request_log.column(column, width=width, anchor="w")
        self.request_log.grid(row=2, column=0, sticky="ew", pady=(0, 16))
        ttk.Label(panel, text="SALIDA DE LA PETICIÓN SELECCIONADA", style="Section.TLabel").grid(row=3, column=0, sticky="w", pady=(0, 8))
        self.output = scrolledtext.ScrolledText(panel, wrap="word", bg="#0d1117", fg=theme.TEXT,
                                                insertbackground=theme.TEXT, relief="flat", borderwidth=0,
                                                font=("TkFixedFont", 10), padx=14, pady=14)
        self.output.grid(row=4, column=0, sticky="nsew")
        self.output.insert("end", "Selecciona una función desplegable para ejecutar una petición.\n")
        self.output.configure(state="disabled")

    def _parse_catalog(self) -> list[tuple[str, list[str]]]:
        modules: list[tuple[str, list[str]]] = []
        current: tuple[str, list[str]] | None = None
        for line in self.catalog_path.read_text(encoding="utf-8").splitlines():
            if line.startswith("## "):
                if current and current[1]: modules.append(current)
                current = (line[3:].strip(), [])
            elif current and line.startswith("- `") and line.endswith("`"):
                current[1].append(line[3:-1])
        if current and current[1]: modules.append(current)
        return modules

    def _populate_modules(self) -> None:
        for index, (module, commands) in enumerate(self._parse_catalog()):
            self.module_states[module] = index == 0
            container = ttk.Frame(self.module_frame, style="Panel.TFrame"); container.pack(fill="x", pady=(0, 6))
            body = ttk.Frame(container, style="Panel.TFrame", padding=(12, 4, 4, 8))
            button = ttk.Button(container, text=self._module_title(module, True), style="Module.TButton",
                                command=lambda m=module, b=body: self._toggle_module(m, b))
            button.pack(fill="x")
            for command in commands:
                ttk.Button(body, text=f"  ▶  adb {command}", style="Action.TButton",
                           command=lambda cmd=command, mod=module: self.run_adb(mod, cmd)).pack(fill="x", pady=1)
            if self.module_states[module]: body.pack(fill="x")

    def _module_title(self, module: str, expanded: bool) -> str:
        return ("▾ " if expanded else "▸ ") + module

    def _toggle_module(self, module: str, body: ttk.Frame) -> None:
        self.module_states[module] = not self.module_states[module]
        if self.module_states[module]: body.pack(fill="x")
        else: body.pack_forget()
        # The button is the previous sibling; refresh via the module frame children.
        for widget in body.master.winfo_children():
            if isinstance(widget, ttk.Button):
                widget.configure(text=self._module_title(module, self.module_states[module]))
                break

    @staticmethod
    def requires_confirmation(command: str) -> bool:
        base = command.strip()
        return not (base in READ_ONLY or base.startswith("list ") or base.startswith("get-"))

    def _argv(self, module: str, command: str) -> list[str]:
        argv = ["adb"]
        if self.serial.get().strip(): argv.extend(["-s", self.serial.get().strip()])
        prefixes = {"Activity Manager (`am`)": ["shell", "am"], "Package Manager (`pm`)": ["shell", "pm"],
                    "Device Policy Manager (`dpm`)": ["shell", "dpm"], "Administrador de servicios (`cmd`)": ["shell"],
                    "Utilidades del sistema (`toybox`)": ["shell"], "Captura de pantalla": ["shell"],
                    "Grabación de pantalla": ["shell"], "Perfiles ART": ["shell"], "Reinicio de dispositivos de prueba": ["shell"],
                    "SQLite": ["shell"]}
        argv.extend(prefixes.get(module, [])); argv.extend(shlex.split(command))
        if self.adb_args.get().strip(): argv.extend(shlex.split(self.adb_args.get().strip()))
        return argv

    def run_adb(self, module: str, command: str) -> None:
        argv = self._argv(module, command)
        if self.requires_confirmation(command):
            detail = " ".join(shlex.quote(part) for part in argv)
            if not messagebox.askyesno("Confirmar acción ADB", f"Módulo: {module}\n\nComando:\n{detail}\n\n"
                                       "La acción puede modificar el dispositivo o revelar datos sensibles.\n"
                                       "Úsalo únicamente sobre un dispositivo autorizado.", icon="warning"):
                return
        item = self.request_log.insert("", "end", values=(module, command, "EN CURSO"))
        self.request_log.see(item)
        self.on_command(argv, f"ejecutando adb {command}", self.output)

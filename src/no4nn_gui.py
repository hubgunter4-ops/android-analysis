#!/usr/bin/env python3
"""GUI Tkinter para el instalador y módulos operativos ADB autorizados.

El catálogo de acciones se carga desde docs/Funciones_de_ADB_por_módulo.md para
mantener una única fuente de verdad. Las acciones se ejecutan con argv, nunca
con un shell, y las operaciones mutables piden confirmación.
"""
from __future__ import annotations

import os
import queue
import shlex
import subprocess
import threading
import tkinter as tk
from pathlib import Path
from tkinter import messagebox, scrolledtext, ttk


READ_ONLY = {
    "devices", "help", "version", "mdns check", "mdns services", "get-state",
    "get-serialno", "get-devpath", "host-features", "features", "server-status",
    "jdwp", "get-current-user", "is-user-stopped", "get-started-user-state",
    "get-inactive", "get-bg-restriction-level", "supports-multiwindow",
    "supports-split-screen-multi-window", "get-standby-bucket", "get-exit-info",
    "get-parcel-size", "get-bg-abusive-uids", "get-harmful-app-warning",
    "get-privapp-permissions", "get-oem-permissions", "get-moduleinfo",
    "get-stagedsessions", "path", "dump", "query-activities", "query-services",
    "query-receivers", "resolve-activity", "list packages", "list permission-groups",
    "list permissions", "list instrumentation", "list features", "list libraries",
    "list users", "list shared-users", "list bridges", "list staged-sessions",
    "list dnssd", "is-package-device-admin", "list-unknown-sources", "list-owners",
    "list-policy-exempt-apps",
}


class ToolchainGUI(tk.Tk):
    BG = "#10131a"
    PANEL = "#181d27"
    PANEL_ALT = "#202735"
    TEXT = "#edf2f7"
    MUTED = "#9ca8ba"
    ACCENT = "#a78bfa"
    SUCCESS = "#6ee7b7"
    WARNING = "#fbbf24"

    def __init__(self, root_dir: Path) -> None:
        super().__init__()
        self.root_dir = root_dir
        self.entrypoint = root_dir / "src" / "no4nn.sh"
        self.catalog_path = root_dir / "docs" / "Funciones_de_ADB_por_módulo.md"
        self.output_queue: queue.Queue[tuple[str, str | None]] = queue.Queue()
        self.process: subprocess.Popen[str] | None = None
        self.worker: threading.Thread | None = None
        self.module_states: dict[str, bool] = {}
        self.request_counter = 0
        self.active_request_id = ""

        self.title("ANDROID ANALYSIS · Toolchain + ADB console")
        self.geometry("1220x820")
        self.minsize(980, 650)
        self.configure(bg=self.BG)
        self._build_style()
        self._build_ui()
        self.after(80, self._drain_output)

    def _build_style(self) -> None:
        style = ttk.Style(self)
        style.theme_use("clam")
        style.configure("App.TFrame", background=self.BG)
        style.configure("Panel.TFrame", background=self.PANEL)
        style.configure("Title.TLabel", background=self.BG, foreground=self.TEXT,
                        font=("TkDefaultFont", 20, "bold"))
        style.configure("Subtitle.TLabel", background=self.BG, foreground=self.MUTED,
                        font=("TkDefaultFont", 10))
        style.configure("Panel.TLabel", background=self.PANEL, foreground=self.TEXT)
        style.configure("Muted.TLabel", background=self.PANEL, foreground=self.MUTED)
        style.configure("Section.TLabel", background=self.PANEL, foreground=self.ACCENT,
                        font=("TkDefaultFont", 10, "bold"))
        style.configure("Accent.TButton", background=self.ACCENT, foreground="#17121f",
                        padding=(14, 8), font=("TkDefaultFont", 10, "bold"))
        style.map("Accent.TButton", background=[("active", "#c4b5fd")])
        style.configure("Secondary.TButton", background=self.PANEL_ALT, foreground=self.TEXT,
                        padding=(10, 7))
        style.map("Secondary.TButton", background=[("active", "#30394b")])
        style.configure("Module.TButton", background=self.PANEL_ALT, foreground=self.TEXT,
                        anchor="w", padding=(9, 7), font=("TkDefaultFont", 10, "bold"))
        style.map("Module.TButton", background=[("active", "#30394b")])
        style.configure("Action.TButton", background="#252d3b", foreground=self.TEXT,
                        anchor="w", padding=(7, 5), font=("TkDefaultFont", 9))
        style.map("Action.TButton", background=[("active", "#39465b")])
        style.configure("Panel.TCheckbutton", background=self.PANEL, foreground=self.TEXT)
        style.configure("Panel.TRadiobutton", background=self.PANEL, foreground=self.TEXT)
        style.configure("Panel.TEntry", fieldbackground="#0d1117", foreground=self.TEXT)
        style.configure("Panel.TCombobox", fieldbackground="#0d1117", foreground=self.TEXT)

    def _build_ui(self) -> None:
        outer = ttk.Frame(self, style="App.TFrame", padding=22)
        outer.pack(fill="both", expand=True)
        ttk.Label(outer, text="ANDROID ANALYSIS", style="Title.TLabel").pack(anchor="w")
        ttk.Label(outer, text="Provisionamiento autorizado · módulos ADB desplegables · salida en vivo",
                  style="Subtitle.TLabel").pack(anchor="w", pady=(2, 14))

        self.notebook = ttk.Notebook(outer)
        self.notebook.pack(fill="both", expand=True)
        installer_tab = ttk.Frame(self.notebook, style="App.TFrame", padding=(0, 12, 0, 0))
        adb_tab = ttk.Frame(self.notebook, style="App.TFrame", padding=(0, 12, 0, 0))
        self.notebook.add(installer_tab, text="  Instalador  ")
        self.notebook.add(adb_tab, text="  Módulos ADB  ")
        self._build_installer_tab(installer_tab)
        self._build_adb_tab(adb_tab)

        self.status = tk.StringVar(value="Estado: listo · no se ha ejecutado ninguna operación")
        ttk.Label(outer, textvariable=self.status, style="Subtitle.TLabel").pack(anchor="w", pady=(10, 0))

    def _build_installer_tab(self, parent: ttk.Frame) -> None:
        parent.columnconfigure(0, weight=0, minsize=300)
        parent.columnconfigure(1, weight=1)
        parent.rowconfigure(0, weight=1)
        panel = ttk.Frame(parent, style="Panel.TFrame", padding=18)
        panel.grid(row=0, column=0, sticky="nsew", padx=(0, 16))
        panel.columnconfigure(0, weight=1)
        self._build_installer_controls(panel)
        self.installer_output = self._make_output_panel(parent, "SALIDA DEL INSTALADOR", 1)

    def _build_installer_controls(self, parent: ttk.Frame) -> None:
        ttk.Label(parent, text="CONFIGURACIÓN", style="Section.TLabel").grid(
            row=0, column=0, sticky="w", pady=(0, 14))
        ttk.Label(parent, text="Alcance", style="Panel.TLabel").grid(row=1, column=0, sticky="w")
        self.scope = tk.StringVar(value="static")
        for row, value, label in ((2, "static", "Solo análisis estático"),
                                  (3, "dynamic", "Solo dinámico / tráfico"),
                                  (4, "all", "Cadena completa")):
            ttk.Radiobutton(parent, text=label, value=value, variable=self.scope,
                            style="Panel.TRadiobutton").grid(row=row, column=0, sticky="w", pady=3)
        ttk.Label(parent, text="Directorio de herramientas", style="Panel.TLabel").grid(
            row=6, column=0, sticky="w", pady=(18, 4))
        self.tools_dir = tk.StringVar(value=os.path.expanduser("~/security-tools"))
        ttk.Entry(parent, textvariable=self.tools_dir, style="Panel.TEntry").grid(row=7, column=0, sticky="ew")
        ttk.Label(parent, text="Estilo del banner", style="Panel.TLabel").grid(row=8, column=0, sticky="w", pady=(14, 4))
        self.banner_style = tk.StringVar(value="0")
        ttk.Combobox(parent, textvariable=self.banner_style, values=("0", "1", "2"),
                     state="readonly", style="Panel.TCombobox").grid(row=9, column=0, sticky="ew")
        self.skip_apt = tk.BooleanVar(value=False)
        ttk.Checkbutton(parent, text="Omitir APT (imagen ya preparada)", variable=self.skip_apt,
                        style="Panel.TCheckbutton").grid(row=10, column=0, sticky="w", pady=(14, 3))
        self.dry_run = tk.BooleanVar(value=True)
        ttk.Checkbutton(parent, text="Dry-run / no cambiar el host", variable=self.dry_run,
                        style="Panel.TCheckbutton").grid(row=11, column=0, sticky="w", pady=3)
        ttk.Separator(parent).grid(row=12, column=0, sticky="ew", pady=18)
        ttk.Button(parent, text="Generar plan", command=self.run_plan, style="Accent.TButton").grid(
            row=13, column=0, sticky="ew", pady=(0, 8))
        ttk.Button(parent, text="Ejecutar instalación", command=self.run_install, style="Secondary.TButton").grid(
            row=14, column=0, sticky="ew", pady=(0, 8))
        self.cancel_button = ttk.Button(parent, text="Cancelar proceso", command=self.cancel_process,
                                        state="disabled", style="Secondary.TButton")
        self.cancel_button.grid(row=15, column=0, sticky="ew")
        ttk.Label(parent, text="La instalación real requiere autorización vigente y puede pedir sudo.",
                  style="Muted.TLabel", wraplength=255).grid(row=16, column=0, sticky="w", pady=(22, 0))

    def _make_output_panel(self, parent: ttk.Frame, title: str, column: int) -> scrolledtext.ScrolledText:
        panel = ttk.Frame(parent, style="Panel.TFrame", padding=14)
        panel.grid(row=0, column=column, sticky="nsew")
        parent.rowconfigure(0, weight=1)
        panel.rowconfigure(1, weight=1)
        panel.columnconfigure(0, weight=1)
        ttk.Label(panel, text=title, style="Section.TLabel").grid(row=0, column=0, sticky="w", pady=(0, 8))
        output = scrolledtext.ScrolledText(panel, wrap="word", bg="#0d1117", fg=self.TEXT,
                                           insertbackground=self.TEXT, relief="flat", borderwidth=0,
                                           font=("TkFixedFont", 10), padx=12, pady=12)
        output.grid(row=1, column=0, sticky="nsew")
        output.insert("end", "Listo. Genera un plan dry-run antes de instalar.\n")
        output.configure(state="disabled")
        return output

    def _build_adb_tab(self, parent: ttk.Frame) -> None:
        parent.columnconfigure(0, weight=1)
        parent.columnconfigure(1, weight=1)
        parent.rowconfigure(1, weight=1)
        header = ttk.Frame(parent, style="Panel.TFrame", padding=12)
        header.grid(row=0, column=0, columnspan=2, sticky="ew", pady=(0, 10))
        header.columnconfigure(1, weight=1)
        ttk.Label(header, text="ADB", style="Section.TLabel").grid(row=0, column=0, padx=(0, 10))
        ttk.Label(header, text="Serial opcional", style="Panel.TLabel").grid(row=0, column=1, sticky="e", padx=(0, 6))
        self.serial = tk.StringVar()
        ttk.Entry(header, textvariable=self.serial, width=22, style="Panel.TEntry").grid(row=0, column=2)
        ttk.Label(header, text="Argumentos adicionales", style="Panel.TLabel").grid(row=0, column=3, padx=(18, 6))
        self.adb_args = tk.StringVar()
        ttk.Entry(header, textvariable=self.adb_args, width=30, style="Panel.TEntry").grid(row=0, column=4)
        ttk.Label(header, text="Se interpretan como argumentos, no como shell.", style="Muted.TLabel").grid(
            row=1, column=0, columnspan=5, sticky="w", pady=(8, 0))

        modules_panel = ttk.Frame(parent, style="Panel.TFrame", padding=10)
        modules_panel.grid(row=1, column=0, sticky="nsew", padx=(0, 10))
        modules_panel.columnconfigure(0, weight=1)
        modules_panel.rowconfigure(0, weight=1)
        self.module_canvas = tk.Canvas(modules_panel, bg=self.PANEL, highlightthickness=0)
        scrollbar = ttk.Scrollbar(modules_panel, orient="vertical", command=self.module_canvas.yview)
        self.module_canvas.configure(yscrollcommand=scrollbar.set)
        self.module_canvas.grid(row=0, column=0, sticky="nsew")
        scrollbar.grid(row=0, column=1, sticky="ns")
        self.module_frame = ttk.Frame(self.module_canvas, style="Panel.TFrame")
        self.module_window = self.module_canvas.create_window((0, 0), window=self.module_frame, anchor="nw")
        self.module_frame.bind("<Configure>", lambda _e: self.module_canvas.configure(
            scrollregion=self.module_canvas.bbox("all")))
        self.module_canvas.bind("<Configure>", lambda event: self.module_canvas.itemconfigure(
            self.module_window, width=event.width))
        self._populate_modules()
        self.adb_output = self._make_adb_output_panel(parent, 1)

    def _make_adb_output_panel(self, parent: ttk.Frame, column: int) -> scrolledtext.ScrolledText:
        panel = ttk.Frame(parent, style="Panel.TFrame", padding=14)
        panel.grid(row=1, column=column, sticky="nsew", padx=(10, 0) if column else (0, 10))
        panel.rowconfigure(3, weight=1)
        panel.columnconfigure(0, weight=1)
        ttk.Label(panel, text="PANEL DE EJECUCIÓN · PETICIONES ADB", style="Section.TLabel").grid(
            row=0, column=0, sticky="w", pady=(0, 8))
        self.request_log = ttk.Treeview(panel, columns=("module", "command", "status"),
                                        show="headings", height=6)
        self.request_log.heading("module", text="Módulo")
        self.request_log.heading("command", text="Petición")
        self.request_log.heading("status", text="Estado")
        self.request_log.column("module", width=150, anchor="w")
        self.request_log.column("command", width=260, anchor="w")
        self.request_log.column("status", width=90, anchor="center")
        self.request_log.grid(row=1, column=0, sticky="ew", pady=(0, 12))
        ttk.Label(panel, text="SALIDA DE LA PETICIÓN SELECCIONADA", style="Section.TLabel").grid(
            row=2, column=0, sticky="w", pady=(0, 8))
        output = scrolledtext.ScrolledText(panel, wrap="word", bg="#0d1117", fg=self.TEXT,
                                           insertbackground=self.TEXT, relief="flat", borderwidth=0,
                                           font=("TkFixedFont", 10), padx=12, pady=12)
        output.grid(row=3, column=0, sticky="nsew")
        output.insert("end", "Selecciona una función desplegable para ejecutar una petición.\n")
        output.configure(state="disabled")
        return output

    def _parse_catalog(self) -> list[tuple[str, list[str]]]:
        modules: list[tuple[str, list[str]]] = []
        current: tuple[str, list[str]] | None = None
        for line in self.catalog_path.read_text(encoding="utf-8").splitlines():
            if line.startswith("## "):
                if current and current[1]:
                    modules.append(current)
                current = (line[3:].strip(), [])
            elif current and line.startswith("- `") and line.endswith("`"):
                current[1].append(line[3:-1])
        if current and current[1]:
            modules.append(current)
        return modules

    def _populate_modules(self) -> None:
        for index, (module, commands) in enumerate(self._parse_catalog()):
            self.module_states[module] = index == 0
            self._add_module(module, commands)

    def _add_module(self, module: str, commands: list[str]) -> None:
        container = ttk.Frame(self.module_frame, style="Panel.TFrame")
        container.pack(fill="x", pady=(0, 6))
        body = ttk.Frame(container, style="Panel.TFrame", padding=(12, 4, 4, 8))
        button = ttk.Button(container, text=self._module_title(module, True), style="Module.TButton",
                            command=lambda: self._toggle_module(module, body, button))
        button.pack(fill="x")
        for command in commands:
            ttk.Button(body, text=f"  ▶  adb {command}", style="Action.TButton",
                       command=lambda cmd=command, mod=module: self.run_adb(mod, cmd)).pack(fill="x", pady=1)
        if self.module_states[module]:
            body.pack(fill="x")

    def _module_title(self, module: str, expanded: bool) -> str:
        return ("▾ " if expanded else "▸ ") + module

    def _toggle_module(self, module: str, body: ttk.Frame, button: ttk.Button) -> None:
        self.module_states[module] = not self.module_states[module]
        if self.module_states[module]:
            body.pack(fill="x")
        else:
            body.pack_forget()
        button.configure(text=self._module_title(module, self.module_states[module]))

    @staticmethod
    def _requires_confirmation(command: str) -> bool:
        base = command.strip()
        if base in READ_ONLY or base.startswith("list ") or base.startswith("get-"):
            return False
        return True

    def _adb_command(self, module: str, command: str) -> list[str]:
        argv = ["adb"]
        serial = self.serial.get().strip()
        if serial:
            argv.extend(["-s", serial])
        tokens = shlex.split(command)
        shell_prefixes = {
            "Activity Manager (`am`)": ["shell", "am"],
            "Package Manager (`pm`)": ["shell", "pm"],
            "Device Policy Manager (`dpm`)": ["shell", "dpm"],
            "Administrador de servicios (`cmd`)": ["shell"],
            "Utilidades del sistema (`toybox`)": ["shell"],
            "Captura de pantalla": ["shell"],
            "Grabación de pantalla": ["shell"],
            "Perfiles ART": ["shell"],
            "Reinicio de dispositivos de prueba": ["shell"],
            "SQLite": ["shell"],
        }
        argv.extend(shell_prefixes.get(module, []))
        argv.extend(tokens)
        extra = self.adb_args.get().strip()
        if extra:
            argv.extend(shlex.split(extra))
        return argv

    def run_adb(self, module: str, command: str) -> None:
        if self.process is not None:
            messagebox.showinfo("Proceso ocupado", "Espera a que termine el proceso actual.")
            return
        argv = self._adb_command(module, command)
        if self._requires_confirmation(command):
            detail = " ".join(shlex.quote(part) for part in argv)
            approved = messagebox.askyesno(
                "Confirmar acción ADB",
                f"Módulo: {module}\n\nComando:\n{detail}\n\n"
                "Úsalo únicamente sobre un dispositivo o emulador autorizado.", icon="warning")
            if not approved:
                return
        self.request_counter += 1
        self.active_request_id = self.request_log.insert(
            "", "end", values=(module, command, "EN CURSO"))
        self.request_log.see(self.active_request_id)
        self._start_process(argv, f"ejecutando adb {command}", self.adb_output)

    def _base_command(self) -> list[str]:
        command = ["bash", str(self.entrypoint)]
        if self.scope.get() == "static":
            command.append("--static-only")
        elif self.scope.get() == "dynamic":
            command.append("--dynamic-only")
        command.extend(["--tools-dir", self.tools_dir.get(), "--banner-style", self.banner_style.get()])
        if self.skip_apt.get():
            command.append("--skip-apt")
        return command

    def _start_process(self, command: list[str], label: str, output: scrolledtext.ScrolledText) -> None:
        self._active_output = output
        self._set_output(output, f"$ {' '.join(shlex.quote(part) for part in command)}\n\n")
        self.status.set(f"Estado: {label}…")
        self._set_running(True)

        def worker() -> None:
            try:
                self.process = subprocess.Popen(command, cwd=self.root_dir, stdout=subprocess.PIPE,
                                                stderr=subprocess.STDOUT, text=True, bufsize=1,
                                                env=os.environ.copy())
                assert self.process.stdout is not None
                for line in self.process.stdout:
                    self.output_queue.put(("line", line))
                code = self.process.wait()
                self.output_queue.put(("done", str(code)))
            except OSError as exc:
                self.output_queue.put(("error", str(exc)))

        self.worker = threading.Thread(target=worker, daemon=True)
        self.worker.start()

    def run_plan(self) -> None:
        if self.process is None:
            self._start_process(self._base_command() + ["--dry-run", "--plan-json"], "generando plan", self.installer_output)

    def run_install(self) -> None:
        if self.process is not None:
            return
        if self.dry_run.get():
            self._start_process(self._base_command() + ["--dry-run"], "simulando instalación", self.installer_output)
            return
        if messagebox.askyesno("Confirmar instalación",
                               "Esto ejecutará cambios en el host y puede usar sudo.\n\n"
                               "Confirma autorización escrita y alcance correcto.", icon="warning"):
            self._start_process(self._base_command(), "instalando", self.installer_output)

    def cancel_process(self) -> None:
        if self.process is not None and self.process.poll() is None:
            self.process.terminate()
            self.status.set("Estado: cancelando…")

    def _set_running(self, running: bool) -> None:
        self.cancel_button.configure(state="normal" if running else "disabled")

    @staticmethod
    def _set_output(output: scrolledtext.ScrolledText, text: str) -> None:
        output.configure(state="normal")
        output.delete("1.0", "end")
        output.insert("end", text)
        output.see("end")
        output.configure(state="disabled")

    def _append_output(self, text: str) -> None:
        output = getattr(self, "_active_output", self.adb_output)
        output.configure(state="normal")
        output.insert("end", text)
        output.see("end")
        output.configure(state="disabled")

    def _drain_output(self) -> None:
        try:
            while True:
                kind, value = self.output_queue.get_nowait()
                if kind == "line":
                    self._append_output(value or "")
                elif kind == "done":
                    self.process = None
                    self._set_running(False)
                    if self.active_request_id:
                        self.request_log.set(self.active_request_id, "status", f"SALIDA {value}")
                        self.active_request_id = ""
                    self.status.set(f"Estado: terminado · código {value}")
                elif kind == "error":
                    self.process = None
                    self._set_running(False)
                    if self.active_request_id:
                        self.request_log.set(self.active_request_id, "status", "ERROR")
                        self.active_request_id = ""
                    self._append_output(f"Error al iniciar el proceso: {value}\n")
                    self.status.set("Estado: error")
        except queue.Empty:
            pass
        self.after(80, self._drain_output)


def main() -> None:
    root_dir = Path(__file__).resolve().parents[1]
    app = ToolchainGUI(root_dir)
    app.mainloop()


if __name__ == "__main__":
    main()

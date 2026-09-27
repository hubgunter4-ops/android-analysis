"""Vista de configuración y diagnóstico del instalador."""
from __future__ import annotations

import os
import tkinter as tk
from collections.abc import Callable
from tkinter import messagebox, ttk

from . import theme
from .diagnostics import Diagnostic


class InstallerView(ttk.Frame):
    def __init__(self, parent: tk.Misc, on_start: Callable[[list[str], str], None],
                 on_cancel: Callable[[], None], on_diagnostics: Callable[[], None]) -> None:
        super().__init__(parent, style="App.TFrame", padding=(0, 12, 0, 0))
        self.on_start = on_start
        self.on_cancel = on_cancel
        self.on_diagnostics = on_diagnostics
        self.scope = tk.StringVar(value="static")
        self.tools_dir = tk.StringVar(value=os.path.expanduser("~/security-tools"))
        self.banner_style = tk.StringVar(value="0")
        self.skip_apt = tk.BooleanVar(value=False)
        self.dry_run = tk.BooleanVar(value=True)
        self._build()

    def _build(self) -> None:
        self.columnconfigure(0, weight=0, minsize=320)
        self.columnconfigure(1, weight=1)
        self.rowconfigure(0, weight=1)
        card = ttk.Frame(self, style="Card.TFrame", padding=22)
        card.grid(row=0, column=0, sticky="nsew", padx=(0, 16))
        card.columnconfigure(0, weight=1)
        ttk.Label(card, text="PROVISIONAMIENTO", style="Section.TLabel").grid(row=0, column=0, sticky="w")
        ttk.Label(card, text="Prepara una estación reproducible de análisis", style="CardTitle.TLabel").grid(
            row=1, column=0, sticky="w", pady=(4, 18))
        ttk.Label(card, text="1  ·  ALCANCE DEL LABORATORIO", style="Section.TLabel").grid(row=2, column=0, sticky="w")
        for row, value, label in ((3, "static", "Solo análisis estático"), (4, "dynamic", "Solo dinámico / tráfico"),
                                  (5, "all", "Cadena completa")):
            ttk.Radiobutton(card, text=label, value=value, variable=self.scope,
                            style="Panel.TRadiobutton").grid(row=row, column=0, sticky="w", pady=3)
        ttk.Label(card, text="2  ·  DESTINO DE HERRAMIENTAS", style="Section.TLabel").grid(row=7, column=0, sticky="w", pady=(20, 8))
        ttk.Entry(card, textvariable=self.tools_dir, style="Panel.TEntry").grid(row=8, column=0, sticky="ew")
        ttk.Label(card, text="Los binarios se mantienen fuera del árbol del proyecto.", style="Muted.TLabel",
                  wraplength=295).grid(row=9, column=0, sticky="w", pady=(5, 0))
        ttk.Label(card, text="3  ·  PREFERENCIAS", style="Section.TLabel").grid(row=10, column=0, sticky="w", pady=(20, 8))
        ttk.Label(card, text="Estilo del banner", style="Panel.TLabel").grid(row=11, column=0, sticky="w", pady=(0, 4))
        ttk.Combobox(card, textvariable=self.banner_style, values=("0", "1", "2"), state="readonly",
                     style="Panel.TCombobox").grid(row=12, column=0, sticky="ew")
        ttk.Checkbutton(card, text="Omitir APT (imagen ya preparada)", variable=self.skip_apt,
                        style="Panel.TCheckbutton").grid(row=13, column=0, sticky="w", pady=(12, 3))
        ttk.Checkbutton(card, text="Dry-run / no cambiar el host", variable=self.dry_run,
                        style="Panel.TCheckbutton").grid(row=14, column=0, sticky="w", pady=3)
        ttk.Separator(card).grid(row=15, column=0, sticky="ew", pady=18)
        ttk.Button(card, text="DIAGNÓSTICO DEL ENTORNO", command=self.on_diagnostics,
                   style="Secondary.TButton").grid(row=16, column=0, sticky="ew", pady=(0, 8))
        ttk.Button(card, text="GENERAR PLAN  ·  DRY-RUN", command=self.run_plan,
                   style="Accent.TButton").grid(row=17, column=0, sticky="ew", pady=(0, 8))
        ttk.Button(card, text="Ejecutar instalación", command=self.run_install,
                   style="Secondary.TButton").grid(row=18, column=0, sticky="ew", pady=(0, 8))
        self.cancel_button = ttk.Button(card, text="Cancelar proceso", command=self.on_cancel,
                                        state="disabled", style="Danger.TButton")
        self.cancel_button.grid(row=19, column=0, sticky="ew")
        ttk.Label(card, text="La instalación real requiere autorización vigente y puede pedir sudo.",
                  style="Muted.TLabel", wraplength=295).grid(row=20, column=0, sticky="w", pady=(22, 0))

        self.output = theme.make_output(
            self, 0, "SALIDA DEL INSTALADOR", "Salida en vivo · lista para revisión y evidencia local",
            on_clear=self.clear_output, on_copy=self.copy_output,
        )
        self.set_output("$ terminal de ejecución esperando una operación…\n\nListo. Genera un plan dry-run antes de instalar.\n")

    def command(self) -> list[str]:
        command = ["bash", "src/no4nn.sh"]
        if self.scope.get() == "static":
            command.append("--static-only")
        elif self.scope.get() == "dynamic":
            command.append("--dynamic-only")
        command.extend(["--tools-dir", self.tools_dir.get(), "--banner-style", self.banner_style.get()])
        if self.skip_apt.get():
            command.append("--skip-apt")
        return command

    def run_plan(self) -> None:
        self.on_start(self.command() + ["--dry-run", "--plan-json"], "generando plan")

    def run_install(self) -> None:
        if self.dry_run.get():
            self.on_start(self.command() + ["--dry-run"], "simulando instalación")
        elif messagebox.askyesno("Confirmar instalación",
                                 "Esto ejecutará cambios en el host y puede usar sudo.\n\n"
                                 "Confirma autorización escrita y alcance correcto.", icon="warning"):
            self.on_start(self.command(), "instalando")

    def set_running(self, running: bool) -> None:
        self.cancel_button.configure(state="normal" if running else "disabled")

    def append_diagnostics(self, diagnostics: list[Diagnostic]) -> None:
        lines = ["DIAGNÓSTICO INICIAL · no se realizaron cambios\n"]
        for item in diagnostics:
            lines.append(f"[{item.state:4}] {item.name:<18} {item.detail}")
        self.set_output("\n".join(lines) + "\n")

    def set_output(self, text: str) -> None:
        self.output.configure(state="normal")
        self.output.delete("1.0", "end")
        self.output.insert("end", text)
        self.output.see("end")
        self.output.configure(state="disabled")

    def append_output(self, text: str) -> None:
        self.output.configure(state="normal")
        self.output.insert("end", text)
        self.output.see("end")
        self.output.configure(state="disabled")

    def clear_output(self) -> None:
        self.set_output("$ terminal limpia\n\nListo para una nueva operación.\n")

    def copy_output(self) -> None:
        text = self.output.get("1.0", "end-1c")
        self.clipboard_clear()
        self.clipboard_append(text)

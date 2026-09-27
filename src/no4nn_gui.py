#!/usr/bin/env python3
"""Aplicación Tkinter modular para Android Analysis."""
from __future__ import annotations

import tkinter as tk
from pathlib import Path
from tkinter import messagebox, ttk

try:
    from ui import theme
    from ui.adb_view import ADBView
    from ui.diagnostics import run as run_diagnostics
    from ui.installer_view import InstallerView
    from ui.process_runner import ProcessRunner
except ModuleNotFoundError:  # Importación como ``src.no4nn_gui`` durante pruebas.
    from src.ui import theme
    from src.ui.adb_view import ADBView
    from src.ui.diagnostics import run as run_diagnostics
    from src.ui.installer_view import InstallerView
    from src.ui.process_runner import ProcessRunner


class ToolchainGUI(tk.Tk):
    """Shell principal: composición de vistas, estado y ejecución asíncrona."""

    def __init__(self, root_dir: Path) -> None:
        super().__init__()
        self.root_dir = root_dir
        self.title("Android Analysis · Secure toolchain console")
        self.geometry("1320x960")
        self.minsize(1060, 760)
        self.configure(bg=theme.BG)
        theme.configure(self)
        self.status = tk.StringVar(value="Listo · diagnóstico inicial pendiente")
        self.active_output: tk.Text | None = None
        self.runner = ProcessRunner(root_dir, self._process_event)
        self._build_ui()
        self.after(180, self.show_diagnostics)
        self.after(80, self._drain_runner)

    def _build_ui(self) -> None:
        outer = ttk.Frame(self, style="App.TFrame", padding=(28, 24, 28, 18))
        outer.pack(fill="both", expand=True)
        header = ttk.Frame(outer, style="Header.TFrame")
        header.pack(fill="x", pady=(0, 18))
        brand = ttk.Frame(header, style="Header.TFrame")
        brand.pack(side="left", anchor="w")
        ttk.Label(brand, text="SECURE MOBILE LAB", style="Eyebrow.TLabel").pack(anchor="w", pady=(0, 3))
        ttk.Label(brand, text="ANDROID ANALYSIS", style="Title.TLabel").pack(anchor="w")
        ttk.Label(brand, text="Provisionamiento autorizado · reversing · instrumentación · ADB",
                  style="Subtitle.TLabel").pack(anchor="w", pady=(3, 0))
        ttk.Label(header, text="●  LABORATORIO AUTORIZADO", style="Badge.TLabel").pack(side="right", anchor="n", pady=(8, 0))

        notebook = ttk.Notebook(outer, style="App.TNotebook")
        notebook.pack(fill="both", expand=True)
        self.notebook = notebook
        installer_tab = InstallerView(notebook, self.start_process, self.cancel_process, self.show_diagnostics)
        adb_tab = ADBView(notebook, self.root_dir / "docs" / "Funciones_de_ADB_por_módulo.md", self.start_process)
        notebook.add(installer_tab, text="  INSTALADOR  ")
        notebook.add(adb_tab, text="  MÓDULOS ADB  ")
        self.installer_view = installer_tab
        self.adb_view = adb_tab

        status_bar = ttk.Frame(outer, style="Header.TFrame")
        status_bar.pack(fill="x", pady=(14, 0))
        ttk.Label(status_bar, text="●", foreground=theme.SUCCESS, background=theme.BG).pack(side="left", padx=(0, 7))
        ttk.Label(status_bar, textvariable=self.status, style="Subtitle.TLabel").pack(side="left")
        ttk.Label(status_bar, text="v2.1.0  ·  secure provisioning", style="Subtitle.TLabel").pack(side="right")

    def show_diagnostics(self) -> None:
        """Ejecuta solo comprobaciones locales y muestra el resultado."""
        if self.runner.running:
            messagebox.showinfo("Proceso ocupado", "Espera a que termine la operación actual.")
            return
        diagnostics = run_diagnostics(self.root_dir)
        self.installer_view.append_diagnostics(diagnostics)
        warnings = sum(item.state == "WARN" for item in diagnostics)
        self.status.set("Diagnóstico completado · %d advertencia(s)" % warnings if warnings else "Diagnóstico completado · entorno listo")

    def start_process(self, command: list[str], label: str, output: tk.Text) -> None:
        if self.runner.running:
            messagebox.showinfo("Proceso ocupado", "Espera a que termine el proceso actual.")
            return
        self.active_output = output
        rendered = "$ " + " ".join(self._quote(part) for part in command) + "\n\n"
        self._set_output(output, rendered)
        self.status.set(f"En curso · {label}")
        self.installer_view.set_running(True)
        if not self.runner.start(command):
            self.installer_view.set_running(False)
            self.status.set("No se pudo iniciar el proceso")

    @staticmethod
    def _quote(value: str) -> str:
        import shlex
        return shlex.quote(value)

    def cancel_process(self) -> None:
        self.runner.cancel()
        self.status.set("Cancelando proceso…")

    def _process_event(self, kind: str, value: str) -> None:
        if kind == "line" and self.active_output is not None:
            self._append_output(self.active_output, value)
        elif kind == "done":
            self.installer_view.set_running(False)
            self.status.set(f"Terminado · código {value}")
        elif kind == "error":
            self.installer_view.set_running(False)
            if self.active_output is not None:
                self._append_output(self.active_output, f"Error al iniciar el proceso: {value}\n")
            self.status.set("Error al iniciar el proceso")

    def _drain_runner(self) -> None:
        self.runner.drain()
        self.after(80, self._drain_runner)

    @staticmethod
    def _set_output(output: tk.Text, text: str) -> None:
        output.configure(state="normal")
        output.delete("1.0", "end")
        output.insert("end", text)
        output.see("end")
        output.configure(state="disabled")

    @staticmethod
    def _append_output(output: tk.Text, text: str) -> None:
        output.configure(state="normal")
        output.insert("end", text)
        output.see("end")
        output.configure(state="disabled")


def main() -> None:
    root_dir = Path(__file__).resolve().parents[1]
    app = ToolchainGUI(root_dir)
    app.mainloop()


if __name__ == "__main__":
    main()

"""Detección de dispositivos ADB para las pestañas de la GUI.

Lee `adb devices` (solo lectura, timeout de 5 s) y rellena el campo
de serial: si hay un único dispositivo lo pone directamente; si hay
varios, muestra un diálogo para elegir; si no hay ninguno, avisa.
Nunca conecta ni autoriza nada: solo enumera lo que `adb devices`
ya ve.
"""
from __future__ import annotations

import subprocess
import tkinter as tk
from tkinter import messagebox, ttk


def list_devices(timeout: float = 5.0) -> list[tuple[str, str]]:
    """Devuelve [(serial, estado)] según `adb devices`."""
    try:
        result = subprocess.run(
            ["adb", "devices"], capture_output=True, text=True, timeout=timeout,
        )
    except FileNotFoundError as exc:
        raise RuntimeError("adb no está instalado; instala android-tools-adb") from exc
    except subprocess.TimeoutExpired as exc:
        raise RuntimeError("adb devices no respondió en 5 s (servidor colgado?)") from exc
    devices: list[tuple[str, str]] = []
    for line in result.stdout.splitlines():
        if not line.strip() or line.startswith("List of devices"):
            continue
        parts = line.split()
        if len(parts) >= 2:
            devices.append((parts[0], parts[1]))
    return devices


def detect_and_fill(parent: tk.Misc, serial_var: tk.StringVar) -> None:
    """Detecta dispositivos y rellena `serial_var` con el elegido."""
    try:
        devices = list_devices()
    except RuntimeError as exc:
        messagebox.showerror("Detección de dispositivo", str(exc), parent=parent)
        return
    if not devices:
        messagebox.showinfo(
            "Detección de dispositivo",
            "No hay dispositivos en `adb devices`.\n\n"
            "Revisa el cable USB, el puerto, la depuración USB del "
            "teléfono y que sea el único servidor ADB en ejecución.",
            parent=parent)
        return
    if len(devices) == 1:
        serial_var.set(devices[0][0])
        return
    _pick_dialog(parent, devices, serial_var)


def _pick_dialog(parent: tk.Misc, devices: list[tuple[str, str]],
                 serial_var: tk.StringVar) -> None:
    dialog = tk.Toplevel(parent)
    dialog.title("Elegir dispositivo")
    dialog.transient(parent)
    dialog.grab_set()
    dialog.resizable(False, False)
    ttk.Label(dialog, text="Varios dispositivos visibles. Elige uno:",
              padding=(16, 14, 16, 6)).pack(anchor="w")
    listbox = tk.Listbox(dialog, height=min(len(devices), 8), width=52)
    for serial, state in devices:
        listbox.insert("end", f"{serial}  ·  {state}")
    listbox.pack(padx=16, pady=(0, 10), fill="x")
    listbox.selection_set(0)
    listbox.focus_set()

    def use_selected() -> None:
        selection = listbox.curselection()
        if selection:
            serial_var.set(devices[selection[0]][0])
        dialog.destroy()

    buttons = ttk.Frame(dialog, padding=(16, 0, 16, 14))
    buttons.pack(fill="x")
    ttk.Button(buttons, text="Usar este dispositivo", command=use_selected).pack(side="right")
    ttk.Button(buttons, text="Cancelar", command=dialog.destroy).pack(side="right", padx=(0, 8))
    listbox.bind("<Double-Button-1>", lambda _e: use_selected())
    dialog.wait_window()

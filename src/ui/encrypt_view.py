"""Vista de ENCRYPT: verificar el cifrado del sistema y cifrar archivos.

Límite honesto: esta pestaña NO activa el cifrado del sistema. Desde
Android 10 el cifrado es por archivos (FBE) y viene activo de fábrica;
aquí solo se verifica el estado y se cifra/descifra archivos con
AES-256-CBC + PBKDF2 (OpenSSL). La contraseña nunca viaja en argv:
se escribe en un archivo temporal 0600 que el propio script borra
tras usarla (--delete-password-file).
"""
from __future__ import annotations

import os
import tempfile
import tkinter as tk
from collections.abc import Callable
from tkinter import filedialog, messagebox, ttk

from . import device_detect, theme

MODES: tuple[tuple[str, str], ...] = (
    ("verify", "Verificar cifrado del sistema · getprop ro.crypto.*"),
    ("encrypt-file", "Cifrar archivo · AES-256-CBC + PBKDF2 (.aes256)"),
    ("decrypt-file", "Descifrar archivo · .aes256 a original"),
    ("install-app", "Instalar app DeviceCrypt en el dispositivo"),
)


class EncryptView(ttk.Frame):
    """Séptima pestaña: cifrado Android (verificar + cifrar archivos)."""

    def __init__(self, parent: tk.Misc,
                 on_start: Callable[[list[str], str, tk.Text], bool],
                 on_cancel: Callable[[], None]) -> None:
        super().__init__(parent, style="App.TFrame", padding=(0, 12, 0, 0))
        self.on_start = on_start
        self.on_cancel = on_cancel
        self.serial = tk.StringVar()
        self.out_dir = tk.StringVar(value=os.path.expanduser("~/security-tools/encrypt"))
        self.mode = tk.StringVar(value="verify")
        self.file = tk.StringVar()
        self.out = tk.StringVar()
        self.password = tk.StringVar()
        self.apk = tk.StringVar(value="android-app/app-debug.apk")
        self.dry_run = tk.BooleanVar(value=True)
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
        ttk.Label(card, text="ENCRYPT", style="Section.TLabel").grid(row=0, column=0, sticky="w")
        ttk.Label(card, text="Cifrado del sistema y de archivos", style="CardTitle.TLabel").grid(
            row=1, column=0, sticky="w", pady=(4, 6))
        ttk.Label(card, text="Verifica el cifrado del sistema (no lo activa: FBE de fábrica "
                             "desde Android 10) y cifra archivos con AES-256.",
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
        ttk.Label(card, text="Cada operación crea una subcarpeta con fecha y serial (0700).",
                  style="Muted.TLabel", wraplength=295).grid(row=8, column=0, sticky="w", pady=(5, 0))
        ttk.Label(card, text="3  ·  MODO", style="Section.TLabel").grid(row=9, column=0, sticky="w", pady=(16, 8))
        row = 10
        for key, label in MODES:
            ttk.Radiobutton(card, text=label, variable=self.mode, value=key,
                            style="Panel.TRadiobutton").grid(row=row, column=0, sticky="w", pady=2)
            row += 1
        ttk.Label(card, text="4  ·  ARCHIVO (cifrar / descifrar)", style="Section.TLabel").grid(
            row=row, column=0, sticky="w", pady=(16, 8))
        row += 1
        file_row = ttk.Frame(card, style="Card.TFrame")
        file_row.grid(row=row, column=0, sticky="ew")
        file_row.columnconfigure(0, weight=1)
        ttk.Entry(file_row, textvariable=self.file, style="Panel.TEntry").grid(row=0, column=0, sticky="ew")
        ttk.Button(file_row, text="Elegir…", command=self.choose_file,
                   style="Secondary.TButton").grid(row=0, column=1, padx=(8, 0))
        row += 1
        ttk.Label(card, text="Salida (vacío: <entrada>.aes256 al cifrar)",
                  style="Panel.TLabel").grid(row=row, column=0, sticky="w", pady=(6, 4))
        row += 1
        ttk.Entry(card, textvariable=self.out, style="Panel.TEntry").grid(row=row, column=0, sticky="ew")
        row += 1
        ttk.Label(card, text="Contraseña (cifrar / descifrar)", style="Panel.TLabel").grid(
            row=row, column=0, sticky="w", pady=(10, 4))
        row += 1
        ttk.Entry(card, textvariable=self.password, show="•", style="Panel.TEntry").grid(
            row=row, column=0, sticky="ew")
        row += 1
        ttk.Label(card, text="La contraseña se escribe en un archivo temporal 0600 que el "
                             "script borra tras usarla; nunca aparece en el log.",
                  style="Muted.TLabel", wraplength=295).grid(row=row, column=0, sticky="w", pady=(5, 0))
        row += 1
        ttk.Label(card, text="5  ·  APK DEVICECRYPT (instalar en el dispositivo)",
                  style="Section.TLabel").grid(row=row, column=0, sticky="w", pady=(16, 8))
        row += 1
        apk_row = ttk.Frame(card, style="Card.TFrame")
        apk_row.grid(row=row, column=0, sticky="ew")
        apk_row.columnconfigure(0, weight=1)
        ttk.Entry(apk_row, textvariable=self.apk, style="Panel.TEntry").grid(row=0, column=0, sticky="ew")
        ttk.Button(apk_row, text="Elegir…", command=self.choose_apk,
                   style="Secondary.TButton").grid(row=0, column=1, padx=(8, 0))
        row += 1
        ttk.Checkbutton(card, text="Vista previa / dry-run (no llama a adb ni a openssl)",
                        variable=self.dry_run,
                        style="Panel.TCheckbutton").grid(row=row, column=0, sticky="w", pady=(14, 3))
        row += 1
        ttk.Separator(card).grid(row=row, column=0, sticky="ew", pady=14)
        row += 1
        ttk.Button(card, text="VISTA PREVIA  ·  DRY-RUN", command=self.run_preview,
                   style="Accent.TButton").grid(row=row, column=0, sticky="ew", pady=(0, 8))
        row += 1
        ttk.Button(card, text="Ejecutar", command=self.run_execute,
                   style="Secondary.TButton").grid(row=row, column=0, sticky="ew", pady=(0, 8))
        row += 1
        ttk.Button(card, text="Instalar app en dispositivo", command=self.run_install_app,
                   style="Secondary.TButton").grid(row=row, column=0, sticky="ew", pady=(0, 8))
        row += 1
        self.cancel_button = ttk.Button(card, text="Cancelar proceso", command=self.on_cancel,
                                        state="disabled", style="Danger.TButton")
        self.cancel_button.grid(row=row, column=0, sticky="ew")
        row += 1
        ttk.Label(card, text="El formato .aes256 de Ubuntu NO lo abre la app DeviceCrypt "
                             "(.crypt, AES/GCM + Keystore) ni viceversa: son dos rutas "
                             "distintas, documentadas en docs/encrypt-android.md.",
                  style="Muted.TLabel", wraplength=295).grid(row=row, column=0, sticky="w", pady=(18, 0))

        self.output = theme.make_output(
            self, 0, "SALIDA DE ENCRYPT", "Progreso en vivo · veredicto y manifiesto al terminar",
            on_clear=self.clear_output, on_copy=self.copy_output,
        )
        self.set_output("$ terminal de encrypt esperando una operación…\n\nListo. Revisa el plan dry-run antes de ejecutar.\n")

    def detect_device(self) -> None:
        device_detect.detect_and_fill(self, self.serial)

    def choose_file(self) -> None:
        path = filedialog.askopenfilename(parent=self, title="Elegir archivo")
        if path:
            self.file.set(path)

    def choose_apk(self) -> None:
        path = filedialog.askopenfilename(parent=self, title="Elegir APK de DeviceCrypt",
                                          filetypes=[("APK", "*.apk"), ("Todos", "*.*")])
        if path:
            self.apk.set(path)

    def _password_file(self) -> str:
        """Escribe la contraseña en un archivo temporal 0600.

        El script lo borra tras usarlo (--delete-password-file).
        """
        fd, path = tempfile.mkstemp(prefix="devicecrypt-pw-", suffix=".txt")
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(self.password.get())
        return path

    def command(self, include_password: bool = False) -> list[str]:
        command = ["bash", "src/android_toolchain/encrypt.sh"]
        if self.serial.get().strip():
            command.extend(["--serial", self.serial.get().strip()])
        command.extend(["--out-dir", self.out_dir.get(), "--mode", self.mode.get()])
        if self.file.get().strip():
            command.extend(["--file", self.file.get().strip()])
        if self.out.get().strip():
            command.extend(["--out", self.out.get().strip()])
        if self.mode.get() in ("encrypt-file", "decrypt-file") and include_password:
            command.extend(["--password-file", self._password_file(),
                            "--delete-password-file"])
        if self.mode.get() == "install-app" and self.apk.get().strip():
            command.extend(["--apk", self.apk.get().strip()])
        return command

    def run_preview(self) -> None:
        if self.mode.get() in ("encrypt-file", "decrypt-file") and not self.file.get().strip():
            messagebox.showinfo("Sin archivo", "Elige el archivo a cifrar o descifrar.")
            return
        self.on_start(self.command() + ["--dry-run"], "vista previa de encrypt", self.output)

    def run_execute(self) -> None:
        if self.mode.get() in ("encrypt-file", "decrypt-file"):
            if not self.file.get().strip():
                messagebox.showinfo("Sin archivo", "Elige el archivo a cifrar o descifrar.")
                return
            if not self.password.get():
                messagebox.showinfo("Sin contraseña",
                                    "Escribe la contraseña para cifrar o descifrar.")
                return
        if self.dry_run.get():
            self.run_preview()
            return
        mode_label = dict(MODES)[self.mode.get()]
        if not messagebox.askyesno(
                "Confirmar operación de encrypt",
                f"Modo: {mode_label}\nSerial: {self.serial.get().strip() or 'único dispositivo'}\n"
                f"Archivo: {self.file.get().strip() or '—'}\n\n"
                "Verificar solo lee el estado del cifrado. Cifrar o descifrar "
                "escribe archivos con la contraseña indicada: guárdala, sin "
                "ella el archivo no se puede recuperar.",
                icon="warning"):
            return
        self.on_start(self.command(include_password=True) + ["--confirm"],
                      "ejecutando encrypt", self.output)

    def run_install_app(self) -> None:
        if not messagebox.askyesno(
                "Instalar DeviceCrypt",
                f"Serial: {self.serial.get().strip() or 'único dispositivo'}\n"
                f"APK: {self.apk.get().strip()}\n\n"
                "Instala com.zapia.devicecrypt en el dispositivo autorizado "
                "con `adb install -r`. La app solo cifra archivos que tú "
                "elijas; no cambia el cifrado del sistema.",
                icon="warning"):
            return
        command = ["bash", "src/android_toolchain/encrypt.sh"]
        if self.serial.get().strip():
            command.extend(["--serial", self.serial.get().strip()])
        command.extend(["--out-dir", self.out_dir.get(), "--mode", "install-app",
                        "--apk", self.apk.get().strip(), "--confirm"])
        self.on_start(command, "instalando DeviceCrypt", self.output)

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

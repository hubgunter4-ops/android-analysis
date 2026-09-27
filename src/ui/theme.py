"""Tema visual y estilos ttk compartidos por la aplicación."""
from __future__ import annotations

import tkinter as tk
from tkinter import ttk


BG = "#0b1020"
PANEL = "#121a2b"
PANEL_ALT = "#1a2740"
PANEL_SOFT = "#162238"
TEXT = "#f4f7fb"
MUTED = "#9aa9bf"
ACCENT = "#8b9cff"
ACCENT_HOVER = "#aab5ff"
SUCCESS = "#5ee0b7"
WARNING = "#f8c96b"
DANGER = "#ff8d9e"


def configure(root: tk.Misc) -> None:
    """Configura la paleta y todos los estilos ttk de la aplicación."""
    style = ttk.Style(root)
    style.theme_use("clam")
    style.configure("App.TFrame", background=BG)
    style.configure("Header.TFrame", background=BG)
    style.configure("Card.TFrame", background=PANEL, relief="flat")
    style.configure("Title.TLabel", background=BG, foreground=TEXT,
                    font=("TkDefaultFont", 24, "bold"))
    style.configure("Eyebrow.TLabel", background=BG, foreground=ACCENT,
                    font=("TkDefaultFont", 9, "bold"))
    style.configure("Subtitle.TLabel", background=BG, foreground=MUTED,
                    font=("TkDefaultFont", 10))
    style.configure("Badge.TLabel", background=PANEL_SOFT, foreground=SUCCESS,
                    padding=(10, 6), font=("TkDefaultFont", 9, "bold"))
    style.configure("CardTitle.TLabel", background=PANEL, foreground=TEXT,
                    font=("TkDefaultFont", 11, "bold"))
    style.configure("Panel.TLabel", background=PANEL, foreground=TEXT)
    style.configure("Muted.TLabel", background=PANEL, foreground=MUTED)
    style.configure("Section.TLabel", background=PANEL, foreground=ACCENT,
                    font=("TkDefaultFont", 9, "bold"))
    style.configure("Accent.TButton", background=ACCENT, foreground=BG,
                    padding=(14, 9), font=("TkDefaultFont", 10, "bold"), borderwidth=0)
    style.map("Accent.TButton", background=[("active", ACCENT_HOVER)])
    style.configure("Secondary.TButton", background=PANEL_ALT, foreground=TEXT,
                    padding=(12, 8), borderwidth=0)
    style.map("Secondary.TButton", background=[("active", "#294064")])
    style.configure("Danger.TButton", background="#44283a", foreground=DANGER,
                    padding=(12, 8), borderwidth=0)
    style.map("Danger.TButton", background=[("active", "#5b3049")])
    style.configure("Module.TButton", background=PANEL_ALT, foreground=TEXT,
                    anchor="w", padding=(11, 9), font=("TkDefaultFont", 10, "bold"), borderwidth=0)
    style.map("Module.TButton", background=[("active", "#294064")])
    style.configure("Action.TButton", background=PANEL_SOFT, foreground=TEXT,
                    anchor="w", padding=(9, 6), font=("TkDefaultFont", 9), borderwidth=0)
    style.map("Action.TButton", background=[("active", "#263b5c")])
    style.configure("Panel.TCheckbutton", background=PANEL, foreground=TEXT,
                    font=("TkDefaultFont", 9))
    style.configure("Panel.TRadiobutton", background=PANEL, foreground=TEXT)
    style.configure("Panel.TEntry", fieldbackground="#0c1424", foreground=TEXT,
                    insertcolor=TEXT, borderwidth=0, padding=7)
    style.configure("Panel.TCombobox", fieldbackground="#0c1424", foreground=TEXT,
                    borderwidth=0, padding=5)
    style.configure("App.TNotebook", background=BG, borderwidth=0)
    style.configure("App.TNotebook.Tab", background=PANEL, foreground=MUTED,
                    padding=(18, 10), borderwidth=0, font=("TkDefaultFont", 10, "bold"))
    style.map("App.TNotebook.Tab", background=[("selected", PANEL_ALT)],
              foreground=[("selected", TEXT)])
    style.configure("App.Treeview", background="#0c1424", fieldbackground="#0c1424",
                    foreground=TEXT, borderwidth=0, rowheight=28, font=("TkDefaultFont", 9))
    style.configure("App.Treeview.Heading", background=PANEL_SOFT, foreground=MUTED,
                    relief="flat", padding=(8, 7), font=("TkDefaultFont", 9, "bold"))
    style.map("App.Treeview", background=[("selected", "#2a3d66")], foreground=[("selected", TEXT)])


def make_output(parent: tk.Misc, row: int, title: str, subtitle: str,
                on_clear: object | None = None, on_copy: object | None = None) -> tk.Text:
    """Crea un panel de salida de solo lectura con estilo de consola."""
    from tkinter import scrolledtext

    panel = ttk.Frame(parent, style="Card.TFrame", padding=18)
    panel.grid(row=row, column=1, sticky="nsew")
    parent.rowconfigure(row, weight=1)
    panel.rowconfigure(3, weight=1)
    panel.columnconfigure(0, weight=1)
    ttk.Label(panel, text=title, style="Section.TLabel").grid(row=0, column=0, sticky="w", pady=(0, 4))
    toolbar = ttk.Frame(panel, style="Card.TFrame")
    toolbar.grid(row=1, column=0, sticky="ew", pady=(0, 10))
    toolbar.columnconfigure(0, weight=1)
    ttk.Label(toolbar, text=subtitle, style="Muted.TLabel").grid(row=0, column=0, sticky="w")
    if on_copy is not None:
        ttk.Button(toolbar, text="Copiar", command=on_copy, style="Secondary.TButton").grid(row=0, column=1, padx=(8, 0))
    if on_clear is not None:
        ttk.Button(toolbar, text="Limpiar", command=on_clear, style="Secondary.TButton").grid(row=0, column=2, padx=(8, 0))
    ttk.Label(panel, text="TERMINAL DE EJECUCIÓN", style="Section.TLabel").grid(row=2, column=0, sticky="w", pady=(0, 6))
    output = scrolledtext.ScrolledText(panel, wrap="word", bg="#0d1117", fg=TEXT,
                                       insertbackground=TEXT, relief="flat", borderwidth=0,
                                       font=("TkFixedFont", 10), padx=14, pady=14)
    output.grid(row=3, column=0, sticky="nsew")
    output.configure(state="disabled")
    return output

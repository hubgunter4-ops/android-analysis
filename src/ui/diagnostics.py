"""Comprobaciones rápidas y seguras del entorno de análisis."""
from __future__ import annotations

import os
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Diagnostic:
    name: str
    detail: str
    state: str  # OK, WARN, INFO


def _command_version(command: str) -> str | None:
    path = shutil.which(command)
    if not path:
        return None
    try:
        result = subprocess.run([path, "--version"], capture_output=True, text=True,
                                timeout=3, check=False)
    except (OSError, subprocess.SubprocessError):
        return path
    first_line = (result.stdout or result.stderr).splitlines()
    return first_line[0].strip() if first_line else path


def run(root_dir: Path) -> list[Diagnostic]:
    """Devuelve diagnósticos sin conectar ADB ni modificar el sistema."""
    checks: list[Diagnostic] = []
    python_version = f"Python {sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}"
    checks.append(Diagnostic("Python", python_version, "OK" if sys.version_info >= (3, 10) else "WARN"))

    for command, label, required in (
        ("adb", "ADB", False),
        ("java", "Java", True),
        ("sudo", "sudo", False),
        ("curl", "curl", True),
        ("git", "Git", True),
    ):
        version = _command_version(command)
        if version:
            checks.append(Diagnostic(label, version, "OK"))
        else:
            checks.append(Diagnostic(label, "No encontrado", "WARN" if required else "INFO"))

    tools_dir = Path(os.path.expanduser("~/security-tools"))
    try:
        free_gb = shutil.disk_usage(tools_dir.parent).free / (1024 ** 3)
        state = "OK" if free_gb >= 5 else "WARN"
        checks.append(Diagnostic("Espacio libre", f"{free_gb:.1f} GB disponibles", state))
    except OSError as exc:
        checks.append(Diagnostic("Espacio libre", str(exc), "WARN"))

    entrypoint = root_dir / "src" / "no4nn.sh"
    checks.append(Diagnostic("Proyecto", "Entry point disponible" if entrypoint.is_file() else "Entry point ausente",
                             "OK" if entrypoint.is_file() else "WARN"))
    checks.append(Diagnostic("Modo seguro", "No se conectan dispositivos automáticamente", "OK"))
    return checks

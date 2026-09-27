"""Ejecución de procesos en segundo plano para la GUI."""
from __future__ import annotations

import queue
import subprocess
import threading
from collections.abc import Callable
from pathlib import Path


class ProcessRunner:
    """Ejecuta un argv sin shell y entrega eventos a la interfaz."""

    def __init__(self, root_dir: Path, on_event: Callable[[str, str], None]) -> None:
        self.root_dir = root_dir
        self.on_event = on_event
        self.process: subprocess.Popen[str] | None = None
        self._events: queue.Queue[tuple[str, str]] = queue.Queue()
        self._thread: threading.Thread | None = None

    @property
    def running(self) -> bool:
        return self.process is not None and self.process.poll() is None

    def start(self, argv: list[str]) -> bool:
        if self.running:
            return False

        def worker() -> None:
            try:
                self.process = subprocess.Popen(
                    argv, cwd=self.root_dir, stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT, text=True, bufsize=1,
                )
                assert self.process.stdout is not None
                for line in self.process.stdout:
                    self._events.put(("line", line))
                code = self.process.wait()
                self._events.put(("done", str(code)))
            except OSError as exc:
                self._events.put(("error", str(exc)))

        self._thread = threading.Thread(target=worker, daemon=True)
        self._thread.start()
        return True

    def cancel(self) -> None:
        if self.running and self.process is not None:
            self.process.terminate()

    def drain(self) -> None:
        try:
            while True:
                kind, value = self._events.get_nowait()
                self.on_event(kind, value)
        except queue.Empty:
            return

#!/usr/bin/env python3
from pathlib import Path
import sys
import time
import tkinter as tk
from PIL import ImageGrab

root_dir = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(root_dir / "src"))
from no4nn_gui import ToolchainGUI

app = ToolchainGUI(root_dir)
app.update_idletasks()
app.update()
app.notebook.select(1)
app.update_idletasks()
app.update()
time.sleep(0.4)
app.update()
image = ImageGrab.grab()
output = root_dir / "docs" / "adb-panel-preview.png"
image.save(output)
app.destroy()
print(output)

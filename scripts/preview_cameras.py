"""Live preview of both kit cameras with the recording settings (640x480, MJPG).

Use it to aim and focus the cameras and to check that the indices in config.bat are right.
Keys: s = save reference snapshot to reference/, q = quit.
Usage: python scripts/preview_cameras.py [top_index] [side_index]
Without arguments it finds the cameras by the USB IDs in scripts/config.bat (CAM_TOP_ID,
CAM_SIDE_ID), exactly like record.bat and the rollout scripts do.

The cameras are opened with OpenCV's default backend (CAP_ANY), like LeRobot. On this laptop that
resolves to DirectShow, whose numbering find_cameras.py reads.

LeRobot needs opencv-python-headless (no cv2.imshow), so the window is drawn with Tkinter.
"""

import re
import sys
import time
import tkinter as tk
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageTk


def config_indices() -> list[int]:
    from find_cameras import find_indices  # same folder

    text = (Path(__file__).resolve().parent / "config.bat").read_text()
    ids = dict(re.findall(r'set "(CAM_TOP_ID|CAM_SIDE_ID)=([^"]+)"', text))
    return find_indices(ids["CAM_TOP_ID"], ids["CAM_SIDE_ID"])


indices = [int(a) for a in sys.argv[1:3]] or config_indices()
names = ["top", "side"][: len(indices)]
caps = []
for i in indices:
    cap = cv2.VideoCapture(i, cv2.CAP_ANY)
    cap.set(cv2.CAP_PROP_FOURCC, cv2.VideoWriter_fourcc(*"MJPG"))
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
    cap.set(cv2.CAP_PROP_FPS, 30)
    if not cap.isOpened():
        sys.exit(f"camera {i} could not be opened (in use by another program?)")
    print(f"{names[len(caps)]}: index {i}, backend {cap.getBackendName()}")
    caps.append(cap)

out_dir = Path(__file__).resolve().parent.parent / "reference"
latest = []  # (name, raw frame) of the last update, for saving


def grab():
    shown = []
    latest.clear()
    for name, i, cap in zip(names, indices, caps):
        ok, frame = cap.read()
        if not ok:
            frame = np.zeros((480, 640, 3), np.uint8)
        latest.append((name, frame))
        view = frame.copy()
        for x in (213, 427):  # thirds grid to help line the cameras up again later
            cv2.line(view, (x, 0), (x, 479), (255, 255, 255), 1)
        for y in (160, 320):
            cv2.line(view, (0, y), (639, y), (255, 255, 255), 1)
        cv2.putText(view, f"{name} (index {i})", (10, 25), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 255, 255), 2)
        shown.append(view)
    return cv2.cvtColor(np.hstack(shown), cv2.COLOR_BGR2RGB)


def save(_event=None):
    out_dir.mkdir(exist_ok=True)
    stamp = time.strftime("%Y%m%d-%H%M%S")
    for name, frame in latest:
        cv2.imwrite(str(out_dir / f"{name}_{stamp}.jpg"), frame)
    status.config(text=f"Referenzbilder gespeichert in {out_dir}")
    print(f"saved reference images to {out_dir}")


def close(_event=None):
    for cap in caps:
        cap.release()
    root.destroy()


def update():
    photo = ImageTk.PhotoImage(Image.fromarray(grab()))
    video.config(image=photo)
    video.image = photo  # keep a reference, Tk does not
    root.after(10, update)


root = tk.Tk()
root.title("VLA_Trial cameras")
video = tk.Label(root)
video.pack()
status = tk.Label(root, text="s: Referenzbilder speichern   q: beenden")
status.pack(fill="x")
root.bind("s", save)
root.bind("q", close)
root.protocol("WM_DELETE_WINDOW", close)
update()
root.mainloop()

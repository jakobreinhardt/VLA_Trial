"""Find the current OpenCV indices of the two kit cameras by their USB instance IDs.

Windows renumbers cameras (e.g. after re-plugging or a reboot), and OpenCV on this laptop opens
cameras through DirectShow (also with CAP_ANY), so a fixed index can suddenly point to the laptop
webcam. The USB instance ID (e.g. 398f0a3) depends on the USB port and stays the same as long as
each camera stays in its port. This script lists the DirectShow video devices in index order and
prints, for config.bat:
    CAM_TOP=<index>
    CAM_SIDE=<index>
Usage: python find_cameras.py <top_id> <side_id>
"""

import sys

import av


def dshow_video_devices() -> list[tuple[str, str]]:
    """(name, device path) of each DirectShow video device, in OpenCV index order."""
    av.logging.set_level(av.logging.INFO)
    with av.logging.Capture() as messages:
        try:
            av.open("video=dummy", format="dshow", options={"list_devices": "true"})
        except Exception:
            pass  # listing devices always ends with an "input not found" error
    av.logging.set_level(None)
    devices, name, kind = [], None, None
    for _level, _logger, msg in messages:
        text = msg.strip()
        if text.startswith('"'):
            name, kind = text.strip('"'), None
        elif text.startswith("("):
            kind = text.strip("( )")
        elif text.startswith("Alternative name") and kind == "video":
            devices.append((name, text.split('"')[1].lower()))
    return devices


def find_indices(*ids: str) -> list[int]:
    devices = dshow_video_devices()
    found = []
    for cam_id in ids:
        hits = [i for i, (_, path) in enumerate(devices) if cam_id.lower() in path]
        if len(hits) != 1:
            listing = "\n".join(f"  {i}: {n}  {p}" for i, (n, p) in enumerate(devices))
            sys.exit(f"camera ID {cam_id!r} matched {len(hits)} devices. Is it plugged into its usual "
                     f"USB port? Video devices:\n{listing}")
        found.append(hits[0])
    return found


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    top, side = find_indices(sys.argv[1], sys.argv[2])
    print(f"CAM_TOP={top}")
    print(f"CAM_SIDE={side}")

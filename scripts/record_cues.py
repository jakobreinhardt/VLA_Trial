"""Run lerobot-record with instant beeps instead of LeRobot's delayed Windows voice prompts.

On Windows, LeRobot speaks each prompt by starting a new PowerShell speech process without
waiting for it, so "Recording episode N" is heard 2-3 s after the episode has started.
Here the start beep plays *before* recording begins, so recording starts when the beep ends:

    1 high beep   -> recording started, move now
    2 low beeps   -> episode over, reset the scene (then press the right arrow)
    3 short beeps -> episode discarded, it will be recorded again

Same arguments as lerobot-record (record.bat passes them).
"""

import logging
import winsound

from lerobot.scripts import lerobot_record

_orig_log_say = lerobot_record.log_say


def _beep(freq, ms, times=1):
    for _ in range(times):
        try:
            winsound.Beep(freq, ms)
        except RuntimeError:  # no beep device: fall back to the system sound
            winsound.MessageBeep()


def _log_say(text, play_sounds=True, blocking=False):
    if text.startswith("Recording episode"):
        logging.info(text)
        print(f"\n>>> AUFNAHME LAEUFT - Episode {text.split()[-1]}", flush=True)
        if play_sounds:
            _beep(1200, 250)
    elif text == "Reset the environment":
        logging.info(text)
        print("\n>>> ZURUECKSETZEN - Klotz raus, neu hinlegen, dann einmal Pfeil rechts", flush=True)
        if play_sounds:
            _beep(600, 150, times=2)
    elif text == "Re-record episode":
        logging.info(text)
        print("\n>>> EPISODE VERWORFEN - wird neu aufgenommen", flush=True)
        if play_sounds:
            _beep(900, 80, times=3)
    else:  # "Stop recording", "Exiting": not time-critical, keep LeRobot's voice
        _orig_log_say(text, play_sounds, blocking)


lerobot_record.log_say = _log_say

if __name__ == "__main__":
    lerobot_record.main()

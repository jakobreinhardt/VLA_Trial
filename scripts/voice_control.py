"""Voice control for the follower: say "grün", "blau", "stopp" or "beenden".

Starts lerobot-rollout in interactive mode with remote inference (policy on the RunPod GPU) and
feeds it commands from the Windows speech recognizer (offline, German, fixed word list):

    "grün" / "grüner Klotz"   pick up the green block (also switches while the arm is moving)
    "blau" / "blauer Klotz"   pick up the blue block
    "stopp" / "halt"          stop, arm returns to its start position and holds
    "beenden"                 end the session (arm returns to its start position)

Keys work as well (in this window): g = green, b = blue, s = stop, q = quit.
Launched by `scripts\\rollout_remote.bat voice`, which sets the robot/camera variables from
config.bat and opens the SSH tunnel to the policy server.
Optional argument: minimum recognition confidence (default 0.7).
"""

import base64
import msvcrt
import os
import shutil
import subprocess
import sys
import threading
import time

MIN_CONFIDENCE = float(sys.argv[1]) if len(sys.argv) > 1 else 0.7
WORDS = {
    "green": ["grün", "grüner Klotz", "den grünen", "nimm grün"],
    "blue": ["blau", "blauer Klotz", "den blauen", "nimm blau"],
    "stop": ["stopp", "halt"],
    "quit": ["beenden", "Programm beenden"],
}
TASKS = {"green": os.environ["TASK_GREEN"], "blue": os.environ["TASK_BLUE"]}

# Windows speech recognition (System.Speech, de-DE) restricted to the words above. Passed as
# -EncodedCommand (UTF-16) so the umlauts survive Windows PowerShell 5.1.
PS_LISTENER = r"""
Add-Type -AssemblyName System.Speech
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$culture = [System.Globalization.CultureInfo]::new('de-DE')
$rec = [System.Speech.Recognition.SpeechRecognitionEngine]::new($culture)
$choices = [System.Speech.Recognition.Choices]::new()
foreach ($w in @(WORDLIST)) { $choices.Add($w) }
$gb = [System.Speech.Recognition.GrammarBuilder]::new()
$gb.Culture = $culture
$gb.Append($choices)
$rec.LoadGrammar([System.Speech.Recognition.Grammar]::new($gb))
$rec.SetInputToDefaultAudioDevice()
[Console]::WriteLine('READY'); [Console]::Out.Flush()
while ($true) {
  $r = $rec.Recognize([TimeSpan]::FromSeconds(10))
  if ($r) {
    $c = $r.Confidence.ToString([System.Globalization.CultureInfo]::InvariantCulture)
    [Console]::WriteLine($r.Text + '|' + $c); [Console]::Out.Flush()
  }
}
""".replace("WORDLIST", ", ".join(f"'{w}'" for ws in WORDS.values() for w in ws))


def rollout_command() -> list[str]:
    exe = shutil.which("lerobot-rollout")
    if exe is None:
        sys.exit("lerobot-rollout not found: run this from the Miniforge Prompt after `conda activate lerobot`.")
    return [
        exe, "--strategy.type=base",
        "--inference.type=remote",
        "--inference.endpoint=tcp/127.0.0.1:7447",
        "--inference.deployment=blocks_into_box",
        "--inference.mode=chunk", "--inference.chunk_merge=aligned",
        "--inference.semantics=so101-degrees-gripper-percent-v1",
        "--inference.encoding=jpeg", "--inference.jpeg_quality=90",
        "--robot.type=so101_follower", f"--robot.port={os.environ['FOLLOWER_PORT']}", "--robot.id=follower",
        f"--robot.cameras={os.environ['CAMERAS']}",
        f"--rename_map={os.environ['RENAME_MAP'].replace(chr(92), '')}",
        "--fps=30", f"--task={TASKS['blue']}",
        "--interactive=true",
    ]


class VoiceControl:
    def __init__(self):
        env = dict(os.environ, PYTHONUNBUFFERED="1", PYTHONIOENCODING="utf-8")
        self.robot = subprocess.Popen(
            rollout_command(), stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, encoding="utf-8", errors="replace", bufsize=1, env=env)
        encoded = base64.b64encode(PS_LISTENER.encode("utf-16-le")).decode()
        self.listener = subprocess.Popen(
            ["powershell", "-NoProfile", "-NonInteractive", "-EncodedCommand", encoded],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace")
        self.running = False  # a policy run is active (after /start, until /reset)
        self.lock = threading.Lock()
        self.done = threading.Event()
        threading.Thread(target=self._relay_robot, daemon=True).start()
        threading.Thread(target=self._listen, daemon=True).start()

    def _send(self, line: str) -> None:
        try:
            self.robot.stdin.write(line + "\n")
            self.robot.stdin.flush()
        except OSError:
            self.done.set()

    def command(self, what: str, source: str) -> None:
        with self.lock:
            print(f">> {what} ({source})", flush=True)
            if what in TASKS:
                self._send(f"/subtask {TASKS[what]}")
                if not self.running:
                    self._send("/start")
                    self.running = True
            elif what == "stop":
                self._send("/reset")
                self.running = False
            elif what == "quit":
                self._send("/stop")
                self.done.set()

    def _relay_robot(self) -> None:
        for line in self.robot.stdout:
            print(f"[robot] {line.rstrip()}", flush=True)
        self.done.set()

    def _listen(self) -> None:
        for line in self.listener.stdout:
            line = line.strip()
            if not line or line.startswith(("#< CLIXML", "<Objs")):
                continue  # PowerShell progress records, not recognizer output
            if line == "READY":
                print("Spracherkennung bereit: 'grün', 'blau', 'stopp', 'beenden'  (Tasten: g b s q)", flush=True)
                continue
            text, _, conf = line.rpartition("|")
            try:
                confidence = float(conf)
            except ValueError:
                print(f"[voice] {line}", flush=True)  # error output of the recognizer
                continue
            what = next((k for k, ws in WORDS.items() if text in ws), None)
            if what is None or confidence < MIN_CONFIDENCE:
                print(f"[voice] ignoriert: '{text}' ({confidence:.2f})", flush=True)
                continue
            self.command(what, f"Sprache '{text}' {confidence:.2f}")

    def run(self) -> None:
        keys = {"g": "green", "b": "blue", "s": "stop", "q": "quit"}
        try:
            while not self.done.is_set():
                if msvcrt.kbhit():
                    key = msvcrt.getwch().lower()
                    if key in keys:
                        self.command(keys[key], f"Taste {key}")
                time.sleep(0.05)
        except KeyboardInterrupt:
            self.command("quit", "Strg+C")
        finally:
            self.listener.kill()
            try:
                self.robot.wait(timeout=60)  # let the arm return to its start position
            except subprocess.TimeoutExpired:
                self.robot.kill()


if __name__ == "__main__":
    VoiceControl().run()

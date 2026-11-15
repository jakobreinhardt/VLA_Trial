# VLA_Trial – SmolVLA auf dem SO-101

Ziel: Der Follower greift auf Anweisung den **grünen** oder den **blauen** Holzklotz
und legt ihn in die **rote runde Box**. Modell: [SmolVLA](https://huggingface.co/lerobot/smolvla_base)
(450M), feingetunt auf eigenen Demonstrationen.

| Aufgabe (Sprachbefehl) | |
|---|---|
| `Pick up the green block and put it in the red box.` | grün |
| `Pick up the blue block and put it in the red box.` | blau |

Weil das Modell die Farbe aus dem Befehl lernen soll, liegen **bei jeder Aufnahme beide Klötze**
auf dem Tisch, und nur der genannte wird in die Box gelegt. Arbeitsbereich = Fläche innerhalb
des gelben Kreppbands.

## Hardware

- Follower `COM6`, Leader `COM7` (Laptop, Miniforge Prompt, env `lerobot`)
- Kameras: zwei Kit-Kameras an Tischarmen, `top` (schräg von oben) und `side` (seitlich/vorne),
  640×480 @ 30 fps, MJPG. OpenCV-Index 0 ist die Laptop-Webcam.
- Leader-Kalibrierung: Die Motoren passen zur Datei `so_leader\None.json`, daher `LEADER_ID=None`.

Alle Einstellungen stehen in [`scripts/config.bat`](scripts/config.bat).

## Ablauf

Alle Befehle im **Miniforge Prompt**, im Ordner `Desktop\VLA_Trial`, nach `conda activate lerobot`.

### 1. Einmalig vorbereiten
```
pip install -e "C:\Users\jakob\lerobot[smolvla]"
hf auth login
```
Token mit **Write**-Rechten von https://huggingface.co/settings/tokens. Danach in
`scripts\config.bat` `HF_USER` auf deinen Hugging-Face-Namen setzen.

### 2. Kameras ausrichten und fixieren
```
python scripts\preview_cameras.py
```
- Beide Klötze, der ganze Greifbereich und der Greifer müssen im Bild sein.
- Objektiv scharf stellen, Kameraarme festziehen, Positionen auf der Platte markieren.
- `s` speichert Referenzbilder nach `reference\`, `q` beendet.
- Stimmen die Indizes nicht, mit `python scripts\preview_cameras.py 2 1` testen und in `config.bat` anpassen.

### 3. Demonstrationen aufnehmen
```
scripts\record.bat green 10
scripts\record.bat blue 10
```
Abwechselnd in 10er-Blöcken, bis **mindestens 30 pro Farbe** (besser 50) im Datensatz sind.
Jeder weitere Aufruf hängt an denselben Datensatz `HF_USER/so101_blocks_into_box` an.

- Episode: 20 s, danach 20 s zum Zurücksetzen (mit `→` jeweils früher weiter).
- Signale (statt der verzögerten LeRobot-Sprachansage, siehe `scripts/record_cues.py`):
  **1 hoher Piep** = Aufnahme läuft, sofort losbewegen · **2 tiefe Pieps** = Episode vorbei, zurücksetzen ·
  **3 kurze Pieps** = Episode verworfen, wird wiederholt.
- Hand schon vor dem Piep am Leader haben und sofort losbewegen (kein Warten am Anfang).
- `→` einmal drücken, sobald der Arm wieder in Ruheposition ist (beendet die Episode). Erst wenn
  zurückgesetzt ist, `→` ein zweites Mal (beendet die Pause). Zweimal schnell hintereinander überspringt
  das Zurücksetzen!
- `→` / `n`: Episode früher beenden · `←` / `r`: Episode verwerfen und neu · `Esc` / `q`: Sitzung beenden
- Am Ende jeder Sitzung wird der Datensatz (privat) zu Hugging Face hochgeladen.

**Gute Daten:**
- Die Box steht immer an derselben Stelle: Position mit Kreppband markieren und nach jedem Zurücksetzen
  genau dort hinstellen. (Variieren erst, wenn das Grundmodell funktioniert.)
- Klotzpositionen innerhalb des Kreppbands variieren, aber systematisch: z. B. 5 markierte Positionen,
  jeweils mehrmals. Mal grün näher an der Box, mal blau.
- Gleiche Bewegung jedes Mal: anfahren, greifen, anheben, über die Box, loslassen, zurück in Ruheposition.
- In der Pause zwischen den Episoden den Klotz aus der Box nehmen und beide Klötze neu hinlegen.
- Ruhig und flüssig führen, nicht zögern. Fehlversuche mit `←` verwerfen.
- Nichts außer Arm und Klötzen soll sich im Bild bewegen. Leader außerhalb des Kamerabilds.
- Licht und Kameras zwischen den Sitzungen nicht verändern.
- Nach der ersten Sitzung die Cadence-Zeile prüfen: Sie sollte nahe 30 Hz liegen.

Datensatz ansehen: https://huggingface.co/spaces/lerobot/visualize_dataset (eingeloggt, da privat).

### 4. Training in Google Colab (kostenlos)
Der Laptop hat keine NVIDIA-GPU; Training auf der CPU würde Tage dauern. Stattdessen:

1. [colab/train_smolvla.ipynb](colab/train_smolvla.ipynb) in Colab öffnen:
   https://colab.research.google.com → **Datei → Notebook hochladen** (oder bei öffentlichem Repo
   über den Reiter **GitHub**).
2. Den Anweisungen oben im Notebook folgen: T4-GPU wählen, `HF_TOKEN` als Secret anlegen,
   `HF_USER` eintragen, Zellen 1–5 ausführen.
3. Alle 2000 Schritte wird ein Checkpoint auf Hugging Face gesichert. Wird die kostenlose Sitzung
   getrennt: Notebook neu öffnen, Zellen 1–4 ausführen, dann Zelle 6 (Fortsetzen).

Eine T4 ist deutlich langsamer als die A100 aus der LeRobot-Doku (20 000 Schritte ≈ 4–5 h);
rechne mit mehreren Sitzungen. Das fertige Modell landet privat unter
`HF_USER/smolvla_so101_blocks_into_box`.

### 5. Auf dem Roboter testen
```
scripts\rollout.bat green
scripts\rollout.bat blue
```
Läuft 60 s (zweites Argument ändert die Dauer). Mit Strg+C abbrechen und dabei den Arm festhalten.
Das Modell läuft dabei auf der Laptop-CPU. Bewegt sich der Arm ruckelig oder mit Pausen, hilft
RTC: in `rollout.bat` `--inference.type=rtc --inference.rtc.execution_horizon=10 --inference.rtc.max_guidance_weight=10.0`
ergänzen.

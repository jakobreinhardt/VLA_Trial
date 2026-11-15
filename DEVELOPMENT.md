# Instructions for developers

How to set up, record, train and run this project. For an overview of what the project is, see
[README.md](README.md).

**Goal:** On command, the follower picks up the **green** or the **blue** wooden block and puts it in
the **round red box**. Model: [SmolVLA](https://huggingface.co/lerobot/smolvla_base) (450M),
fine-tuned on our own demonstrations.

| Task (language instruction) | Argument |
|---|---|
| `Pick up the green block and put it in the red box.` | `green` |
| `Pick up the blue block and put it in the red box.` | `blue` |

The model has to learn the colour from the instruction, so **both blocks are on the table in every
recording**, and only the named one goes into the box. The workspace is the area inside the yellow
masking tape.

## Hardware

- Follower on `COM6`, leader on `COM7` (laptop, Miniforge Prompt, conda env `lerobot`).
- Cameras: two kit cameras on desk arms, `top` (angled from above) and `side` (side/front),
  640×480 @ 30 fps, MJPG. OpenCV index 0 is the laptop webcam.
- Leader calibration: the motors match the file `so_leader\None.json`, so `LEADER_ID=None`.

All settings are in [`scripts/config.bat`](scripts/config.bat):

| Variable | Meaning |
|---|---|
| `HF_USER` | Hugging Face user name that owns the dataset and model repos |
| `DATASET`, `MODEL` | Repo names: `HF_USER/so101_blocks_into_box` and `HF_USER/smolvla_so101_blocks_into_box` |
| `DATA_ROOT` | Local dataset folder. LeRobot needs it set explicitly to append to an existing dataset |
| `FOLLOWER_PORT`, `LEADER_PORT`, `LEADER_ID` | Serial ports and leader calibration ID |
| `CAM_TOP`, `CAM_SIDE` | OpenCV camera indices |
| `RENAME_MAP` | Maps `top` → `camera1` and `side` → `camera2`, the image keys `smolvla_base` expects. Used for training and rollout |
| `TASK_GREEN`, `TASK_BLUE` | The exact instruction strings. Training and rollout must use identical text |

## Workflow

Run all commands in the **Miniforge Prompt**, in the `Desktop\VLA_Trial` folder, after
`conda activate lerobot`.

### 1. One-time setup

```
pip install -e "%USERPROFILE%\lerobot[smolvla]"
hf auth login
```

Use a token with **write** access from https://huggingface.co/settings/tokens. Then set `HF_USER` in
`scripts\config.bat` to your Hugging Face user name.

The Colab notebook pins LeRobot to commit `3f797de5` (`LEROBOT_REV`) so that it matches the laptop.
If you update LeRobot on the laptop, update `LEROBOT_REV` as well.

### 2. Align and fix the cameras

```
python scripts\preview_cameras.py
```

- Both blocks, the whole reach area and the gripper must be in view.
- Focus the lenses, tighten the camera arms, and mark their positions on the table.
- `s` saves reference images to `reference\` (git-ignored), `q` quits.
- If the indices are wrong, try e.g. `python scripts\preview_cameras.py 2 1` and update `config.bat`.

The preview draws the window with Tkinter because LeRobot installs `opencv-python-headless`, which has
no `cv2.imshow`.

### 3. Record demonstrations

```
scripts\record.bat green 10
scripts\record.bat blue 10
```

Alternate in blocks of 10 until the dataset has **at least 30 per colour** (50 is better). Every run
appends to the same dataset `HF_USER/so101_blocks_into_box`. `record.bat` detects an existing
`DATA_ROOT\meta\info.json` and switches to `--resume=true` automatically.

- Episode: 20 s, followed by 20 s to reset the scene (`→` moves on earlier in both cases).
- Audio cues. `scripts/record_cues.py` replaces LeRobot's Windows voice prompts, which arrive 2–3 s late:
  - **1 high beep**: recording has started, move now.
  - **2 low beeps**: episode over, reset the scene.
  - **3 short beeps**: episode discarded, it will be recorded again.
- Have your hand on the leader before the beep and start moving right away. Don't pause at the start.
- Press `→` once as soon as the arm is back in its rest position (this ends the episode). Press `→`
  a second time only after the scene has been reset (this ends the reset period). Pressing it twice in
  quick succession skips the reset!
- `→` / `n`: end episode early · `←` / `r`: discard and re-record · `Esc` / `q`: end session.
- At the end of each session the dataset is uploaded to Hugging Face (created as private).

**Good data:**

- The box always stands in the same spot. Mark its position with tape and put it back exactly there
  after every reset. (Only vary it once the basic model works.)
- Vary the block positions inside the tape, but systematically: e.g. 5 marked positions, several times
  each. Sometimes green is closer to the box, sometimes blue.
- Same motion every time: approach, grasp, lift, move over the box, release, return to rest.
- During the reset, take the block out of the box and place both blocks again.
- Guide the arm calmly and smoothly, without hesitating. Discard failed attempts with `←`.
- Nothing except the arm and the blocks should move in the image. Keep the leader out of view.
- Don't change the lighting or the cameras between sessions.
- After the first session, check the cadence line in the output: it should be close to 30 Hz.

View the dataset: https://huggingface.co/spaces/lerobot/visualize_dataset (log in if the dataset is
private).

### 4. Train in Google Colab (free)

The laptop has no NVIDIA GPU, and training on the CPU would take days. Instead:

1. Open [colab/train_smolvla.ipynb](colab/train_smolvla.ipynb) in Colab:
   https://colab.research.google.com → **File → Upload notebook** (or use the **GitHub** tab if the
   repo is public).
2. Follow the instructions at the top of the notebook: select a T4 GPU, add `HF_TOKEN` as a secret,
   set `HF_USER`, run sections 1–4, then section 5 (start training).
3. A checkpoint is pushed to Hugging Face every 2000 steps (`SAVE_FREQ`). If the free session
   disconnects, reopen the notebook, run sections 1–4, then section 6 (resume) instead of section 5.

`BATCH` is 32 by default, which fits a T4 (16 GB). Lower it to 16 on `CUDA out of memory`.

A T4 is much slower than the A100 used in the LeRobot docs (20,000 steps ≈ 4–5 h there), so expect
several sessions. The finished model is pushed privately to `HF_USER/smolvla_so101_blocks_into_box`.

The notebook also runs on RunPod / JupyterLab: it uses `/content` (Colab) or `/workspace` (RunPod)
as its working directory, whichever exists.

#### Estimating training time

Before committing to a long run, the optional benchmark section of the notebook (or
`scripts/bench_train.py` locally) trains for about 2 minutes on the real dataset without saving or
uploading anything, and extrapolates to a full run (20,000 steps × batch 64, as in the SmolVLA docs):

```
python scripts\bench_train.py --device cpu  --batch 8  --steps 12  --log 2      (laptop)
python scripts\bench_train.py --device cuda --batch 64 --steps 110 --log 10     (GPU)
```

Add `--root <local dataset folder>` to skip the download. The dataset repo is hard-coded in the script
(`REPO`).

### 5. Test on the robot

```
scripts\rollout.bat green
scripts\rollout.bat blue
```

Runs for 60 s (a second argument changes the duration). Stop with Ctrl+C and hold the arm while doing
so. The model runs on the laptop CPU. If the arm moves jerkily or with pauses, try RTC (real-time
chunking): add
`--inference.type=rtc --inference.rtc.execution_horizon=10 --inference.rtc.max_guidance_weight=10.0`
to `rollout.bat`.

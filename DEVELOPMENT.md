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

[`runpod/setup.sh`](runpod/setup.sh) pins LeRobot on the training GPU to commit `3f797de5`
(`LEROBOT_REV`) so that it matches the laptop. If you update LeRobot on the laptop, update
`LEROBOT_REV` as well.

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

### 4. Train on RunPod (RTX 4090)

The laptop has no NVIDIA GPU and cannot train: in a test on the CPU (batch 8), not even 2 training
steps finished in 22 minutes, because 16 GB of RAM is not enough and Windows kept swapping. Training
runs on a rented RTX 4090 on [RunPod](https://www.runpod.io) instead, driven over SSH with the
scripts in [`runpod/`](runpod):

| Script | Purpose |
|---|---|
| `setup.sh` | One-time: Python 3.12 venv + LeRobot (pinned commit) + SmolVLA extras on the `/workspace` volume |
| `train.sh` | Fine-tunes `lerobot/smolvla_base` on the dataset: batch 64, 20,000 steps, checkpoint every 2000 steps |
| `autostop.sh` | Waits until training has ended (or crashed), then stops the pod so it stops costing GPU money |

**Measured on the 4090** (fp32, batch 64): 0.55 s/step and 14.4 GB of 24 GB VRAM, so 20,000 steps
take about 3 h (≈ $3 at $0.89/h). Data loading is not a bottleneck.

1. **SSH key:** the laptop's public key (`%USERPROFILE%\.ssh\id_ed25519.pub`) must be listed under
   **Credentials → SSH Public Keys** *before* the pod is created. RunPod copies the keys into a pod
   only when it starts.
2. **Deploy a pod:** Pods → Deploy, 1× RTX 4090, On-Demand, template *PyTorch 2.8.0*, container disk
   50 GB, volume disk 50 GB at `/workspace`, *SSH terminal access* on (TCP port 22 is exposed by
   default). When it runs, **Connect → SSH over exposed TCP** shows `ssh root@IP -p PORT ...`.
3. **Set up and start** (Git Bash on the laptop, in this folder; replace `IP` and `PORT`). The second
   command copies the Hugging Face token to the pod without printing it:

   ```
   scp -P PORT runpod/*.sh root@IP:/workspace/
   ssh -p PORT root@IP "mkdir -p /workspace/hf && cat > /workspace/hf/token && chmod 600 /workspace/hf/token" < ~/.cache/huggingface/token
   ssh -p PORT root@IP "bash /workspace/setup.sh"
   ssh -p PORT root@IP 'tmux new-session -d -s train "bash /workspace/train.sh > /workspace/train.log 2>&1"; tmux new-session -d -s autostop "bash /workspace/autostop.sh"'
   ```

   Training runs in `tmux`, so it continues when the SSH connection drops or the laptop sleeps.
4. **Watch progress:**

   ```
   ssh -p PORT root@IP "tr '\r' '\n' < /workspace/train.log | grep -a step: | tail -3"
   ```

5. **Results:** every 2000 steps a checkpoint is pushed privately to
   `HF_USER/smolvla_so101_blocks_into_box` under `checkpoints/<step>` (also as a tag). At the end the
   final model is pushed to the root of the same repo.
6. **Afterwards:** check in the RunPod console that the pod shows as stopped (`autostop.sh` logs to
   `/workspace/autostop.log`). A stopped pod still costs about $0.014/h for its volume. Terminate it
   once the model works.

If training is interrupted, resume from the last local checkpoint with the command in the header of
`train.sh`.

Notes for this LeRobot version: experiment tracking uses `--trackio.*` (there is no `--wandb.*`).
The dataset is cached on the container disk (`HF_LEROBOT_HOME=/root/lerobot_data`), because
`/workspace` is network storage.

#### What happens during training

There is no project-specific training code: `lerobot-train` does everything, in PyTorch (not
scikit-learn). The relevant parts of LeRobot at the pinned commit:

- [`lerobot_train.py` L852](https://github.com/huggingface/lerobot/blob/3f797de5952432284a7c77ad2760218cb74e2f26/src/lerobot/scripts/lerobot_train.py#L852):
  the training loop. Each step takes a batch of 64 random frames from the dataset.
- [`lerobot_train.py` L181](https://github.com/huggingface/lerobot/blob/3f797de5952432284a7c77ad2760218cb74e2f26/src/lerobot/scripts/lerobot_train.py#L181)
  (`update_policy`): forward pass → `loss`, `accelerator.backward(loss)` (gradients),
  `optimizer.step()` (AdamW updates the weights), learning-rate scheduler.
- [`modeling_smolvla.py` L773](https://github.com/huggingface/lerobot/blob/3f797de5952432284a7c77ad2760218cb74e2f26/src/lerobot/policies/smolvla/modeling_smolvla.py#L773):
  the loss. The model sees both camera images, the instruction and the joint state, gets the
  recorded next 50 actions mixed with random noise (flow matching), and predicts the direction back
  to the real actions. The loss is the mean squared error of that prediction.

Only the action expert (100M of the 450M parameters) is trained. The vision-language part of
`smolvla_base` stays frozen (`freeze_vision_encoder`, `train_expert_only`).

### 5. Test on the robot

```
scripts\rollout.bat green
scripts\rollout.bat blue
scripts\rollout.bat green 60 010000      (test the checkpoint from step 10,000)
```

It first downloads the model to `models\` (git-ignored; without the training checkpoints unless one
is named). LeRobot on Windows cannot load a Hub id directly: it turns `user/model` into the invalid
`user\model`. Then it runs for 60 s (the second argument changes the duration). Stop with Ctrl+C and
hold the arm while doing so.

If the final model overfits (stiff motions, only works at the recorded block positions), try an
earlier checkpoint with the third argument. The model runs on the laptop CPU. If the arm moves jerkily or with pauses, try RTC (real-time
chunking): add
`--inference.type=rtc --inference.rtc.execution_horizon=10 --inference.rtc.max_guidance_weight=10.0`
to `rollout.bat`.

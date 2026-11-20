#!/usr/bin/env bash
# Fine-tune SmolVLA on JRrobots4all/so101_blocks_into_box (RTX 4090, ~0.55 s/step at batch 64 fp32).
# Checkpoints every 2000 steps -> /workspace/outputs and privately to the HF model repo (checkpoints/<step>).
# Start detached so it survives a dropped SSH connection:
#   tmux new-session -d -s train "bash /workspace/train.sh > /workspace/train.log 2>&1"
# Resume after an interruption (output_dir must contain checkpoints/last):
#   lerobot-train --config_path=/workspace/outputs/smolvla_so101_blocks_into_box/checkpoints/last/pretrained_model/train_config.json --resume=true
set -uo pipefail
export HF_HOME=/workspace/hf HF_LEROBOT_HOME=/root/lerobot_data
source /workspace/venv/bin/activate
cd /workspace
echo "START $(date -u +%FT%TZ)"
lerobot-train \
  --policy.path=lerobot/smolvla_base \
  --dataset.repo_id=JRrobots4all/so101_blocks_into_box \
  --rename_map='{"observation.images.top": "observation.images.camera1", "observation.images.side": "observation.images.camera2"}' \
  --policy.repo_id=JRrobots4all/smolvla_so101_blocks_into_box \
  --policy.private=true \
  --policy.push_to_hub=true \
  --save_checkpoint_to_hub=true \
  --batch_size=64 \
  --steps=20000 \
  --save_freq=2000 \
  --log_freq=100 \
  --num_workers=8 \
  --output_dir=/workspace/outputs/smolvla_so101_blocks_into_box \
  --job_name=smolvla_so101_blocks_into_box \
  --policy.device=cuda
echo "EXIT $? $(date -u +%FT%TZ)"

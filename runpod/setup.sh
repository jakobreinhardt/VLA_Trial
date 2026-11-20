#!/usr/bin/env bash
# One-time setup on a RunPod GPU pod: Python 3.12 venv + LeRobot (same commit as the laptop) + SmolVLA extras.
# Everything lives on the /workspace volume, so it survives stopping and restarting the pod.
# The HF token goes to /workspace/hf/token (copied from the laptop, see DEVELOPMENT.md).
set -euo pipefail
LEROBOT_REV=3f797de5952432284a7c77ad2760218cb74e2f26
export HF_HOME=/workspace/hf
export PATH="$HOME/.local/bin:$PATH"

echo "== GPU"; nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader
echo "== CPU cores: $(nproc), RAM: $(free -g | awk '/Mem:/{print $2}') GB, disk /workspace: $(df -h /workspace | awk 'NR==2{print $4}') free"

command -v uv >/dev/null || curl -LsSf https://astral.sh/uv/install.sh | sh >/dev/null
command -v ffmpeg >/dev/null || (apt-get update -qq && apt-get install -y -qq ffmpeg >/dev/null) || echo "ffmpeg install failed (pyav fallback is fine)"

cd /workspace
[ -d lerobot ] || git clone -q https://github.com/huggingface/lerobot.git
cd lerobot && git fetch -q origin && git checkout -q "$LEROBOT_REV"
[ -d /workspace/venv ] || uv venv -q --python 3.12 /workspace/venv
source /workspace/venv/bin/activate
uv pip install -q -e ".[training,smolvla]"

python - <<'PY'
import torch
print("== torch", torch.__version__, "| CUDA build", torch.version.cuda, "| GPU available:", torch.cuda.is_available())
if torch.cuda.is_available():
    print("   device:", torch.cuda.get_device_name(0), "| bf16:", torch.cuda.is_bf16_supported())
PY
echo "== LeRobot $(git rev-parse --short HEAD) ready"

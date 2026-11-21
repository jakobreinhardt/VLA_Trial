#!/usr/bin/env bash
# Start the policy server on a (re)started pod. Needs setup.sh to have run once on this volume.
#   bash /workspace/serve.sh [max_hours] [checkpoint]
# checkpoint: optional training step such as 010000 to serve an intermediate checkpoint instead of
#             the final model (downloaded from the Hub to /workspace/ckpt).
# The server runs in tmux session "server" (log: /workspace/server.log). As a safety net the pod
# stops itself after max_hours (default 2), so a forgotten pod does not keep costing GPU money.
# Running the script again restarts the server and the timer.
set -euo pipefail
MAX_HOURS=${1:-2}
CKPT=${2:-}
MODEL_REPO=JRrobots4all/smolvla_so101_blocks_into_box
export HF_HOME=/workspace/hf
source /workspace/venv/bin/activate
# The container disk (uv, pip caches) is wiped when the pod stops; the venv on /workspace is kept.
python -c "import zenoh, msgpack" 2>/dev/null || {
  export PATH="$HOME/.local/bin:$PATH"
  command -v uv >/dev/null || curl -LsSf https://astral.sh/uv/install.sh | sh >/dev/null
  uv pip install -q --python /workspace/venv/bin/python "eclipse-zenoh>=1.9.0,<1.11.0" "msgpack>=1.1.0,<2.0.0"
}
MODEL_ARG=""
if [ -n "$CKPT" ]; then
  hf download "$MODEL_REPO" --include "checkpoints/$CKPT/pretrained_model/*" --local-dir /workspace/ckpt >/dev/null
  MODEL_ARG="--model.repo_or_path=/workspace/ckpt/checkpoints/$CKPT/pretrained_model"
fi
tmux kill-session -t server 2>/dev/null || true
: > /workspace/server.log
tmux new-session -d -s server "lerobot-policy-server --config_path=/workspace/server.yaml $MODEL_ARG 2>&1 | tee -i -a /workspace/server.log"
tmux kill-session -t stoptimer 2>/dev/null || true
tmux new-session -d -s stoptimer "sleep $((MAX_HOURS * 3600)); \
  export \$(tr '\0' '\n' < /proc/1/environ | grep -E '^RUNPOD_(API_KEY|POD_ID)=' | xargs); \
  echo \"timer stop \$(date -u +%FT%TZ)\" >> /workspace/autostop.log; \
  runpodctl stop pod \"\$RUNPOD_POD_ID\" >> /workspace/autostop.log 2>&1"
echo "server starting (tmux 'server', model: ${CKPT:-final}), pod stops itself in ${MAX_HOURS} h"
for i in $(seq 1 120); do
  grep -q "Policy server ready" /workspace/server.log 2>/dev/null && { grep -a "Policy server ready" /workspace/server.log | tail -1; exit 0; }
  grep -qaE "Traceback|Error" /workspace/server.log 2>/dev/null && { tail -30 /workspace/server.log; exit 1; }
  sleep 2
done
echo "server not ready after 4 min:"; tail -20 /workspace/server.log; exit 1

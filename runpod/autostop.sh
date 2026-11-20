#!/usr/bin/env bash
# Stop this pod once the tmux session "train" has ended (training finished or crashed).
# Stop (not terminate): the /workspace volume with checkpoints and venv is kept.
LOG=/workspace/autostop.log
echo "watcher started $(date -u +%FT%TZ)" >> "$LOG"
while tmux has-session -t =train 2>/dev/null; do sleep 60; done
echo "train session ended $(date -u +%FT%TZ): $(grep -a '^EXIT' /workspace/train.log | tail -1)" >> "$LOG"
sleep 120  # grace period for any last hub upload / file flush
export $(tr '\0' '\n' < /proc/1/environ | grep -E '^RUNPOD_(API_KEY|POD_ID)=' | xargs)
echo "stopping pod via runpodctl $(date -u +%FT%TZ)" >> "$LOG"
runpodctl stop pod "$RUNPOD_POD_ID" >> "$LOG" 2>&1 && exit 0
echo "runpodctl failed, trying REST API" >> "$LOG"
curl -s -X POST "https://rest.runpod.io/v1/pods/$RUNPOD_POD_ID/stop" \
  -H "Authorization: Bearer $RUNPOD_API_KEY" >> "$LOG" 2>&1
echo "REST call done $(date -u +%FT%TZ)" >> "$LOG"

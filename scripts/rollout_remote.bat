@echo off
rem Usage: rollout_remote.bat green|blue [seconds]
rem        rollout_remote.bat voice          (voice control, see voice_control.py)
rem Runs the fine-tuned model on the RunPod GPU (policy server, runpod/serve.sh) while the laptop
rem drives the follower. The laptop CPU is far too slow for SmolVLA (~53 s per action chunk).
rem Set POD_HOST and POD_PORT in config.bat first. Stop with Ctrl+C (support the arm).
setlocal
call "%~dp0config.bat" || exit /b 1

set "MODE=%~1"
if /i "%MODE%"=="green" (set "TASK=%TASK_GREEN%") else if /i "%MODE%"=="blue" (set "TASK=%TASK_BLUE%") else if /i not "%MODE%"=="voice" (
    echo Usage: rollout_remote.bat green^|blue [seconds]   or   rollout_remote.bat voice
    exit /b 1
)
set "SECONDS=%~2"
if "%SECONDS%"=="" set "SECONDS=60"

rem SSH tunnel: laptop 127.0.0.1:7447 -> policy server on 127.0.0.1:7447 inside the pod.
rem It opens in its own window; close that window when the robot session is over.
rem (A listening socket has the remote address 0.0.0.0:0; this check works in any Windows language.)
netstat -an -p tcp | findstr /c:"127.0.0.1:7447" | findstr /c:"0.0.0.0:0" >nul || (
    start "RunPod tunnel - close after the robot session" ssh -N -o ServerAliveInterval=15 -o ExitOnForwardFailure=yes -o StrictHostKeyChecking=accept-new -i "%USERPROFILE%\.ssh\id_ed25519" -p %POD_PORT% -L 7447:127.0.0.1:7447 root@%POD_HOST%
    timeout /t 5 /nobreak >nul
)

if /i "%MODE%"=="voice" (
    python "%~dp0voice_control.py"
    exit /b
)

lerobot-rollout --strategy.type=base ^
  --inference.type=remote ^
  --inference.endpoint=tcp/127.0.0.1:7447 ^
  --inference.deployment=blocks_into_box ^
  --inference.mode=chunk --inference.chunk_merge=aligned ^
  --inference.semantics=so101-degrees-gripper-percent-v1 ^
  --inference.encoding=jpeg --inference.jpeg_quality=90 ^
  --robot.type=so101_follower --robot.port=%FOLLOWER_PORT% --robot.id=follower ^
  --robot.cameras="%CAMERAS%" ^
  --rename_map="%RENAME_MAP%" ^
  --fps=30 --task="%TASK%" --duration=%SECONDS%

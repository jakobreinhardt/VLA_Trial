@echo off
rem Usage: rollout.bat green|blue [seconds]
rem Runs the fine-tuned model on the follower. Stop with Ctrl+C (support the arm).
setlocal
call "%~dp0config.bat" || exit /b 1

if /i "%~1"=="green" (set "TASK=%TASK_GREEN%") else if /i "%~1"=="blue" (set "TASK=%TASK_BLUE%") else (
    echo Usage: rollout.bat green^|blue [seconds]
    exit /b 1
)
set "SECONDS=%~2"
if "%SECONDS%"=="" set "SECONDS=60"

lerobot-rollout --strategy.type=base ^
  --robot.type=so101_follower --robot.port=%FOLLOWER_PORT% --robot.id=follower ^
  --robot.cameras="%CAMERAS%" ^
  --rename_map="%RENAME_MAP%" ^
  --policy.path=%HF_USER%/%MODEL% ^
  --task="%TASK%" --duration=%SECONDS%

@echo off
rem Usage: record.bat green|blue [episodes]
rem Records teleoperated episodes into one dataset; later runs append to it (resume).
setlocal
call "%~dp0config.bat" || exit /b 1

if /i "%~1"=="green" (set "TASK=%TASK_GREEN%") else if /i "%~1"=="blue" (set "TASK=%TASK_BLUE%") else (
    echo Usage: record.bat green^|blue [episodes]
    exit /b 1
)
set "N=%~2"
if "%N%"=="" set "N=10"

set "RESUME=false"
if exist "%USERPROFILE%\.cache\huggingface\lerobot\%HF_USER%\%DATASET%\meta\info.json" set "RESUME=true"
echo Task: %TASK%   episodes: %N%   append to existing dataset: %RESUME%

lerobot-record ^
  --robot.type=so101_follower --robot.port=%FOLLOWER_PORT% --robot.id=follower ^
  --robot.cameras="%CAMERAS%" ^
  --teleop.type=so101_leader --teleop.port=%LEADER_PORT% --teleop.id=%LEADER_ID% ^
  --dataset.repo_id=%HF_USER%/%DATASET% --dataset.no_stamp=true --resume=%RESUME% ^
  --dataset.single_task="%TASK%" ^
  --dataset.num_episodes=%N% --dataset.episode_time_s=20 --dataset.reset_time_s=20 ^
  --dataset.private=true ^
  --dataset.streaming_encoding=true --dataset.encoder_threads=2

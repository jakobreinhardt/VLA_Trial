@echo off
rem Usage: rollout.bat green|blue [seconds] [checkpoint]
rem Runs the fine-tuned model on the follower. Stop with Ctrl+C (support the arm).
rem checkpoint: optional training step such as 010000 to test an intermediate checkpoint
rem             instead of the final model.
setlocal
call "%~dp0config.bat" || exit /b 1

if /i "%~1"=="green" (set "TASK=%TASK_GREEN%") else if /i "%~1"=="blue" (set "TASK=%TASK_BLUE%") else (
    echo Usage: rollout.bat green^|blue [seconds] [checkpoint]
    exit /b 1
)
set "SECONDS=%~2"
if "%SECONDS%"=="" set "SECONDS=60"
set "CKPT=%~3"

rem LeRobot on Windows turns a Hub id like user/model into user\model (an invalid repo id),
rem so download the model into models\ first and pass the local folder.
set "MODEL_DIR=%~dp0..\models\%MODEL%"
if "%CKPT%"=="" (
    hf download %HF_USER%/%MODEL% --local-dir "%MODEL_DIR%" --exclude "checkpoints/*" || exit /b 1
    set "POLICY_DIR=%MODEL_DIR%"
) else (
    hf download %HF_USER%/%MODEL% --local-dir "%MODEL_DIR%" --include "checkpoints/%CKPT%/pretrained_model/*" || exit /b 1
    set "POLICY_DIR=%MODEL_DIR%\checkpoints\%CKPT%\pretrained_model"
)
if not exist "%POLICY_DIR%\model.safetensors" (
    echo No model found in %POLICY_DIR%. Has training finished and pushed the model?
    exit /b 1
)

lerobot-rollout --strategy.type=base ^
  --robot.type=so101_follower --robot.port=%FOLLOWER_PORT% --robot.id=follower ^
  --robot.cameras="%CAMERAS%" ^
  --rename_map="%RENAME_MAP%" ^
  --policy.path="%POLICY_DIR%" ^
  --task="%TASK%" --duration=%SECONDS%

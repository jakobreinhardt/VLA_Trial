@echo off
rem Shared settings for all scripts. Edit HF_USER once after `hf auth login`.
set "HF_USER=JRrobots4all"
set "DATASET=so101_blocks_into_box"
set "MODEL=smolvla_so101_blocks_into_box"
rem Local dataset folder (LeRobot needs it explicitly to append to an existing dataset).
set "DATA_ROOT=%USERPROFILE%\.cache\huggingface\lerobot\%HF_USER%\%DATASET%"

set "FOLLOWER_PORT=COM6"
set "LEADER_PORT=COM7"
rem The leader motors match calibration file so_leader\None.json (see README).
set "LEADER_ID=None"

rem The two kit cameras, identified by their USB instance ID (fixed per USB port). Windows
rem renumbers cameras, so find_cameras.py looks up their current OpenCV indices every time.
rem Keep each camera in its USB port (top: 398f0a3, side: 24750a61). Check with preview_cameras.py.
set "CAM_TOP_ID=398f0a3"
set "CAM_SIDE_ID=24750a61"
set "CAM_TOP="
set "CAM_SIDE="
for /f "delims=" %%L in ('python "%~dp0find_cameras.py" %CAM_TOP_ID% %CAM_SIDE_ID%') do set "%%L"
if not defined CAM_SIDE (
    echo Kit cameras not found, see the message above.
    exit /b 1
)
set "CAMERAS={ top: {type: opencv, index_or_path: %CAM_TOP%, width: 640, height: 480, fps: 30, fourcc: MJPG}, side: {type: opencv, index_or_path: %CAM_SIDE%, width: 640, height: 480, fps: 30, fourcc: MJPG}}"
set "RENAME_MAP={\"observation.images.top\": \"observation.images.camera1\", \"observation.images.side\": \"observation.images.camera2\"}"

set "TASK_GREEN=Pick up the green block and put it in the red box."
set "TASK_BLUE=Pick up the blue block and put it in the red box."

rem RunPod pod running the policy server (rollout_remote.bat). Both values change on every pod
rem start: RunPod console -> Pods -> Connect -> "SSH over exposed TCP": ssh root@POD_HOST -p POD_PORT
set "POD_HOST=213.173.108.228"
set "POD_PORT=15986"

if "%HF_USER%"=="CHANGE_ME" (
    echo Set HF_USER in scripts\config.bat first ^(your Hugging Face username^).
    exit /b 1
)

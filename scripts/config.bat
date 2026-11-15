@echo off
rem Shared settings for all scripts. Edit HF_USER once after `hf auth login`.
set "HF_USER=JRrobots4all"
set "DATASET=so101_blocks_into_box"
set "MODEL=smolvla_so101_blocks_into_box"

set "FOLLOWER_PORT=COM6"
set "LEADER_PORT=COM7"
rem The leader motors match calibration file so_leader\None.json (see README).
set "LEADER_ID=None"

rem OpenCV indices of the two kit cameras (0 = laptop webcam). Check with preview_cameras.py.
set "CAM_TOP=1"
set "CAM_SIDE=2"
set "CAMERAS={ top: {type: opencv, index_or_path: %CAM_TOP%, width: 640, height: 480, fps: 30, fourcc: MJPG}, side: {type: opencv, index_or_path: %CAM_SIDE%, width: 640, height: 480, fps: 30, fourcc: MJPG}}"
set "RENAME_MAP={\"observation.images.top\": \"observation.images.camera1\", \"observation.images.side\": \"observation.images.camera2\"}"

set "TASK_GREEN=Pick up the green block and put it in the red box."
set "TASK_BLUE=Pick up the blue block and put it in the red box."

if "%HF_USER%"=="CHANGE_ME" (
    echo Set HF_USER in scripts\config.bat first ^(your Hugging Face username^).
    exit /b 1
)

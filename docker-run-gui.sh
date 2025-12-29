#!/bin/bash

# 1. Allow X11 connections (for GUI)
echo "Allowing xhost local connections..."
xhost +local:docker

# 2. check if DISPLAY is set, default to :0 if not
if [ -z "$DISPLAY" ]; then
  export DISPLAY=:0
fi

# 3. Run the container
echo "Starting container..."
docker run -it \
    --net=host \
    --env="DISPLAY=$DISPLAY" \
    --env="QT_X11_NO_MITSHM=1" \
    --volume="/tmp/.X11-unix:/tmp/.X11-unix:rw" \
    --privileged \
    --name camera_imu_calib \
    camera_imu_calib
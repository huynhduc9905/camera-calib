#!/bin/bash

# check if it have ORB_SLAM3, realsense-ros, allan_variance_ros folders
if [ ! -d "ORB_SLAM3" ] || [ ! -d "realsense-ros" ] || [ ! -d "allan_variance_ros" ]; then
    echo "Error, need to run this script in the root directory of the repository"
    exit 1
fi

# build the docker image
docker build -t camera_imu_calib .
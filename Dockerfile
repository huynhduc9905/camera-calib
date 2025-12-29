# Base image: ROS Noetic (Ubuntu 20.04)
FROM osrf/ros:noetic-desktop-full

# Or base image from official ROS repository (amd64/arm64)
# FROM ros:noetic-ros-base-focal

# Set environment to non-interactive to avoid hanging during apt installs
ENV DEBIAN_FRONTEND=noninteractive

# Set working directory to /root/ as requested feature
WORKDIR /root

# ---------------------------------------------------------
# 1. System Prep & Dependencies
# ---------------------------------------------------------
RUN apt-get update && apt-get install -y \
    git cmake build-essential pkg-config \
    libusb-1.0-0-dev libssl-dev \
    libgtk-3-dev libglfw3-dev libgl1-mesa-dev libglu1-mesa-dev \
    libboost-dev libboost-thread-dev libboost-filesystem-dev \
    libglew-dev python3-dev \
    vim wget x11-apps tmux \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------
# 2. Install RealSense SDK (Driver) -- latest git version
# ---------------------------------------------------------
RUN git clone https://github.com/IntelRealSense/librealsense.git && \
    cd librealsense && \
    # Install Udev rules (Note: Device access requires --privileged at runtime)
    # ./scripts/setup_udev_rules.sh && \
    mkdir build && cd build && \
    cmake .. \
    -DCMAKE_BUILD_TYPE=Release \
    -DFORCE_RSUSB_BACKEND=true \
    -DBUILD_GRAPHICAL_EXAMPLES=false \
    -DBUILD_EXAMPLES=false && \
    make -j$(nproc) && \
    make install && \
    ldconfig

# ---------------------------------------------------------
# 3. Install Pangolin (Visualization)
# ---------------------------------------------------------
RUN git clone https://github.com/stevenlovegrove/Pangolin.git && \
    cd Pangolin && \
    # Checkout v0.6 (Critical for ORB-SLAM3 and ubuntu 20.04)
    git checkout v0.6 && \
    mkdir build && cd build && \
    # Fix "deprecated-copy" error
    cmake -DCMAKE_CXX_FLAGS="-Wno-error=deprecated-copy" .. && \
    make -j$(nproc) && \
    make install && \
    ldconfig

# ---------------------------------------------------------
# 4. Install ORB-SLAM3
# ---------------------------------------------------------
# Copy local ORB_SLAM3 folder
COPY ORB_SLAM3 /root/ORB_SLAM3    
RUN cd ORB_SLAM3 && \
    # Fix OpenCV Version: Replace 4.4 with 4.2 in CMakeLists.txt (Ubuntu 20.04 default)
    sed -i 's/find_package(OpenCV 4.4)/find_package(OpenCV 4.2 REQUIRED)/' CMakeLists.txt && \
    # Fix 'usleep' error: Add <unistd.h> to System.cc and Tracking.cc
    # sed -i '1i#include <unistd.h>' src/System.cc && \
    # sed -i '1i#include <unistd.h>' src/Tracking.cc && \
    chmod +x build.sh && \
    # Build Thirdparty and Main Project
    ./build.sh

# Remove ORB_SLAM3/Examples/Calibration/recorder_realsense_D435i binary (NEED TO REBUILD ON HOST)
RUN rm -rf ORB_SLAM3/Examples/Calibration/recorder_realsense_D435i

# ---------------------------------------------------------
# 5. Install Kalibr
# ---------------------------------------------------------
# Install Kalibr dependencies
RUN apt-get update && apt-get install -y \
    git wget autoconf automake nano \
    python3-dev python3-pip python3-scipy python3-matplotlib \
    ipython3 python3-wxgtk4.0 python3-tk python3-igraph python3-pyx \
    libeigen3-dev libboost-all-dev libsuitesparse-dev \
    doxygen \
    libopencv-dev \
    libpoco-dev libtbb-dev libblas-dev liblapack-dev libv4l-dev \
    python3-catkin-tools python3-osrf-pycommon && \
    rm -rf /var/lib/apt/lists/*

# Create the workspace and build kalibr in it
ENV WORKSPACE=/root/catkin_ws

# Change shell to bash to support source
SHELL ["/bin/bash", "-c"]

# Initialize catkin workspace
RUN source /opt/ros/noetic/setup.bash && \
    mkdir -p $WORKSPACE/src && \
    cd $WORKSPACE && \
    catkin init && \
    catkin config --extend /opt/ros/noetic && \
    catkin config --cmake-args -DCMAKE_BUILD_TYPE=Release

# Clone and build Kalibr
RUN cd $WORKSPACE/src && \
    git clone https://github.com/ethz-asl/kalibr.git

RUN source /opt/ros/noetic/setup.bash && \
    cd $WORKSPACE && \
    catkin build --verbose -j$(nproc)

# ---------------------------------------------------------
# 6. Install Allan Variance ROS
# ---------------------------------------------------------
# Copy local allan_variance_ros folder
COPY allan_variance_ros $WORKSPACE/src/allan_variance_ros

# Initialize and update rosdep
RUN rosdep init || true && \
    rosdep update

# Install dependencies using rosdep
RUN source /opt/ros/noetic/setup.bash && \
    rosdep install --from-paths $WORKSPACE/src --ignore-src -r -y

# Build the workspace with allan_variance_ros
RUN source /opt/ros/noetic/setup.bash && \
    cd $WORKSPACE && \
    catkin build

# ---------------------------------------------------------
# 7. Install realsense-ros
# ---------------------------------------------------------
# Copy local realsense-ros folder
COPY realsense-ros $WORKSPACE/src/realsense-ros

# Install dependencies using rosdep
RUN source /opt/ros/noetic/setup.bash && source $WORKSPACE/devel/setup.bash && \
    apt-get update && apt-get install -y ros-noetic-ddynamic-reconfigure && \
    rosdep install --from-paths $WORKSPACE/src --ignore-src -r -y

# Build the workspace with realsense-ros
RUN source /opt/ros/noetic/setup.bash && source $WORKSPACE/devel/setup.bash && \
    cd $WORKSPACE && \
    catkin build

# Source the workspace in bashrc and add alias for VS Code
RUN echo "source /root/catkin_ws/devel/setup.bash" >> /root/.bashrc && \
    echo "alias code='code --no-sandbox --user-data-dir /root/.code'" >> /root/.bashrc

# Install dependencies and VS Code
RUN apt-get update && apt-get install -y \
    wget \
    gpg \
    apt-transport-https \
    software-properties-common \
    # 1. Import the Microsoft GPG key
    && wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > packages.microsoft.gpg \
    && install -D -o root -g root -m 644 packages.microsoft.gpg /etc/apt/keyrings/packages.microsoft.gpg \
    # 2. Add the VS Code repository
    && sh -c 'echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list' \
    && rm -f packages.microsoft.gpg \
    # 3. Install VS Code
    && apt-get update && apt-get install -y code \
    # 4. Cleanup to reduce image size
    && rm -rf /var/lib/apt/lists/*

# When a user runs a command we will run this code before theirs
ENTRYPOINT export KALIBR_MANUAL_FOCAL_LENGTH_INIT=1 && \
    # Source the Kalibr workspace automatically so commands are available
    . "$WORKSPACE/devel/setup.bash" && \
    # Ensure we land in /root at the end
    cd /root && \
    /bin/bash
#!/bin/bash

# Project Identity
export ROM_NAME="AfterlifeOS"
export MANIFEST_URL="https://github.com/AfterlifeOS/afterlife_manifest"
export ROM_VERSION="16"

# Build Configuration
export DEVICE=${DEVICE:-"bacon"} # Default device if none provided
export BUILD_TYPE=${BUILD_TYPE:-"userdebug"}

# Directories
export WORKSPACE=${WORKSPACE:-$(pwd)}
export ROOTDIR="${WORKSPACE}/source"
export CCACHE_DIR="${WORKSPACE}/ccache"

# Ccache Configuration (Handled automatically by build/envsetup.sh)
# export USE_CCACHE=1
# export CCACHE_EXEC=$(which ccache)

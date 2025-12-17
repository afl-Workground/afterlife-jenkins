#!/bin/bash

# Project Identity
export ROM_NAME="AfterlifeOS"
export MANIFEST_URL="https://github.com/AfterlifeOS/afterlife_manifest"
export ROM_VERSION="16"

# Build Configuration
export DEVICE=${DEVICE:-"bacon"} # Default device if none provided
export BUILD_TYPE=${BUILD_TYPE:-"userdebug"}

# Directories
# CRITICAL: Point ROOTDIR outside the GitHub Actions workspace to prevent auto-cleanup!
export WORKSPACE=${WORKSPACE:-$(pwd)}
# export ROOTDIR="${WORKSPACE}/source" <--- OLD (DANGEROUS)
export ROOTDIR="${HOME}/android/source" # <--- NEW (SAFE & PERSISTENT & PORTABLE)

export CCACHE_DIR="${HOME}/.ccache" # Also keep ccache outside

# Ccache Configuration
export USE_CCACHE=1
export CCACHE_EXEC=/usr/bin/ccache

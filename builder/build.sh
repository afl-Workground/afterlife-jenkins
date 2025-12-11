#!/bin/bash

# Load configuration
LOCALDIR=`cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd`
. $LOCALDIR/config.sh

cd $ROOTDIR

echo "[*] Setting up Ccache Directory..."
# Ensure the persistent directory exists before envsetup uses it
mkdir -p "$CCACHE_DIR"
export CCACHE_DIR="$CCACHE_DIR"

echo "[*] Setting up Environment..."
. build/envsetup.sh

# CLEAN_BUILD Logic
# Enforce Admin restriction for full wipes
if [ "$CLEAN_BUILD" = "true" ]; then
    if [ "$IS_ADMIN" = "true" ]; then
        echo "[!!!] AUTHENTICATED: Admin requested Full Wipe. Executing 'make clean'..."
        make clean
    else
        echo "[!] PERMISSION DENIED: Full Clean ('make clean') is restricted to Admins/Owners."
        echo "[*] Falling back to Surgical Clean (Device specific)..."
        CLEAN_BUILD="false" # Force false to trigger standard logic below
    fi
fi

# Surgical Cleanup Function (Mimics ros-builder's cleanup)
surgical_clean() {
    echo "[*] Executing Surgical Cleanup..."
    
    # 1. Clean output for THIS device only
    if [ -d "out/target/product/${DEVICE}" ]; then
        echo "    -> Removing device output: out/target/product/${DEVICE}"
        rm -rf "out/target/product/${DEVICE}"
    fi
    
    # 2. Clean 'install' artifacts (images) but keep compiled intermediates if possible
    make installclean
    
    # 3. Clean tracked repositories from sync.sh (The "ros-builder" explicit cleanup style)
    TRACK_FILE="tracked_paths_${DEVICE}.txt"
    if [ -f "$TRACK_FILE" ]; then
        echo "    -> Cleaning up tracked source directories from $TRACK_FILE..."
        while IFS= read -r path; do
            if [ -d "$path" ]; then
                echo "       Removing: $path"
                rm -rf "$path"
            fi
        done < $TRACK_FILE
        rm $TRACK_FILE
    fi
}

# Execute Cleanup
surgical_clean

# Import Telegram Utils
source builder/tg_utils.sh

# --- TELEGRAM START NOTIFICATION ---
BUILD_START_TIME=$(date +"%Y-%m-%d %H:%M:%S")
JOB_URL="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"

START_MSG="🚀 *AfterlifeOS Build Started!*
*Device:* \`${DEVICE}\`
*Type:* \`${BUILD_TYPE}\`
*Variant:* \`${BUILD_VARIANT}\`
*Host:* \`VPS-Runner\`
*Date:* ${BUILD_START_TIME}

[View Action Log](${JOB_URL})"

# Send initial message and save ID for editing
MSG_ID=$(tg_send_message "$START_MSG")
echo "Telegram Message ID: $MSG_ID"

# --- BUILD PROCESS WITH MONITORING ---

echo "[*] Running goafterlife for device ${DEVICE}..."
LOG_FILE="build_progress.log"

# Define the build command based on variant
if [ "$BUILD_VARIANT" = "release" ]; then
    BUILD_CMD="goafterlife ${DEVICE} ${BUILD_TYPE} --release"
else
    BUILD_CMD="goafterlife ${DEVICE} ${BUILD_TYPE}"
fi

# 1. Start Monitoring Loop in Background
(
    while true; do
        sleep 15
        # Check if process is still running (we'll kill this loop later)
        
        # Grep the last progress line: [ 15% 1234/5678]
        # We use 'tr' to clean up control characters if any
        PROGRESS=$(grep -o "\[ *[0-9]*% [0-9]*/[0-9]*\]" $LOG_FILE | tail -n 1)
        
        if [ ! -z "$PROGRESS" ]; then
            NEW_TEXT="🚀 *AfterlifeOS Build in Progress...*
*Device:* \`${DEVICE}\`
*Current Status:* \`${PROGRESS}\`
*Job:* [Click Here](${JOB_URL})"
            
            tg_edit_message "$MSG_ID" "$NEW_TEXT"
        fi
    done
) &
MONITOR_PID=$!

# 2. Execute the Build (Piping to log and stdout)
# We use 'tee' so Jenkins/GitHub still sees the logs in real-time
$BUILD_CMD 2>&1 | tee $LOG_FILE

# Capture Exit Code
BUILD_STATUS=${PIPESTATUS[0]}

# 3. Kill Monitor Loop
kill $MONITOR_PID

# --- POST BUILD NOTIFICATION ---

END_TIME=$(date +"%Y-%m-%d %H:%M:%S")

if [ $BUILD_STATUS -eq 0 ]; then
    echo "BUILD SUCCESS!"
    
    # --- COPY ARTIFACTS TO WORKSPACE ---
    # GitHub Actions/Jenkins can only upload artifacts from within their own workspace.
    # Since we build in an external ROOTDIR, we must copy the results back.
    
    SRC_OUT="${ROOTDIR}/out/target/product/${DEVICE}"
    DEST_OUT="${WORKSPACE}/source/out/target/product/${DEVICE}"
    
    echo "[*] Copying artifacts to Workspace for Upload..."
    mkdir -p "$DEST_OUT"
    
    # Copy ZIPs, JSONs, and checksums
    cp -v "$SRC_OUT"/AfterlifeOS*.zip "$DEST_OUT/" 2>/dev/null || true
    cp -v "$SRC_OUT"/*.json "$DEST_OUT/" 2>/dev/null || true
    
    echo "    -> Artifacts copied to: $DEST_OUT"
    # -----------------------------------
    
    SUCCESS_MSG="✅ *AfterlifeOS Build SUCCESS!*
*Device:* \`${DEVICE}\`
*Variant:* \`${BUILD_VARIANT}\`
*Time:* ${END_TIME}

📦 *Artifacts will be available here:*
[Download Page](${JOB_URL})"

    # Reply/Edit with Success
    tg_send_message "$SUCCESS_MSG"

else
    echo "BUILD FAILED!"
    
    FAILURE_MSG="❌ *AfterlifeOS Build FAILED!*
*Device:* \`${DEVICE}\`
*Time:* ${END_TIME}
*Check the attached log for details.*"

    tg_send_message "$FAILURE_MSG"

    # Try to find the error log
    ERROR_LOG="out/error.log"
    if [ ! -f "$ERROR_LOG" ]; then
        # If no specific error log, take the tail of our build log
        echo "out/error.log not found, using tail of build log..."
        tail -n 200 $LOG_FILE > build_error_snippet.log
        ERROR_LOG="build_error_snippet.log"
    fi
    
    tg_upload_log "$ERROR_LOG" "Build Failure Log - ${DEVICE}"
    exit 1
fi

rm -f $LOG_FILE

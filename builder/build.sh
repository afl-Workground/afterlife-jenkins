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
source build/envsetup.sh

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

# Import Telegram Utils
source "$LOCALDIR/tg_utils.sh"

# --- HELPER FUNCTIONS (From Reference) ---

function fetch_progress() {
    # Extracts the last Ninja progress line (e.g., [ 45% 1000/2000]) from the log
    local PROGRESS=$(
        tail -n 50 "$LOG_FILE" |
        grep -Po '\[\s*\d+% \d+/\d+\]' |
        tail -n 1
    )

    if [ -z "$PROGRESS" ]; then
        echo "Initializing..."
    else
        echo "$PROGRESS"
    fi
}

# --- TELEGRAM START NOTIFICATION ---
BUILD_START_TIME_READABLE=$(date +"%Y-%m-%d %H:%M:%S")
BUILD_START_TIMESTAMP=$(date +"%s")
JOB_URL="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"

# HTML Formatted Start Message
START_MSG="🚀 *AfterlifeOS Build Started!*
*Device:* \`${DEVICE}\`
*Type:* \`${BUILD_TYPE}\`
*Variant:* \`${BUILD_VARIANT}\`
*Host:* \`VPS-Runner\`
*Date:* ${BUILD_START_TIME_READABLE}

[View Action Log](${JOB_URL})"

# Send initial message and save ID for editing
MSG_ID=$(tg_send_message "$START_MSG")
echo "Telegram Message ID: $MSG_ID"

# --- BUILD PROCESS WITH MONITORING ---

echo "[*] Running goafterlife for device ${DEVICE}..."
LOG_FILE="${ROOTDIR}/build_progress.log" # Use absolute path in ROOTDIR
rm -f "$LOG_FILE"

# Define the build command based on variant
if [ "$BUILD_VARIANT" = "release" ]; then
    BUILD_CMD="goafterlife ${DEVICE} ${BUILD_TYPE} --release"
else
    BUILD_CMD="goafterlife ${DEVICE} ${BUILD_TYPE}"
fi

# 1. Start Monitoring Loop in Background
(
    previous_progress=""
    while true; do
        sleep 20
        # Check if process is still running (we'll kill this loop later)
        
        CURRENT_PROGRESS=$(fetch_progress)
        
        if [ "$CURRENT_PROGRESS" != "$previous_progress" ] && [ "$CURRENT_PROGRESS" != "Initializing..." ]; then
            NEW_TEXT="🚀 *AfterlifeOS Build in Progress...*
*Device:* \`${DEVICE}\`
*Current Status:* \`${CURRENT_PROGRESS}\`
*Job:* [Click Here](${JOB_URL})"
            
            tg_edit_message "$MSG_ID" "$NEW_TEXT"
            previous_progress="$CURRENT_PROGRESS"
        fi
    done
) &
MONITOR_PID=$!

# 2. Execute the Build (Piping to log and stdout)
# set -o pipefail ensures that if the build fails, the exit code is preserved even after piping to tee
set -o pipefail
$BUILD_CMD 2>&1 | tee "$LOG_FILE"

# Capture Exit Code immediately
BUILD_STATUS=$?
set +o pipefail

# 3. Kill Monitor Loop
kill $MONITOR_PID 2>/dev/null

# --- POST BUILD NOTIFICATION ---

BUILD_END_TIMESTAMP=$(date +"%s")
DIFFERENCE=$((BUILD_END_TIMESTAMP - BUILD_START_TIMESTAMP))
HOURS=$(($DIFFERENCE / 3600))
MINUTES=$((($DIFFERENCE % 3600) / 60))

# --- VERIFY BUILD SUCCESS ---
# We verify success by checking if the output ZIP actually exists.
# This prevents "False Success" when the build tool crashes/panics but returns exit code 0.

# Define expected output path
SRC_OUT="${ROOTDIR}/out/target/product/${DEVICE}"
ZIP_FILE_CHECK=$(ls "$SRC_OUT"/AfterlifeOS*.zip 2>/dev/null | head -n 1)

if [ $BUILD_STATUS -eq 0 ] && [ ! -z "$ZIP_FILE_CHECK" ] && [ -f "$ZIP_FILE_CHECK" ]; then
    echo "BUILD SUCCESS! Artifact found: $ZIP_FILE_CHECK"
    
    # --- COPY ARTIFACTS TO WORKSPACE ---
    # GitHub Actions/Jenkins can only upload artifacts from within their own workspace.
    # Since we build in an external ROOTDIR, we must copy the results back.
    
    DEST_OUT="${WORKSPACE}/source/out/target/product/${DEVICE}"
    
    echo "[*] Copying artifacts to Workspace for Upload..."
    mkdir -p "$DEST_OUT"
    
    # Copy ZIPs, JSONs, and checksums
    cp -v "$SRC_OUT"/AfterlifeOS*.zip "$DEST_OUT/" 2>/dev/null || true
    cp -v "$SRC_OUT"/*.json "$DEST_OUT/" 2>/dev/null || true
    
    echo "    -> Artifacts copied to: $DEST_OUT"
    # -----------------------------------
    
    # Get File Info for Message
    ZIP_FILE=$(ls "$DEST_OUT"/AfterlifeOS*.zip | head -n 1)
    if [ -f "$ZIP_FILE" ]; then
        FILE_SIZE=$(ls -sh "$ZIP_FILE" | awk '{print $1}')
        MD5SUM=$(md5sum "$ZIP_FILE" | awk '{print $1}')
    else
        FILE_SIZE="Unknown"
        MD5SUM="Unknown"
    fi

    SUCCESS_MSG="✅ *AfterlifeOS Build SUCCESS!*
*Device:* \`${DEVICE}\`
*Variant:* \`${BUILD_VARIANT}\`
*Size:* \`${FILE_SIZE}\`
*MD5:* \`${MD5SUM}\`
*Duration:* ${HOURS}h ${MINUTES}m

📦 *Artifacts will be available here:*
[Download Page](${JOB_URL})"

    # Reply/Edit with Success
    tg_edit_message "$MSG_ID" "$SUCCESS_MSG"

else
    echo "BUILD FAILED! (Exit Code: $BUILD_STATUS or No Zip File)"
    
    FAILURE_MSG="❌ *AfterlifeOS Build FAILED!*
*Device:* \`${DEVICE}\`
*Duration:* ${HOURS}h ${MINUTES}m
*Check the attached log for details.*"

    tg_edit_message "$MSG_ID" "$FAILURE_MSG"

    # Try to find the error log
    ERROR_LOG="${ROOTDIR}/out/error.log"
    if [ ! -f "$ERROR_LOG" ]; then
        # If no specific error log, take the tail of our build log
        echo "out/error.log not found, using tail of build log..."
        tail -n 200 "$LOG_FILE" > build_error_snippet.log
        ERROR_LOG="build_error_snippet.log"
    fi
    
    tg_upload_log "$ERROR_LOG" "Build Failure Log - ${DEVICE}"
    
    # Clean up before exit
    surgical_clean
    exit 1
fi

rm -f "$LOG_FILE"

# Final Cleanup (Success Case)
surgical_clean

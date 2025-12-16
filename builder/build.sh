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

# --- GAPPS INJECTION LOGIC ---
if [ ! -z "$GAPPS_VARIANT" ] && [ "$GAPPS_VARIANT" != "default" ]; then
    echo "[*] Handling GApps Variant: $GAPPS_VARIANT"
    
    MK_FILE=""
    TRACK_FILE="${ROOTDIR}/tracked_paths_${DEVICE}.txt"

    # 1. Priority: Check tracked paths (Optimized)
    if [ -f "$TRACK_FILE" ]; then
        # Read tracked paths and look for the makefile inside device trees
        while IFS= read -r path; do
            if [[ "$path" == device/* ]]; then
                TARGET="$path/afterlife_${DEVICE}.mk"
                if [ -f "$TARGET" ]; then
                    MK_FILE="$TARGET"
                    break
                fi
            fi
        done < "$TRACK_FILE"
    fi

    # 2. Fallback: Global search (Safety Net)
    if [ -z "$MK_FILE" ]; then
        echo "    -> Target not found in tracked paths. Scanning 'device' directory..."
        MK_FILE=$(find device -type f -name "afterlife_${DEVICE}.mk" 2>/dev/null | head -n 1)
    fi

    if [ -f "$MK_FILE" ]; then
        echo "    -> Found Device Makefile: $MK_FILE"
        
        # Prepare the Make flag string
        NEW_FLAG="AFTERLIFE_GAPPS := $GAPPS_VARIANT"
        
        # Check if the flag already exists in the file
        if grep -q "AFTERLIFE_GAPPS :=" "$MK_FILE"; then
            echo "    -> Updating existing flag..."
            sed -i "s|AFTERLIFE_GAPPS :=.*|$NEW_FLAG|g" "$MK_FILE"
        else
            echo "    -> Appending new flag..."
            # Append to end of file, ensuring a newline before it
            sed -i -e '$a\' -e "$NEW_FLAG" "$MK_FILE"
        fi
        
        # Verify
        grep "AFTERLIFE_GAPPS :=" "$MK_FILE"
    else
        echo "    [!] Warning: afterlife_${DEVICE}.mk not found! GApps flag might not be applied."
    fi
else
    echo "[*] GApps Variant is Default or Unset. Using device tree configuration."
fi

source build/envsetup.sh

# Determine FSGen Status String
if [ "${DISABLE_FSGEN}" == "true" ]; then
    FSGEN_STATUS="Disabled"
else
    FSGEN_STATUS="Enabled"
fi

# Determine GApps Display
case "${GAPPS_VARIANT}" in
    "true") GAPPS_DISPLAY="Full" ;;
    "false") GAPPS_DISPLAY="Vanilla" ;;
    "core") GAPPS_DISPLAY="Core" ;;
    "basic") GAPPS_DISPLAY="Basic" ;;
    "default") GAPPS_DISPLAY="Default" ;;
    *) GAPPS_DISPLAY="${GAPPS_VARIANT}" ;;
esac

# CLEAN_BUILD Logic
# Enforce Admin restriction for full wipes
if [ "$CLEAN_BUILD" = "true" ]; then
    if [ "$IS_ADMIN" = "true" ]; then
        echo "[!!!] AUTHENTICATED: Admin requested Full Wipe. Executing 'make clean'..."
        make clean
    else
        echo "[!] PERMISSION DENIED: Full Clean ('make clean') is restricted to Admins/Owners."
        echo "[*] Skipping Full Wipe. Relying on 'sync.sh' for standard cleanup."
        CLEAN_BUILD="false" # Force false to trigger standard logic below
    fi
fi

# Import Telegram Utils
source "$LOCALDIR/tg_utils.sh"

# --- DETERMINE BUILD USER ---
if [ -n "$REQUESTER" ]; then
    BUILD_USER="$REQUESTER"
else
    BUILD_USER="${GITHUB_ACTOR:-Unknown}"
fi

# Define User Tag (with Telegram ID)
if [ -n "$TG_USER_ID" ]; then
    USER_TAG="[$BUILD_USER](tg://user?id=$TG_USER_ID)"
else
    USER_TAG="\`$BUILD_USER\`"
fi

# --- HELPER FUNCTIONS (From Reference) ---

function fetch_progress() {
    # 1. Read the last line from the clean FILTERED_LOG
    #    This file is created in real-time by the build process using grep filter
    local RAW_LOG=$(tail -n 1 "$FILTERED_LOG" 2>/dev/null)

    if [ -z "$RAW_LOG" ]; then
        echo "Initializing..."
        return
    fi

    # 2. Check if this is the Kati/Soong phase (Setup/Analyzing)
    # Filter keywords: finishing, analyzing, bootstrap, including, initializing
    # Also 'writing legacy' (specific to Kati: "writing legacy Make module rules")
    if echo "$RAW_LOG" | grep -qE "including|initializing|finishing|analyzing|bootstrap|writing legacy"; then
        echo "Initializing Build System (Kati/Soong)..."
        return
    fi

    # 3. If it passes the filter above, this is the Ninja phase (Compilation)
    # Extract Percentage (digits before comma)
    local PCT=$(echo "$RAW_LOG" | cut -d',' -f1)
    # Extract Counts (digits after comma)
    local COUNTS=$(echo "$RAW_LOG" | cut -d',' -f2)
    
    # Validation: Safety net if parsing fails
    if [ -z "$PCT" ] || [ -z "$COUNTS" ]; then
        echo "Initializing..." # Default fallback if the format doesn't match Ninja yet
        return
    fi

    # 4. Generate Progress Bar (10 blocks total)
    local FILLED=$((PCT / 10))
    local EMPTY=$((10 - FILLED))
    local BAR=""
    
    for ((i=0; i<FILLED; i++)); do BAR="${BAR}█"; done
    for ((i=0; i<EMPTY; i++)); do BAR="${BAR}░"; done

    # 5. Clean Output Format
    echo "[${BAR}] ${PCT}% (${COUNTS})"
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
*GApps:* \`${GAPPS_DISPLAY}\`
*FSGen:* \`${FSGEN_STATUS}\`
*Dirty:* \`${DIRTY_BUILD}\`
*Clean:* \`${CLEAN_BUILD}\`
*Host:* \`$(hostname)\`
*Build by:* $USER_TAG
*Date:* ${BUILD_START_TIME_READABLE}

[View Action Log](${JOB_URL})"

# Read MSG_ID from previous job
MSG_ID=$(cat "${WORKSPACE}/.tg_msg_id" 2>/dev/null)

if [ -n "$MSG_ID" ]; then
    echo "Found existing Telegram Message ID: $MSG_ID"
    tg_edit_message "$MSG_ID" "$START_MSG"
else
    echo "⚠️ Message ID not found. Sending new message."
    MSG_ID=$(tg_send_message "$START_MSG")
    # Save for smart_upload
    echo "$MSG_ID" > "${WORKSPACE}/.tg_msg_id"
fi

# --- TRAP FOR CANCELLATION ---
function handle_cancel() {
    echo " [!] Received Termination Signal (User Cancelled)"
    
    # Just kill the processes. 
    # Notification is handled reliably by 'Notify Workflow Cancellation' in afterlife_build.yml
    
    # Kill monitor
    if [ ! -z "$MONITOR_PID" ]; then
        kill $MONITOR_PID 2>/dev/null
    fi

    # Kill actual build process
    if [ ! -z "$BUILD_PID" ]; then
        echo "Killing build process $BUILD_PID..."
        kill $BUILD_PID 2>/dev/null
        # Wait a bit to ensure it dies
        wait $BUILD_PID 2>/dev/null
    fi

    exit 130
}

# Trap SIGINT (Ctrl+C) and SIGTERM (GitHub Cancel)
trap 'handle_cancel' SIGINT SIGTERM

# --- BUILD PROCESS WITH MONITORING ---

echo "[*] Running goafterlife for device ${DEVICE}..."
LOG_FILE="${ROOTDIR}/build_progress.log" # Use absolute path in ROOTDIR
FILTERED_LOG="${ROOTDIR}/monitoring_progress.log" # File dedicated to holding clean progress logs
rm -f "$LOG_FILE" "$FILTERED_LOG" "${ROOTDIR}/out/error.log" "${ROOTDIR}/build_error_snippet.log"

# MARK STATE FOR NEXT BUILD (Lazy Cleanup)
echo "${DEVICE}" > "${ROOTDIR}/.last_build_device"
echo "[*] State saved: Next build will check this device tag."

# Define the build command based on variant
if [ "$BUILD_VARIANT" = "Release" ]; then
    BUILD_CMD="goafterlife ${DEVICE} ${BUILD_TYPE} --release"
else
    BUILD_CMD="goafterlife ${DEVICE} ${BUILD_TYPE}"
fi

# 1. Start Monitoring Loop in Background
(
    previous_progress=""
    while true; do
        sleep 10
        # Check if process is still running (we'll kill this loop later)
        
        CURRENT_PROGRESS=$(fetch_progress)
        
        if [ "$CURRENT_PROGRESS" != "$previous_progress" ] && [ "$CURRENT_PROGRESS" != "Initializing..." ]; then
            NEW_TEXT="⚙️ *AfterlifeOS Build in Progress...*
*Device:* \`${DEVICE}\`
*Type:* \`${BUILD_TYPE}\`
*Variant:* \`${BUILD_VARIANT}\`
*GApps:* \`${GAPPS_DISPLAY}\`
*FSGen:* \`${FSGEN_STATUS}\`
*Dirty:* \`${DIRTY_BUILD}\`
*Clean:* \`${CLEAN_BUILD}\`
*Build by:* $USER_TAG
*Build Progress:* \`${CURRENT_PROGRESS}\`

[View Realtime Log](${JOB_URL})"
            
            tg_edit_message "$MSG_ID" "$NEW_TEXT"
            previous_progress="$CURRENT_PROGRESS"
        fi
    done
) &
MONITOR_PID=$!

# 2. Execute the Build (Piping to log and stdout)
# Technique: Run in background to allow TRAP to catch SIGTERM immediately
# Refactored: Use explicit awk with fflush() to avoid 'Broken pipe' and dependency on stdbuf
set -o pipefail
(
    $BUILD_CMD 2>&1 | tee "$LOG_FILE" | \
    tee >(grep --line-buffered -P '^\[\s*[0-9]+% [0-9]+/[0-9]+' | \
    awk -v logfile="${ROOTDIR}/monitoring_progress.log" '{
        # 1. Strip ANSI Colors (simple regex approach for standard build output)
        gsub(/\x1b\[[0-9;]*m/, "");
        
        # 2. Extract Percentage and Counts
        # Format input expected: "[ 12% 123/456] ..."
        match($0, /([0-9]+)% ([0-9]+\/[0-9]+)/, arr);
        
        if (arr[1] != "" && arr[2] != "") {
             print arr[1] "," arr[2] > logfile;
             fflush(logfile);
        }
    }')
) &
BUILD_PID=$!

# Wait for the build process to finish
# 'wait' is interruptible by traps (unlike blocking commands)
wait $BUILD_PID
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
    
    # Get File Info for Message
    ZIP_FILE=$(ls "$SRC_OUT"/AfterlifeOS*.zip | head -n 1)
    FILE_SIZE_BYTES=0
    if [ -f "$ZIP_FILE" ]; then
        FILE_SIZE=$(ls -sh "$ZIP_FILE" | awk '{print $1}')
        MD5SUM=$(md5sum "$ZIP_FILE" | awk '{print $1}')
        FILE_SIZE_BYTES=$(stat -c%s "$ZIP_FILE")
    else
        FILE_SIZE="Unknown"
        MD5SUM="Unknown"
    fi

    BASE_MSG="✅ *AfterlifeOS Build SUCCESS!*
*Device:* \`${DEVICE}\`
*Type:* \`${BUILD_TYPE}\`
*Variant:* \`${BUILD_VARIANT}\`
*GApps:* \`${GAPPS_DISPLAY}\`
*FSGen:* \`${FSGEN_STATUS}\`
*Dirty:* \`${DIRTY_BUILD}\`
*Clean:* \`${CLEAN_BUILD}\`
*Build by:* $USER_TAG
*Size:* \`${FILE_SIZE}\`
*MD5:* \`${MD5SUM}\`
*Duration:* ${HOURS}h ${MINUTES}m

[View Action Log](${JOB_URL})"

    # --- RELEASE VARIANT LOGIC (JSON UPLOAD) ---
    JSON_LINK_TEXT=""
    if [ "$BUILD_VARIANT" = "Release" ]; then
        JSON_FILE="${SRC_OUT}/${DEVICE}.json"
        
        if [ -f "$JSON_FILE" ]; then
            echo "[*] Release Build Detected. Uploading OTA JSON..."
            # TELEGRAM_OTA_TOPIC_ID must be set in env/config, otherwise defaults to main topic
            JSON_LINK=$(tg_upload_json "$JSON_FILE" "OTA Json - ${DEVICE} (${BUILD_TYPE})" "$TELEGRAM_CHAT_ID" "$TELEGRAM_OTA_TOPIC_ID")
            
            if [ ! -z "$JSON_LINK" ]; then
                echo "[*] JSON Uploaded: $JSON_LINK"
                # Save link for smart_upload.sh
                echo "$JSON_LINK" > "${ROOTDIR}/.json_link"
                
                JSON_LINK_TEXT="
📄 [View OTA JSON]($JSON_LINK)"
            else
                echo "[!] Failed to get JSON Link."
            fi
        else
            echo "[!] Release build but ${DEVICE}.json not found in ${SRC_OUT}"
        fi
    fi

    # Standard Case: Processing upload via smart_upload.sh
    SUCCESS_MSG="${BASE_MSG}${JSON_LINK_TEXT}

🚀 *Build Complete. Processing upload...*
Please wait for the final download link."

    # Reply/Edit with Success
    tg_edit_message "$MSG_ID" "$SUCCESS_MSG"

else
    echo "BUILD FAILED! (Exit Code: $BUILD_STATUS or No Zip File)"
    
    FAILURE_MSG="❌ *AfterlifeOS Build FAILED!*
*Device:* \`${DEVICE}\`
*Type:* \`${BUILD_TYPE}\`
*Variant:* \`${BUILD_VARIANT}\`
*GApps:* \`${GAPPS_DISPLAY}\`
*FSGen:* \`${FSGEN_STATUS}\`
*Dirty:* \`${DIRTY_BUILD}\`
*Clean:* \`${CLEAN_BUILD}\`
*Build by:* $USER_TAG
*Duration:* ${HOURS}h ${MINUTES}m

*Check the attached log for details:*
[View Detailed Log](${JOB_URL})"

    tg_edit_message "$MSG_ID" "$FAILURE_MSG"

    # Try to find the error log
    if [ -f "${ROOTDIR}/out/error.log" ]; then
        ERROR_LOG="${ROOTDIR}/out/error.log"
    else
        # If no specific error log, take the tail of our build log
        echo "out/error.log not found, using tail of build log..."
        # Ensure filesystem buffers are flushed before tailing
        sync
        ERROR_LOG="${ROOTDIR}/build_error_snippet.log"
        tail -n 200 "$LOG_FILE" > "$ERROR_LOG"
    fi
    
    tg_upload_log "$ERROR_LOG" "Build Failure Log - ${DEVICE}"
    
    # Clean up before exit
    # LAZY CLEANUP: We DO NOT clean here anymore. 
    # If the user rebuilds the same device, we want these files.
    # If they build a different device, 'sync.sh' will handle the cleanup.
    exit 1
fi

rm -f "$LOG_FILE" "$FILTERED_LOG"

# Final Cleanup (Success Case)
# LAZY CLEANUP: No action needed. 'sync.sh' handles the next run.
echo "Build complete. Artifacts preserved for potential re-run."

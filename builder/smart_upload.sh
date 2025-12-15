#!/bin/bash

# Smart Upload Handler
# Logic: Checks file size. If > 2GB, uploads to Gofile and creates a text link.
# Requires: curl, jq
# Inherits: TELEGRAM_TOKEN, TELEGRAM_CHAT_ID from environment

source builder/tg_utils.sh
source builder/config.sh

DEVICE="$1"
OUT_DIR="$ROOTDIR/out/target/product/${DEVICE}"

# Determine Builder Name / Tag
BUILDER_NAME="${GITHUB_ACTOR:-Unknown}"
if [ -n "$TG_USER_ID" ]; then
    USER_TAG="<a href='tg://user?id=$TG_USER_ID'>$BUILDER_NAME</a>"
else
    USER_TAG="<code>$BUILDER_NAME</code>"
fi

# Fix: Get the MOST RECENT zip file (handling multiple files case)
ZIP_PATH=$(ls -t "$OUT_DIR"/AfterlifeOS*.zip 2>/dev/null | head -n 1)
LIMIT_BYTES=0 # Force Gofile upload (GitHub Storage Quota Full)

if [ -z "$ZIP_PATH" ]; then
    echo "SmartUpload: No zip file found in $OUT_DIR. Skipping."
    exit 0
fi

FILE_SIZE=$(stat -c%s "$ZIP_PATH")
FILE_SIZE_GB=$(awk -v bytes="$FILE_SIZE" 'BEGIN {printf "%.2f GB", bytes/1073741824}')
FILE_NAME=$(basename "$ZIP_PATH")

echo "Found: $FILE_NAME"
echo "Size: $FILE_SIZE bytes"
echo "Limit: $LIMIT_BYTES bytes"

# Upload Function (Direct Endpoint per User Request)
upload_to_gofile() {
    local fpath="$1"
    
    echo "    -> Uploading to Gofile (Direct)..." >&2
    # Using direct endpoint as requested for stability
    UPLOAD_RESPONSE=$(curl -# -X POST https://upload.gofile.io/uploadfile -F "file=@$fpath")
    
    # Extract link
    DOWNLOAD_LINK=$(echo "$UPLOAD_RESPONSE" | jq -r '.data.downloadPage')
    
    if [ "$DOWNLOAD_LINK" != "null" ] && [ ! -z "$DOWNLOAD_LINK" ]; then
        echo "$DOWNLOAD_LINK"
        return 0
    else
        echo "Error: $UPLOAD_RESPONSE" >&2
        return 1
    fi
}

if [ "$FILE_SIZE" -gt "$LIMIT_BYTES" ]; then
    echo "⚠️ Bypass GitHub Artifacts (Storage Full/Limit). Uploading to Gofile..."
    
    # Read Message ID from previous step
    MSG_ID=$(cat "${WORKSPACE}/.tg_msg_id" 2>/dev/null)
    
    # Determine FSGen Status String
    if [ "${DISABLE_FSGEN}" == "true" ]; then
        FSGEN_STATUS="Disabled"
    else
        FSGEN_STATUS="Enabled"
    fi

    # HTML Upload Message
    UPLOAD_MSG="📦 <b>Artifact Upload Started</b>
<b>Device:</b> <code>${DEVICE}</code>
<b>Type:</b> <code>${BUILD_TYPE}</code>
<b>Variant:</b> <code>${BUILD_VARIANT:-Unknown}</code>
<b>FSGen:</b> <code>${FSGEN_STATUS}</code>
<b>Dirty:</b> <code>${DIRTY_BUILD}</code>
<b>Clean:</b> <code>${CLEAN_BUILD}</code>
Uploading to Gofile server..."

    if [ -z "$MSG_ID" ]; then
        echo "⚠️ Message ID not found. Falling back to new message."
        tg_send_message "$UPLOAD_MSG" "$TELEGRAM_CHAT_ID" "HTML"
    else
        tg_edit_message "$MSG_ID" "🚀 <b>Build Success!</b>
<b>Device:</b> <code>${DEVICE}</code>
<b>Type:</b> <code>${BUILD_TYPE}</code>
<b>Variant:</b> <code>${BUILD_VARIANT:-Unknown}</code>
<b>FSGen:</b> <code>${FSGEN_STATUS}</code>
<b>Dirty:</b> <code>${DIRTY_BUILD}</code>
<b>Clean:</b> <code>${CLEAN_BUILD}</code>
<b>Size:</b> <code>${FILE_SIZE_GB}</code>

📦 <b>Uploading artifact to Gofile...</b>
Please wait..." "$TELEGRAM_CHAT_ID" "HTML"
    fi

    DOWNLOAD_LINK=$(upload_to_gofile "$ZIP_PATH")

    if [ $? -eq 0 ]; then
        echo "✅ Gofile Upload Success: $DOWNLOAD_LINK"
        
        # Create a text file with the link
        LINK_FILE="$OUT_DIR/AfterlifeOS_Download_Link.txt"
        echo "Artifact uploaded to Gofile (GitHub Storage Full)." > "$LINK_FILE"
        echo "$DOWNLOAD_LINK" >> "$LINK_FILE"
        
        # Calculate additional info
        MD5SUM=$(md5sum "$ZIP_PATH" | awk '{print $1}')

        # Check for JSON Link (Release Build)
        JSON_LINK_HTML=""
        if [ -f "$ROOTDIR/.json_link" ]; then
            JSON_LINK_RAW=$(cat "$ROOTDIR/.json_link")
            if [ ! -z "$JSON_LINK_RAW" ]; then
                JSON_LINK_HTML="
📄 <a href='${JSON_LINK_RAW}'>View OTA JSON</a>"
            fi
            # Clean up
            rm "$ROOTDIR/.json_link"
        fi

        # Send Success Message (HTML)
        SUCCESS_MSG="✅ <b>AfterlifeOS Build and Upload Complete!</b>
<b>Device:</b> <code>${DEVICE}</code>
<b>Type:</b> <code>${BUILD_TYPE}</code>
<b>Variant:</b> <code>${BUILD_VARIANT:-Unknown}</code>
<b>FSGen:</b> <code>${FSGEN_STATUS}</code>
<b>Dirty:</b> <code>${DIRTY_BUILD}</code>
<b>Clean:</b> <code>${CLEAN_BUILD}</code>
<b>Build by:</b> $USER_TAG
<b>Size:</b> <code>${FILE_SIZE_GB}</code>
<b>MD5:</b> <code>${MD5SUM}</code>${JSON_LINK_HTML}

<a href='${DOWNLOAD_LINK}'>Download from Gofile</a>"

        if [ -z "$MSG_ID" ]; then
             tg_send_message "$SUCCESS_MSG" "$TELEGRAM_CHAT_ID" "HTML"
        else
             tg_edit_message "$MSG_ID" "$SUCCESS_MSG" "$TELEGRAM_CHAT_ID" "HTML"
        fi
        
    else
        echo "❌ Gofile Upload Failed."
        
        FAIL_MSG="❌ <b>Gofile Upload Failed!</b>
<b>Device:</b> <code>${DEVICE}</code>
<b>Build Success, but Upload Failed.</b>
<b>Build by:</b> $USER_TAG
Check logs for details."

        if [ -z "$MSG_ID" ]; then
            tg_send_message "$FAIL_MSG" "$TELEGRAM_CHAT_ID" "HTML"
        else
            tg_edit_message "$MSG_ID" "$FAIL_MSG" "$TELEGRAM_CHAT_ID" "HTML"
        fi
        # Keep zip so manual intervention is possible
        exit 1
    fi
fi

#!/bin/bash

# Smart Upload Handler
# Logic: Checks file size. If > 2GB, uploads to Gofile and creates a text link.
# Requires: curl, jq
# Inherits: TELEGRAM_TOKEN, TELEGRAM_CHAT_ID from environment

source builder/tg_utils.sh

DEVICE="$1"
OUT_DIR="source/out/target/product/${DEVICE}"

# Fix: Get the MOST RECENT zip file (handling multiple files case)
ZIP_PATH=$(ls -t "$OUT_DIR"/AfterlifeOS*.zip 2>/dev/null | head -n 1)
LIMIT_BYTES=$((2 * 1024 * 1024 * 1024)) # 2GB Limit

if [ -z "$ZIP_PATH" ]; then
    echo "SmartUpload: No zip file found in $OUT_DIR. Skipping."
    exit 0
fi

FILE_SIZE=$(stat -c%s "$ZIP_PATH")
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
    echo "⚠️ File exceeds 2GB GitHub limit. Switching to Gofile upload..."
    
    tg_send_message "📦 *Artifact > 2GB Detected*
Uploading to Gofile server... This may take a while."

    DOWNLOAD_LINK=$(upload_to_gofile "$ZIP_PATH")

    if [ $? -eq 0 ]; then
        echo "✅ Gofile Upload Success: $DOWNLOAD_LINK"
        
        # Create a text file with the link
        LINK_FILE="$OUT_DIR/AfterlifeOS_Download_Link.txt"
        echo "The build artifact was too large for GitHub (>2GB)." > "$LINK_FILE"
        echo "It has been uploaded to Gofile:" >> "$LINK_FILE"
        echo "$DOWNLOAD_LINK" >> "$LINK_FILE"
        
        # Calculate additional info
        MD5SUM=$(md5sum "$ZIP_PATH" | awk '{print $1}')
        FILE_SIZE_HUMAN=$(ls -sh "$ZIP_PATH" | awk '{print $1}')

        # Send Success Message
        SUCCESS_MSG="✅ *AfterlifeOS Gofile Upload Complete!*
*Device:* \`${DEVICE}\`
*Type:* \`${BUILD_TYPE}\`
*Variant:* \`${BUILD_VARIANT:-Unknown}\`
*Build by:* \`${GITHUB_ACTOR:-Unknown}\`
*Size:* \`${FILE_SIZE_HUMAN}\`
*MD5:* \`${MD5SUM}\`

[Download from Gofile](${DOWNLOAD_LINK})"

        tg_send_message "$SUCCESS_MSG"
        
        # REMOVE the original zip so GitHub Action doesn't fail trying to upload it
        rm "$ZIP_PATH"
        echo "Original zip removed to prevent GitHub upload failure."
        
    else
        echo "❌ Gofile Upload Failed."
        tg_send_message "❌ *Gofile Upload Failed!* Please check logs."
        # Keep zip so manual intervention is possible
    fi
else
    echo "✅ File is under 2GB. Keeping file for standard GitHub Artifact upload."
fi

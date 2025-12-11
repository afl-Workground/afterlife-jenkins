#!/bin/bash

# Telegram Utils for AfterlifeOS Builder
# Requires: curl, jq

TG_API="https://api.telegram.org/bot${TELEGRAM_TOKEN}"

function tg_send_message() {
    local text="$1"
    local parse_mode="${2:-Markdown}"
    
    # Send message and capture the JSON response to get message_id
    local response=$(curl -s -X POST "${TG_API}/sendMessage" \
        -d chat_id="${TELEGRAM_CHAT_ID}" \
        -d text="${text}" \
        -d parse_mode="${parse_mode}" \
        -d disable_web_page_preview="true")
        
    # Return the message_id for future editing
    echo "$response" | jq -r '.result.message_id'
}

function tg_edit_message() {
    local msg_id="$1"
    local text="$2"
    local parse_mode="${3:-Markdown}"
    
    curl -s -X POST "${TG_API}/editMessageText" \
        -d chat_id="${TELEGRAM_CHAT_ID}" \
        -d message_id="${msg_id}" \
        -d text="${text}" \
        -d parse_mode="${parse_mode}" \
        -d disable_web_page_preview="true" > /dev/null
}

function tg_upload_log() {
    local file_path="$1"
    local caption="$2"
    
    if [ ! -f "$file_path" ]; then
        echo "Log file not found: $file_path"
        return
    fi
    
    curl -s -X POST "${TG_API}/sendDocument" \
        -F chat_id="${TELEGRAM_CHAT_ID}" \
        -F document=@"${file_path}" \
        -F caption="${caption}" \
        -F parse_mode="Markdown" > /dev/null
}

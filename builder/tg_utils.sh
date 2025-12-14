#!/bin/bash

# Telegram Utils for AfterlifeOS Builder
# Reference: xSkyyHinohara

# Check dependencies
if ! command -v curl &> /dev/null; then
    echo "❌ Error: 'curl' is not installed. Telegram notifications will fail." >&2
fi

TG_API="https://api.telegram.org/bot${TELEGRAM_TOKEN}"

function tg_send_message() {
    local text="$1"
    local chat_id="${2:-$TELEGRAM_CHAT_ID}"
    local parse_mode="${3:-Markdown}"
    
    # DEBUG: Check env vars (Masked)
    echo "DEBUG: Sending msg to ChatID: ${chat_id:0:5}*** using Token: ${TELEGRAM_TOKEN:0:5}***" >&2
    
    # Prepare Topic/Thread ID if available
    local thread_arg=""
    if [[ ! -z "$TELEGRAM_TOPIC_ID" ]]; then
        thread_arg="-d message_thread_id=${TELEGRAM_TOPIC_ID}"
    fi

    # Send message
    local response=$(curl -s -X POST "${TG_API}/sendMessage" \
        -d chat_id="${chat_id}" \
        ${thread_arg} \
        -d text="${text}" \
        -d parse_mode="${parse_mode}" \
        -d disable_web_page_preview="true")

    # Debug: Print raw response if it's not OK
    if [[ "$response" != *"\"ok\":true"* ]]; then
        echo "❌ Telegram Error: $response" >&2
    fi

    # Extract message_id (Method from reference script)
    echo "$response" | grep -o '"message_id":[0-9]*' | cut -d':' -f2
}

function tg_edit_message() {
    local msg_id="$1"
    local text="$2"
    local chat_id="${3:-$TELEGRAM_CHAT_ID}"
    local parse_mode="${4:-Markdown}"
    
    if [ -z "$msg_id" ] || [ "$msg_id" == "null" ]; then
        return
    fi
    
    curl -s -X POST "${TG_API}/editMessageText" \
        -d chat_id="${chat_id}" \
        -d message_id="${msg_id}" \
        -d text="${text}" \
        -d parse_mode="${parse_mode}" \
        -d disable_web_page_preview="true" > /dev/null
}

function tg_upload_log() {
    local file_path="$1"
    local caption="$2"
    local chat_id="${3:-$TELEGRAM_CHAT_ID}"
    
    if [ ! -f "$file_path" ]; then
        echo "Log file not found: $file_path"
        return
    fi
    
    # Prepare Topic/Thread ID if available
    local thread_arg=""
    if [[ ! -z "$TELEGRAM_TOPIC_ID" ]]; then
        thread_arg="-F message_thread_id=${TELEGRAM_TOPIC_ID}"
    fi

    curl -s --progress-bar -F document=@"${file_path}" "${TG_API}/sendDocument" \
        -F chat_id="${chat_id}" \
        ${thread_arg} \
        -F caption="${caption}" \
        -F parse_mode="Markdown" \
        -F disable_web_page_preview="true"
}

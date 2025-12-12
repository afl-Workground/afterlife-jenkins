#!/bin/bash

# Load configuration
LOCALDIR=`cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd`
. $LOCALDIR/config.sh

# Setup Repo tool if missing
if ! command -v repo &> /dev/null
then
    mkdir -p ~/bin
    curl https://storage.googleapis.com/git-repo-downloads/repo > ~/bin/repo
    chmod a+rx ~/bin/repo
    export PATH=~/bin:$PATH
fi

mkdir -p $ROOTDIR
cd $ROOTDIR

# --- SMART DIRTY BUILD LOGIC ---
LAST_DEV_FILE=".last_build_device"
if [ -f "$LAST_DEV_FILE" ]; then
    LAST_DEVICE=$(cat "$LAST_DEV_FILE")
else
    LAST_DEVICE=""
fi

echo "[*] Checking Build Context..."
echo "    -> Previous Device: '${LAST_DEVICE}'"
echo "    -> Current Device:  '${DEVICE}'"
echo "    -> Dirty Requested: '${DIRTY_BUILD}'"

# Validasi Dirty Build
if [ "$DIRTY_BUILD" = "true" ]; then
    if [ "$DEVICE" == "$LAST_DEVICE" ]; then
        echo "[*] VALIDATED: Safe to proceed with Dirty Build."
    else
        echo "[!] MISMATCH: Cannot Dirty Build '${DEVICE}' on top of '${LAST_DEVICE}' tree."
        echo "    -> Forcing CLEANUP and disabling Dirty Build."
        DIRTY_BUILD="false"
    fi
fi

# Eksekusi Cleanup jika Dirty Build OFF (atau dimatikan paksa di atas)
if [ "$DIRTY_BUILD" != "true" ]; then
    echo "[*] Preparing Clean Environment..."
    
    # 1. Bersihkan sisa device SEBELUMNYA (jika ada)
    if [ ! -z "$LAST_DEVICE" ] && [ -d "out/target/product/${LAST_DEVICE}" ]; then
        echo "    -> Removing artifacts from previous device (${LAST_DEVICE})..."
        rm -rf "out/target/product/${LAST_DEVICE}"
        
        OLD_TRACK_FILE="tracked_paths_${LAST_DEVICE}.txt"
        if [ -f "$OLD_TRACK_FILE" ]; then
            echo "    -> Removing tracked paths from previous build..."
            while IFS= read -r path; do
                [ -d "$path" ] && rm -rf "$path"
            done < $OLD_TRACK_FILE
            rm "$OLD_TRACK_FILE"
        fi
    fi

    # 2. Reset Local Manifests (Untuk device baru)
    echo "    -> Wiping local manifests..."
    rm -rf .repo/local_manifests
else
    echo "[*] DIRTY MODE: Skipping cleanup of output and manifests."
fi

echo "[*] Initializing Repo for $ROM_NAME ($ROM_VERSION)..."
repo init -u $MANIFEST_URL -b $ROM_VERSION --depth=1 --git-lfs

echo "[*] Handling Local Manifests..."
# Pastikan folder ada
mkdir -p .repo/local_manifests

# If a Local Manifest URL is provided via Jenkins, download it
if [ ! -z "$LOCAL_MANIFEST_URL" ]; then
    echo "[*] Downloading Local Manifest from: $LOCAL_MANIFEST_URL"
    curl -L -o .repo/local_manifests/jenkins_local_manifest.xml "$LOCAL_MANIFEST_URL"
    
    if [ $? -ne 0 ]; then
        echo "[!] Failed to download local manifest. Check the URL."
        exit 1
    fi

    # TRACKING LOGIC: Extract paths from the local manifest to track what we added
    # We use a unique filename per device to avoid race condition conflicts
    TRACK_FILE="tracked_paths_${DEVICE}.txt"
    echo "[*] Tracking added paths from Local Manifest into $TRACK_FILE..."
    
    # Extracts text inside path="..." from the XML
    grep -oP 'path="\K[^"]+' .repo/local_manifests/jenkins_local_manifest.xml > $TRACK_FILE
    
    echo "--- Tracked Paths ---"
    cat $TRACK_FILE
    echo "---------------------"
else
    echo "[!] ERROR: No Local Manifest URL provided in sync.sh (Should be caught by Jenkinsfile validation)."
    exit 1
fi

echo "[*] Starting Sync..."
# EXPLANATION OF FLAGS:
# --prune : CRITICAL. Deletes project files that are no longer in the manifest.
#           This removes Maintainer A's device tree when Maintainer B builds.
# --force-sync : Overwrite changes if necessary.
repo sync -c -j8 --force-sync --optimized-fetch --no-clone-bundle --no-tags --prune --retry-fetches=5
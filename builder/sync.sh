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

echo "[*] Initializing Repo for $ROM_NAME ($ROM_VERSION)..."
repo init -u $MANIFEST_URL -b $ROM_VERSION --depth=1 --git-lfs

echo "[*] Handling Local Manifests..."
# Clean up old local manifests directory entirely to be safe
rm -rf .repo/local_manifests
mkdir -p .repo/local_manifests

# If a Local Manifest URL is provided via Jenkins, download it
if [ ! -z "$LOCAL_MANIFEST_URL" ]; then
    echo "[*] Downloading Local Manifest from: $LOCAL_MANIFEST_URL"
    curl -L -o .repo/local_manifests/jenkins_local_manifest.xml "$LOCAL_MANIFEST_URL"
    
    if [ $? -ne 0 ]; then
        echo "[!] Failed to download local manifest. Check the URL."
        exit 1
    fi
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
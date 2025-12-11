#!/bin/bash

# Load configuration
LOCALDIR=`cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd`
. $LOCALDIR/config.sh

cd $ROOTDIR

echo "[*] Setting up Environment..."
. build/envsetup.sh

# CLEAN_BUILD Logic
# Jenkins passes parameters as environment variables.
if [ "$CLEAN_BUILD" = "true" ]; then
    echo "[!!!] CLEAN_BUILD selected. Wiping out/ directory..."
    # 'make clean' removes the entire output directory
    make clean
    # Alternatively: rm -rf out/
else
    echo "[*] Standard Dirty Build (Speed optimized)..."
    echo "[*] Cleaning old images but keeping objects (installclean)..."
    # 'installclean' removes the generated images (boot.img, system.img) but keeps compiled classes/binaries
    make installclean
fi

echo "[*] Running goafterlife for device ${DEVICE} with build type ${BUILD_TYPE}..."
# The 'goafterlife' command is assumed to handle both lunch and the actual compilation (mka).
goafterlife ${DEVICE} ${BUILD_TYPE}

# Check the exit status of goafterlife
if [ $? -eq 0 ]; then
    echo "BUILD SUCCESS!"
else
    echo "BUILD FAILED! goafterlife exited with an error."
    exit 1
fi

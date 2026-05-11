#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Colors for output
CLR_RST=$(tput sgr0)
CLR_RED=$CLR_RST$(tput setaf 1)
CLR_GRN=$CLR_RST$(tput setaf 2)
CLR_CYA=$CLR_RST$(tput setaf 6)
CLR_BLD=$(tput bold)
CLR_BLD_RED=$CLR_RST$CLR_BLD$(tput setaf 1)
CLR_BLD_GRN=$CLR_RST$CLR_BLD$(tput setaf 2)
CLR_BLD_BLU=$CLR_RST$CLR_BLD$(tput setaf 4)
CLR_BLD_CYA=$CLR_RST$CLR_BLD$(tput setaf 6)

export DEVICE="marble"
export BUILD_TYPE="userdebug"
export FILE_NAME_TAG="eng.nobody"

echo "=========================================="
echo "    Preparing AOSPA Build for Crave.io    "
echo "=========================================="

# 1. Clean up old local manifests to prevent duplicate errors
echo -e "${CLR_BLD_BLU}-> Cleaning old manifests...${CLR_RST}"
rm -rf .repo/local_manifests
mkdir -p .repo/local_manifests

# 2. Add the BCR manifest
echo -e "${CLR_BLD_BLU}-> Adding BCR local manifest...${CLR_RST}"
cat << 'EOF' > .repo/local_manifests/bcr.xml
<?xml version="1.0" encoding="UTF-8"?>
<manifest>
    <remote name="xiaomi-marble" fetch="https://github.com/xiaomi-sm8450-marble" />
    <project path="vendor/bcr" name="android_vendor_bcr" remote="xiaomi-marble" revision="ursa" />
</manifest>
EOF

# 3. Ensure SKIP_ROOMSERVICE is unset so Barista can work
unset SKIP_ROOMSERVICE

# 4. Initialize the environment and lunch to trigger Barista
# Barista will automatically generate baristablend.xml with all device dependencies
echo -e "${CLR_BLD_BLU}-> Triggering Barista to generate device dependencies...${CLR_RST}"
. build/envsetup.sh
lunch aospa_${DEVICE}-${BUILD_TYPE}

# 5. Force a full sync to catch BCR and all Barista-generated dependencies
echo -e "${CLR_BLD_BLU}-> Syncing dependencies (BCR and Device Trees)...${CLR_RST}"
/opt/crave/resync.sh

# 6. Setup environment again after sync
echo -e "${CLR_BLD_BLU}-> Setting up environment...${CLR_RST}"
. build/envsetup.sh
lunch aospa_${DEVICE}-${BUILD_TYPE}

AOSPA_VERSION="$(get_build_var AOSPA_VERSION)"
AOSPA_DISPLAY_VERSION="$(cat vendor/aospa/target/product/version.mk | grep 'AOSPA_MAJOR_VERSION := *' | sed 's/.*= //')"

echo -e "${CLR_BLD_GRN}Building AOSPA $AOSPA_DISPLAY_VERSION for $DEVICE${CLR_RST}"
echo -e "${CLR_GRN}Start time: $(date)${CLR_RST}"

TIME_START=$(date +%s.%N)

function checkExit () {
    EXIT_CODE=$?
    if [ $EXIT_CODE -ne 0 ]; then
        echo "${CLR_BLD_RED}Build failed!${CLR_RST}"
        echo -e ""
        exit $EXIT_CODE
    fi
}

# 7. Start the actual ROM build
echo -e "${CLR_BLD_BLU}-> Starting ROM compilation...${CLR_RST}"
m otapackage
checkExit

# 8. Finalize package
cp -f $OUT/aospa_${DEVICE}-ota-${FILE_NAME_TAG}.zip $OUT/aospa-${AOSPA_VERSION}.zip
echo -e "${CLR_BLD_GRN}Package Complete: $OUT/aospa-${AOSPA_VERSION}.zip${CLR_RST}"

TIME_END=$(date +%s.%N)
echo -e "${CLR_BLD_GRN}Total time elapsed:${CLR_RST} ${CLR_GRN}$(echo "($TIME_END - $TIME_START) / 60" | bc) minutes ($(echo "$TIME_END - $TIME_START" | bc) seconds)${CLR_RST}"

echo "=========================================="
echo "          Build Script Finished           "
echo "=========================================="
exit 0

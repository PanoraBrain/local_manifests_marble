#!/bin/bash

# Colors
CLR_RST=$(tput sgr0)
CLR_BLD=$(tput bold)
CLR_BLD_RED=$CLR_RST$CLR_BLD$(tput setaf 1)
CLR_BLD_GRN=$CLR_RST$CLR_BLD$(tput setaf 2)
CLR_BLD_BLU=$CLR_RST$CLR_BLD$(tput setaf 4)
CLR_GRN=$CLR_RST$(tput setaf 2)

# ── Config ──────────────────────────────────────────────
DEVICE="marble"
BUILD_TYPE="userdebug"
AOSPA_BRANCH="beryl"
AOSPA_MANIFEST="https://github.com/aospa-shadedark/manifest"
BCR_REMOTE="https://github.com/xiaomi-sm8450-marble"
BCR_REPO="android_vendor_bcr"
BCR_BRANCH="ursa"
# ────────────────────────────────────────────────────────

function checkExit() {
    EXIT_CODE=$?
    if [ $EXIT_CODE -ne 0 ]; then
        echo -e "${CLR_BLD_RED}Error! Build failed at the last step.${CLR_RST}"
        exit "$EXIT_CODE"
    fi
}

function getDisplayVersion() {
    local version=""
    local found=""

    if [ -f "vendor/aospa/target/product/version.mk" ]; then
        version=$(grep 'AOSPA_MAJOR_VERSION := *' vendor/aospa/target/product/version.mk \
            | sed 's/.*= //')
    elif [ -f "vendor/shadedark/target/product/version.mk" ]; then
        version=$(grep 'AOSPA_MAJOR_VERSION := *' vendor/shadedark/target/product/version.mk \
            | sed 's/.*= //')
    else
        found=$(find vendor/ -name "version.mk" -exec \
            grep -l 'AOSPA_MAJOR_VERSION' {} \; 2>/dev/null | head -1)
        if [ -n "$found" ]; then
            version=$(grep 'AOSPA_MAJOR_VERSION := *' "$found" | sed 's/.*= //')
        fi
    fi

    if [ -z "$version" ]; then
        version="unknown"
        echo -e "${CLR_BLD_RED}Warning: Could not find version.mk, display version set to 'unknown'${CLR_RST}" >&2
    fi

    echo "$version"
}

echo "=========================================="
echo "    AOSPA Shadedark Build for Crave.io    "
echo "    Device : $DEVICE                      "
echo "    Branch : $AOSPA_BRANCH                "
echo "=========================================="

# ── Step 0: SSH, HTTPS and hooks fix ────────────────────
echo -e "\n${CLR_BLD_BLU}[0/7] Configuring Git and SSH settings...${CLR_RST}"

# Trust GitHub host keys (prevents interactive yes/no hang)
mkdir -p ~/.ssh
chmod 700 ~/.ssh
ssh-keyscan -t rsa,ecdsa,ed25519 github.com >> ~/.ssh/known_hosts 2>/dev/null
chmod 600 ~/.ssh/known_hosts

# Force HTTPS instead of SSH for all GitHub URLs
git config --global url."https://github.com/".insteadOf "git@github.com:"
git config --global url."https://github.com/".insteadOf "ssh://git@github.com/"

# Fix "hooks is different" caused by switching ROMs on crave
find .repo/projects -name "hooks" -type d -exec rm -rf {} + 2>/dev/null || true
find .repo/project-objects -name "hooks" -type d -exec rm -rf {} + 2>/dev/null || true
find .repo/projects -name "hooks" -type d -exec rm -rf {} + 2>/dev/null || true
find .repo/project-objects -name "hooks" -type d -exec rm -rf {} + 2>/dev/null || true
find .repo/projects -name "objects" -type d -exec rm -rf {} + 2>/dev/null || true
find .repo/project-objects -name "objects" -type d -exec rm -rf {} + 2>/dev/null || true
echo -e "${CLR_GRN}SSH, HTTPS and hooks configured.${CLR_RST}"


echo -e "\n${CLR_BLD_BLU}[0.5/7] Cl...${CLR_RST}"
find . -mindepth 1 -maxdepth 1 \
    ! -name '.repo' \
    -exec rm -rf {} + 2>/dev/null || true
echo -e "${CLR_GRN}here we go.${CLR_RST}"

# ── Step 1: Re-init repo to aospa-shadedark ─────────────
echo -e "\n${CLR_BLD_BLU}[1/7] Initializing aospa-shadedark repo...${CLR_RST}"
repo init -u "$AOSPA_MANIFEST" -b "$AOSPA_BRANCH" --depth=1 --git-lfs
checkExit

# ── Step 2: Clean and set up local manifests ─────────────
echo -e "\n${CLR_BLD_BLU}[2/7] Setting up local manifests...${CLR_RST}"
rm -rf .repo/local_manifests
mkdir -p .repo/local_manifests

cat << EOF > .repo/local_manifests/bcr.xml
<?xml version="1.0" encoding="UTF-8"?>
<manifest>
    <remote name="xiaomi-marble" fetch="${BCR_REMOTE}" />
    <project path="vendor/bcr" name="${BCR_REPO}" remote="xiaomi-marble" revision="${BCR_BRANCH}" />
</manifest>
EOF

echo -e "${CLR_GRN}BCR manifest written.${CLR_RST}"

# ── Step 3: First sync (core source + BCR) ───────────────
echo -e "\n${CLR_BLD_BLU}[3/7] First sync - core source + BCR...${CLR_RST}"
/opt/crave/resync.sh
checkExit

# ── Step 4: Lunch to trigger Barista ─────────────────────
echo -e "\n${CLR_BLD_BLU}[4/7] Running lunch to trigger Barista...${CLR_RST}"
# shellcheck source=/dev/null
. build/envsetup.sh
lunch "aospa_${DEVICE}-${BUILD_TYPE}"
checkExit

# ── Step 5: Second sync (Barista device trees) ───────────
echo -e "\n${CLR_BLD_BLU}[5/7] Second sync - pulling Barista device trees...${CLR_RST}"
/opt/crave/resync.sh
checkExit

# ── Step 6: Re-lunch with full tree ──────────────────────
echo -e "\n${CLR_BLD_BLU}[6/7] Re-lunching with complete device tree...${CLR_RST}"
# shellcheck source=/dev/null
. build/envsetup.sh
lunch "aospa_${DEVICE}-${BUILD_TYPE}"
checkExit

AOSPA_VERSION="$(get_build_var AOSPA_VERSION)"
AOSPA_DISPLAY_VERSION="$(getDisplayVersion)"

echo -e "\n${CLR_BLD_GRN}Building AOSPA $AOSPA_DISPLAY_VERSION for $DEVICE${CLR_RST}"
echo -e "${CLR_GRN}Start time: $(date)${CLR_RST}"
TIME_START=$(date +%s.%N)

# ── Step 7: Build ─────────────────────────────────────────
echo -e "\n${CLR_BLD_BLU}[7/7] Starting compilation...${CLR_RST}"
m otapackage -j"$(nproc --all)"
checkExit

# ── Finalize output ───────────────────────────────────────
OUT_ZIP=$(find "$OUT" -maxdepth 1 -name "aospa_${DEVICE}-ota*.zip" | head -1)
if [ -z "$OUT_ZIP" ]; then
    echo -e "${CLR_BLD_RED}Output zip not found in $OUT!${CLR_RST}"
    exit 1
fi

cp -f "$OUT_ZIP" "$OUT/aospa-${AOSPA_VERSION}.zip"

TIME_END=$(date +%s.%N)
echo -e "\n${CLR_BLD_GRN}=========================================="
echo -e "Build complete!"
echo -e "Package : $OUT/aospa-${AOSPA_VERSION}.zip"
echo -e "Time    : $(echo "($TIME_END - $TIME_START) / 60" | bc) minutes"
echo -e "==========================================${CLR_RST}"
exit 0echo -e "\n${CLR_BLD_GRN}=========================================="
echo -e "Build complete!"
echo -e "Package : $OUT/aospa-${AOSPA_VERSION}.zip"
echo -e "Time    : $(echo "($TIME_END - $TIME_START) / 60" | bc) minutes"
echo -e "==========================================${CLR_RST}"
exit 0

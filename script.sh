#!/bin/bash

# Colors
CLR_RST=$(tput sgr0)
CLR_BLD=$(tput bold)
CLR_BLD_RED=$CLR_RST$CLR_BLD$(tput setaf 1)
CLR_BLD_GRN=$CLR_RST$CLR_BLD$(tput setaf 2)
CLR_BLD_BLU=$CLR_RST$CLR_BLD$(tput setaf 4)
CLR_GRN=$CLR_RST$(tput setaf 2)


# Validate required env vars (warn only, don't exit)
if [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ] || [ -z "$PIXELDRAIN_API_KEY" ]; then
    echo -e "${CLR_BLD_RED}Warning: Missing env vars (TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID, PIXELDRAIN_API_KEY). Telegram/Pixeldrain features may not work.${CLR_RST}"
fi

# ── Config ──────────────────────────────────────────────
DEVICE="marble"
BUILD_TYPE="user"
AOSPA_BRANCH="beryl"
AOSPA_MANIFEST="https://github.com/aospa-shadedark/manifest"
BCR_REMOTE="https://github.com/Chaitanyakm"
BCR_REPO="vendor_bcr"
BCR_BRANCH="main"
TELECOMM_COMMIT="dc55208d85933334bfbc420d5ece9516fe8d56fc"
TELECOMM_REMOTE="https://github.com/aospa-shadedark/android_packages_services_Telecomm"
# ────────────────────────────────────────────────────────

# ── Telegram Bot API Helpers ───────────────────────────
TG_API="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}"
STATUS_MSG_ID=""

tg_send_message() {
    local text="$1"
    local reply_markup="$2"
    local response
    local args=(
        -s
        --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}"
        --data-urlencode "text=${text}"
        --data-urlencode "parse_mode=HTML"
        --data-urlencode "disable_web_page_preview=true"
    )
    if [ -n "$reply_markup" ]; then
        args+=(--data-urlencode "reply_markup=${reply_markup}")
    fi
    response=$(curl "${args[@]}" "${TG_API}/sendMessage")
    echo "$response" | grep -o '"message_id":[0-9]*' | head -1 | grep -o '[0-9]*'
}

tg_edit_message() {
    local msg_id="$1"
    local text="$2"
    local reply_markup="$3"
    if [ -z "$msg_id" ]; then return; fi
    local args=(
        -s
        --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}"
        --data-urlencode "message_id=${msg_id}"
        --data-urlencode "text=${text}"
        --data-urlencode "parse_mode=HTML"
        --data-urlencode "disable_web_page_preview=true"
    )
    if [ -n "$reply_markup" ]; then
        args+=(--data-urlencode "reply_markup=${reply_markup}")
    fi
    curl "${args[@]}" "${TG_API}/editMessageText" -o /dev/null 2>/dev/null
}

tg_delete_message() {
    local msg_id="$1"
    if [ -z "$msg_id" ]; then return; fi
    curl -s \
        --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
        --data-urlencode "message_id=${msg_id}" \
        "${TG_API}/deleteMessage" -o /dev/null 2>/dev/null
}

# ── Pixeldrain Upload Helper ──────────────────────────
pixeldrain_upload() {
    local file_path="$1"
    local file_name
    file_name=$(basename "$file_path")
    local response
    response=$(curl -s \
        -T "$file_path" \
        -u ":${PIXELDRAIN_API_KEY}" \
        "https://pixeldrain.com/api/file/${file_name}")
    # PUT returns {"id":"abc123"}
    echo "$response" | grep -o '"id":"[^"]*"' | head -1 | sed 's/"id":"//;s/"//'
}

# ── Helpers for pretty Telegram messages ──────────────
format_size() {
    local size=$1
    if [ "$size" -ge 1073741824 ]; then
        echo "$(awk "BEGIN {printf \"%.2f\", $size/1073741824}") GB"
    elif [ "$size" -ge 1048576 ]; then
        echo "$(awk "BEGIN {printf \"%.2f\", $size/1048576}") MB"
    elif [ "$size" -ge 1024 ]; then
        echo "$(awk "BEGIN {printf \"%.2f\", $size/1024}") KB"
    else
        echo "${size} B"
    fi
}

format_duration() {
    local total_seconds=$1
    local hours=$((total_seconds / 3600))
    local minutes=$(( (total_seconds % 3600) / 60 ))
    local seconds=$((total_seconds % 60))
    if [ "$hours" -gt 0 ]; then
        printf "%dh %dm %ds" "$hours" "$minutes" "$seconds"
    elif [ "$minutes" -gt 0 ]; then
        printf "%dm %ds" "$minutes" "$seconds"
    else
        printf "%ds" "$seconds"
    fi
}

update_status() {
    local step="$1"
    local total="$2"
    local title="$3"
    local extra="$4"

    # Build progress bar
    local filled=$((step * 8 / total))
    local empty=$((8 - filled))
    local bar=""
    for ((i=0; i<filled; i++)); do bar+="▓"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done

    local elapsed=""
    if [ -n "$BUILD_START_TS" ]; then
        local now
        now=$(date +%s)
        elapsed="$(format_duration $((now - BUILD_START_TS)))"
    fi

    local text=""
    text+="<b>🔨 AOSPA Shadedark Build</b>"
    text+=$'\n'"━━━━━━━━━━━━━━━━━━━━━━"
    text+=$'\n'"<b>📱 Device:</b>  <code>${DEVICE}</code>"
    text+=$'\n'"<b>🌿 Branch:</b>  <code>${AOSPA_BRANCH}</code>"
    text+=$'\n'"<b>🏷 Type:</b>     <code>${BUILD_TYPE}</code>"
    text+=$'\n'
    text+=$'\n'"<b>📊 Progress:</b>  [${bar}]  ${step}/${total}"
    text+=$'\n'"<b>📌 Status:</b>   ${title}"
    if [ -n "$extra" ]; then
        text+=$'\n'"${extra}"
    fi
    if [ -n "$elapsed" ]; then
        text+=$'\n'"<b>⏱ Elapsed:</b>  <code>${elapsed}</code>"
    fi
    text+=$'\n'"━━━━━━━━━━━━━━━━━━━━━━"
    text+=$'\n'"🕐 <i>$(date '+%Y-%m-%d %H:%M:%S %Z')</i>"

    if [ -z "$STATUS_MSG_ID" ]; then
        STATUS_MSG_ID=$(tg_send_message "$text")
    else
        tg_edit_message "$STATUS_MSG_ID" "$text"
    fi
}

function checkExit() {
    EXIT_CODE=$?
    if [ $EXIT_CODE -ne 0 ]; then
        echo -e "${CLR_BLD_RED}Error! Build failed at the last step.${CLR_RST}"
        # Send failure notification
        local fail_text=""
        fail_text+="<b>❌ Build Failed!</b>"
        fail_text+=$'\n'"━━━━━━━━━━━━━━━━━━━━━━"
        fail_text+=$'\n'"<b>📱 Device:</b>  <code>${DEVICE}</code>"
        fail_text+=$'\n'"<b>🌿 Branch:</b>  <code>${AOSPA_BRANCH}</code>"
        fail_text+=$'\n'"<b>🚫 Exit Code:</b>  <code>${EXIT_CODE}</code>"
        fail_text+=$'\n'"━━━━━━━━━━━━━━━━━━━━━━"
        fail_text+=$'\n'"🕐 <i>$(date '+%Y-%m-%d %H:%M:%S %Z')</i>"
        tg_edit_message "$STATUS_MSG_ID" "$fail_text"
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

BUILD_START_TS=$(date +%s)

# ── Step 0: SSH, HTTPS and hooks fix ────────────────────
echo -e "\n${CLR_BLD_BLU}[0/7] Configuring Git and SSH settings...${CLR_RST}"
update_status 0 7 "⚙️ Configuring Git & SSH..."

# Trust GitHub host keys (prevents interactive yes/no hang)
mkdir -p ~/.ssh
chmod 700 ~/.ssh
ssh-keyscan -t rsa,ecdsa,ed25519 github.com >> ~/.ssh/known_hosts 2>/dev/null
chmod 600 ~/.ssh/known_hosts

# Force HTTPS instead of SSH for all GitHub URLs
git config --global url."https://github.com/".insteadOf "git@github.com:"
git config --global url."https://github.com/".insteadOf "ssh://git@github.com/"

rm -rf prebuilts/clang/host/linux-x86
rm -rf .repo/projects/prebuilts/clang/host/linux-x86.git

# ── Step 1: Re-init repo to aospa-shadedark ─────────────
echo -e "\n${CLR_BLD_BLU}[1/7] Initializing aospa-shadedark repo...${CLR_RST}"
update_status 1 7 "📦 Initializing repo..."
repo init -u "$AOSPA_MANIFEST" -b "$AOSPA_BRANCH" --depth=1 --git-lfs
checkExit

# ── Step 2: Clean and set up local manifests ─────────────
echo -e "\n${CLR_BLD_BLU}[2/7] Setting up local manifests...${CLR_RST}"
update_status 2 7 "📝 Setting up local manifests..."
rm -rf .repo/local_manifests
mkdir -p .repo/local_manifests

# BCR manifest
cat <<EOF > .repo/local_manifests/bcr.xml
<?xml version="1.0" encoding="UTF-8"?>
<manifest>
    <remote name="xiaomi-marble" fetch="${BCR_REMOTE}" />
    <project path="vendor/bcr" name="${BCR_REPO}" remote="xiaomi-marble" revision="${BCR_BRANCH}" />
</manifest>
EOF
echo -e "${CLR_GRN}BCR manifest written.${CLR_RST}"

# NOTE: shadedark-https.xml removed — HTTPS override handled by global git config

# ── Step 3: First sync (core source + BCR) ───────────────
echo -e "\n${CLR_BLD_BLU}[3/7] First sync - core source + BCR...${CLR_RST}"
update_status 3 7 "🔄 Syncing core source + BCR..."
/opt/crave/resync.sh
checkExit

# ── Apply Telecomm cherry-pick ────────────────────────────
echo -e "\n${CLR_BLD_BLU}Applying Telecomm cherry-pick...${CLR_RST}"
update_status 3 7 "🔄 Syncing core source + BCR..." "🍒 <i>Applying Telecomm cherry-pick...</i>"
cd packages/services/Telecomm
git fetch "$TELECOMM_REMOTE" "$TELECOMM_COMMIT"
git cherry-pick "$TELECOMM_COMMIT"
checkExit
cd ../../..
echo -e "${CLR_GRN}Telecomm cherry-pick applied successfully.${CLR_RST}"

# ── Step 4: Lunch to trigger Barista ─────────────────────
echo -e "\n${CLR_BLD_BLU}[4/7] Running lunch to trigger Barista...${CLR_RST}"
update_status 4 7 "🍽 Running lunch (Barista)..."
# shellcheck source=/dev/null
. build/envsetup.sh
lunch "aospa_${DEVICE}-${BUILD_TYPE}"
checkExit

# ── Step 5: Second sync (Barista device trees) ───────────
echo -e "\n${CLR_BLD_BLU}[5/7] Second sync - pulling Barista device trees...${CLR_RST}"
update_status 5 7 "🔄 Syncing Barista device trees..."
/opt/crave/resync.sh
checkExit

# ── Re-apply Telecomm cherry-pick after second sync ───────
echo -e "\n${CLR_BLD_BLU}Re-applying Telecomm cherry-pick after second sync...${CLR_RST}"
update_status 5 7 "🔄 Syncing Barista device trees..." "🍒 <i>Re-applying Telecomm cherry-pick...</i>"
cd packages/services/Telecomm
git fetch "$TELECOMM_REMOTE" "$TELECOMM_COMMIT"
git cherry-pick "$TELECOMM_COMMIT" || git cherry-pick --skip
checkExit
cd ../../..
echo -e "${CLR_GRN}Telecomm cherry-pick re-applied.${CLR_RST}"

# ── Step 6: Re-lunch with full tree ──────────────────────
echo -e "\n${CLR_BLD_BLU}[6/7] Re-lunching with complete device tree...${CLR_RST}"
update_status 6 7 "🍽 Re-lunching with full tree..."
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
update_status 7 7 "🔨 Compiling... (this takes a while)" "<b>🏗 Version:</b>  <code>${AOSPA_DISPLAY_VERSION}</code>"
m otapackage -j"$(nproc --all)"
checkExit

# ── Finalize output ───────────────────────────────────────
OUT_ZIP=$(find "$OUT" -maxdepth 1 -name "aospa_${DEVICE}-ota*.zip" | head -1)
if [ -z "$OUT_ZIP" ]; then
    echo -e "${CLR_BLD_RED}Output zip not found in $OUT!${CLR_RST}"
    local fail_text=""
    fail_text+="<b>❌ Build Error</b>"
    fail_text+=$'\n'"━━━━━━━━━━━━━━━━━━━━━━"
    fail_text+=$'\n'"Output ZIP not found in <code>$OUT</code>"
    tg_edit_message "$STATUS_MSG_ID" "$fail_text"
    exit 1
fi

FINAL_ZIP="$OUT/aospa-${AOSPA_VERSION}.zip"
cp -f "$OUT_ZIP" "$FINAL_ZIP"

TIME_END=$(date +%s.%N)
ELAPSED_SECS=$(awk "BEGIN {printf \"%d\", $TIME_END - $TIME_START}")
BUILD_DURATION=$(format_duration "$ELAPSED_SECS")
FILE_SIZE=$(stat -c%s "$FINAL_ZIP" 2>/dev/null || stat -f%z "$FINAL_ZIP" 2>/dev/null)
PRETTY_SIZE=$(format_size "$FILE_SIZE")
MD5SUM=$(md5sum "$FINAL_ZIP" | awk '{print $1}')

echo -e "\n${CLR_BLD_GRN}=========================================="
echo -e "Build complete!"
echo -e "  File: $(basename "$FINAL_ZIP")"
echo -e "  Size: $PRETTY_SIZE"
echo -e "  MD5:  $MD5SUM"
echo -e "  Time: $BUILD_DURATION"
echo -e "==========================================${CLR_RST}"

# ── Upload to Pixeldrain ─────────────────────────────────
echo -e "\n${CLR_BLD_BLU}Uploading to Pixeldrain...${CLR_RST}"
update_status 7 7 "☁️ Uploading to Pixeldrain..." "<b>📦 File:</b>  <code>$(basename "$FINAL_ZIP")</code>  |  <code>${PRETTY_SIZE}</code>"

PD_FILE_ID=$(pixeldrain_upload "$FINAL_ZIP")

if [ -z "$PD_FILE_ID" ]; then
    echo -e "${CLR_BLD_RED}Pixeldrain upload failed!${CLR_RST}"
    tg_edit_message "$STATUS_MSG_ID" "<b>❌ Pixeldrain upload failed!</b>"
    exit 1
fi

PD_DOWNLOAD_URL="https://pixeldrain.com/u/${PD_FILE_ID}"
PD_DIRECT_URL="https://pixeldrain.com/api/file/${PD_FILE_ID}?download"

echo -e "${CLR_BLD_GRN}Upload successful!${CLR_RST}"
echo -e "${CLR_GRN}  Download: $PD_DOWNLOAD_URL${CLR_RST}"

# ── Send final Telegram notification ─────────────────────
# Delete the old progress message
tg_delete_message "$STATUS_MSG_ID"

# Build inline keyboard with download links
INLINE_KEYBOARD='{"inline_keyboard":[[{"text":"⬇️ Download ROM","url":"'"${PD_DOWNLOAD_URL}"'"}],[{"text":"📥 Direct Download","url":"'"${PD_DIRECT_URL}"'"}]]}'

FINAL_TEXT=""
FINAL_TEXT+="<b>✅ Build Completed Successfully!</b>"
FINAL_TEXT+=$'\n'"━━━━━━━━━━━━━━━━━━━━━━"
FINAL_TEXT+=$'\n'
FINAL_TEXT+=$'\n'"<b>📱 Device:</b>       <code>${DEVICE}</code>"
FINAL_TEXT+=$'\n'"<b>🌿 Branch:</b>       <code>${AOSPA_BRANCH}</code>"
FINAL_TEXT+=$'\n'"<b>🏷 Build Type:</b>   <code>${BUILD_TYPE}</code>"
FINAL_TEXT+=$'\n'"<b>📋 Version:</b>      <code>${AOSPA_DISPLAY_VERSION}</code>"
FINAL_TEXT+=$'\n'
FINAL_TEXT+=$'\n'"━━━━━━━━━━━━━━━━━━━━━━"
FINAL_TEXT+=$'\n'
FINAL_TEXT+=$'\n'"<b>📦 File:</b>         <code>$(basename "$FINAL_ZIP")</code>"
FINAL_TEXT+=$'\n'"<b>📏 Size:</b>         <code>${PRETTY_SIZE}</code>"
FINAL_TEXT+=$'\n'"<b>🔒 MD5:</b>          <code>${MD5SUM}</code>"
FINAL_TEXT+=$'\n'"<b>⏱ Duration:</b>     <code>${BUILD_DURATION}</code>"
FINAL_TEXT+=$'\n'
FINAL_TEXT+=$'\n'"━━━━━━━━━━━━━━━━━━━━━━"
FINAL_TEXT+=$'\n'"🕐 <i>$(date '+%Y-%m-%d %H:%M:%S %Z')</i>"

tg_send_message "$FINAL_TEXT" "$INLINE_KEYBOARD"

echo -e "\n${CLR_BLD_GRN}Telegram notification sent with download links!${CLR_RST}"

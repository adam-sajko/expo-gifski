#!/bin/bash
set -e

#
# Rebuild expo-gifski: compile Rust FFI + build the app via Xcode/Gradle.
#
# Usage:
#   ./scripts/rebuild.sh              # Rust + iOS + Android (both)
#   ./scripts/rebuild.sh ios          # Rust + iOS only
#   ./scripts/rebuild.sh android      # Rust + Android only
#   ./scripts/rebuild.sh --clean ios  # Nuke everything, then rebuild
#   ./scripts/rebuild.sh --verbose    # Stream full build output
#

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$SCRIPT_DIR/.."
PKG_DIR="$ROOT_DIR/packages/expo-gifski"
APP_DIR="$ROOT_DIR/apps/gifski-example"

PLATFORM=""
CLEAN=false
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --clean)  CLEAN=true; shift ;;
        --verbose|-v) VERBOSE=true; shift ;;
        ios|android) PLATFORM="$1"; shift ;;
        *) echo "Unknown argument: $1"; exit 1 ;;
    esac
done

PLATFORMS=()
if [ -n "$PLATFORM" ]; then
    PLATFORMS=("$PLATFORM")
else
    PLATFORMS=("ios" "android")
fi

export VERBOSE
source "$SCRIPT_DIR/lib/step-utils.sh"

echo ""
echo "  expo-gifski rebuild (${PLATFORMS[*]})"
echo ""

# ── Clean (optional) ────────────────────────────────────────────────

if [ "$CLEAN" = true ]; then
    step_begin "Cleaning build artifacts"
    rm -rf "$PKG_DIR/build" "$PKG_DIR/ios/libs" "$PKG_DIR/ios/generated" \
           "$PKG_DIR/rust/target" \
           "$PKG_DIR/android/.cxx" "$PKG_DIR/android/build" "$PKG_DIR/android/.gradle" \
           "$PKG_DIR/android/src/main/jniLibs" "$PKG_DIR/android/src/main/java/uniffi"
    rm -rf "$APP_DIR/.expo" "$APP_DIR/node_modules/.cache"
    for p in "${PLATFORMS[@]}"; do
        if [ "$p" = "ios" ];     then rm -rf "$APP_DIR/ios"; fi
        if [ "$p" = "android" ]; then rm -rf "$APP_DIR/android"; fi
    done
    step_end

    step_begin "Installing dependencies"
    cd "$ROOT_DIR"
    yarn install
    step_end
fi

# ── Build Rust FFI ──────────────────────────────────────────────────

for p in "${PLATFORMS[@]}"; do
    step_begin "Building Rust library ($p)"
    if [ "$p" = "ios" ]; then
        "$PKG_DIR/ios/build.sh"
    elif [ "$p" = "android" ]; then
        "$PKG_DIR/android/build.sh"
    fi
    step_end
done

# ── Refresh CocoaPods (pick up generated UniFFI bindings) ──────────

for p in "${PLATFORMS[@]}"; do
    if [ "$p" = "ios" ] && [ -d "$APP_DIR/ios" ]; then
        step_begin "Refreshing CocoaPods"
        cd "$APP_DIR/ios"
        pod install
        step_end
    fi
done

# ── Build TypeScript ────────────────────────────────────────────────

step_begin "Building TypeScript"
cd "$ROOT_DIR"
yarn workspace expo-gifski build
step_end

# ── Build app ───────────────────────────────────────────────────────

for p in "${PLATFORMS[@]}"; do
    step_begin "Building app ($p)"
    cd "$ROOT_DIR"
    if [ "$p" = "ios" ]; then
        yarn ios --no-bundler
    elif [ "$p" = "android" ]; then
        yarn android --no-bundler
    fi
    step_end
done

# ── Size report ─────────────────────────────────────────────────────

YELLOW='\033[0;33m'
DIM='\033[2m'
BOLD='\033[1m'
WHITE='\033[1;37m'

format_size() {
    local bytes=$1
    if [ "$bytes" -ge 1048576 ]; then
        awk "BEGIN { printf \"%.1f MB\", $bytes / 1048576 }"
    else
        awk "BEGIN { printf \"%.0f KB\", $bytes / 1024 }"
    fi
}

file_size() {
    stat -f%z "$1" 2>/dev/null || stat -c%s "$1" 2>/dev/null || echo 0
}

# Estimate actual code size (TEXT + DATA segments) from a static library.
# The .a file on disk is much larger due to symbol tables and object metadata.
estimate_code_size() {
    size "$1" 2>/dev/null | awk 'NR>1 { text+=$1; data+=$2 } END { print int(text + data) }'
}

echo ""
echo -e "  ${BOLD}Native library sizes${NC}"
echo -e "  ${DIM}──────────────────────────────────────────────${NC}"

for p in "${PLATFORMS[@]}"; do
    if [ "$p" = "ios" ]; then
        DEVICE_LIB="$PKG_DIR/ios/libs/libexpo_gifski.a"
        SIM_LIB="$PKG_DIR/ios/libs/libexpo_gifski_sim.a"
        echo ""
        echo -e "  ${WHITE}iOS${NC}"
        if [ -f "$DEVICE_LIB" ]; then
            CODE_BYTES=$(estimate_code_size "$DEVICE_LIB")
            DISK_BYTES=$(file_size "$DEVICE_LIB")
            echo -e "    arm64 (device)         ${YELLOW}~$(format_size "$CODE_BYTES")${NC}  ${DIM}estimated app size (.a on disk: $(format_size "$DISK_BYTES"))${NC}"
        fi
        if [ -f "$SIM_LIB" ]; then
            DISK_BYTES=$(file_size "$SIM_LIB")
            echo -e "    arm64+x86 (simulator)  $(format_size "$DISK_BYTES")  ${DIM}dev only${NC}"
        fi
    elif [ "$p" = "android" ]; then
        echo ""
        echo -e "  ${WHITE}Android${NC}"
        JNILIBS_DIR="$PKG_DIR/android/src/main/jniLibs"
        for abi in arm64-v8a armeabi-v7a x86_64 x86; do
            LIB="$JNILIBS_DIR/$abi/libexpo_gifski.so"
            if [ -f "$LIB" ]; then
                SIZE_BYTES=$(file_size "$LIB")
                note=""
                if [ "$abi" = "arm64-v8a" ]; then
                    note="  ${DIM}most devices${NC}"
                fi
                printf "    %-20s ${YELLOW}%s${NC}%b\n" "$abi" "$(format_size "$SIZE_BYTES")" "$note"
            fi
        done
    fi
done

echo ""
echo -e "  ${DIM}iOS estimate = code segments before linker dead-code stripping.${NC}"
echo -e "  ${DIM}Android .so = exact shipped size. For exact iOS size, build a${NC}"
echo -e "  ${DIM}release archive with: xcodebuild -configuration Release${NC}"
echo ""
echo -e "  ${GREEN}Build complete.${NC} Run ${CYAN}yarn start${NC} to launch Metro."
echo ""

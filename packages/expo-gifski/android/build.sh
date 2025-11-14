#!/bin/bash
set -euo pipefail

# Build Rust library for Android
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUST_DIR="$SCRIPT_DIR/../rust"
ANDROID_DIR="$SCRIPT_DIR"
cd "$RUST_DIR"

# Install Android targets if not already installed
echo "📦 Installing Rust Android targets..."
rustup target add aarch64-linux-android || true
rustup target add armv7-linux-androideabi || true
rustup target add i686-linux-android || true
rustup target add x86_64-linux-android || true

# Set up Android NDK
if [ -z "${ANDROID_NDK_HOME:-}" ]; then
    if [ -d "$HOME/Library/Android/sdk/ndk" ]; then
        LATEST_NDK=$(ls -1 "$HOME/Library/Android/sdk/ndk" | sort -V | tail -1)
        export ANDROID_NDK_HOME="$HOME/Library/Android/sdk/ndk/$LATEST_NDK"
    elif [ -d "$HOME/Library/Android/sdk/ndk-bundle" ]; then
        export ANDROID_NDK_HOME="$HOME/Library/Android/sdk/ndk-bundle"
    elif [ -n "${ANDROID_HOME:-}" ] && [ -d "$ANDROID_HOME/ndk" ]; then
        LATEST_NDK=$(ls -1 "$ANDROID_HOME/ndk" | sort -V | tail -1)
        export ANDROID_NDK_HOME="$ANDROID_HOME/ndk/$LATEST_NDK"
    elif [ -n "${ANDROID_HOME:-}" ] && [ -d "$ANDROID_HOME/ndk-bundle" ]; then
        export ANDROID_NDK_HOME="$ANDROID_HOME/ndk-bundle"
    fi
fi

if [ -z "${ANDROID_NDK_HOME:-}" ] || [ ! -d "$ANDROID_NDK_HOME" ]; then
    echo "❌ Error: ANDROID_NDK_HOME not set or invalid."
    echo "   Please set ANDROID_NDK_HOME to your Android NDK path."
    echo "   Example: export ANDROID_NDK_HOME=\$HOME/Library/Android/sdk/ndk/25.1.8937393"
    exit 1
fi

echo "✅ Using NDK at: $ANDROID_NDK_HOME"

# Detect host architecture for NDK toolchain
HOST_OS="$(uname -s)"
ARCH=$(uname -m)
if [ "$HOST_OS" = "Linux" ]; then
    TOOLCHAIN="linux-x86_64"
elif [ "$ARCH" = "arm64" ] || [ "$ARCH" = "aarch64" ]; then
    TOOLCHAIN="darwin-arm64"
else
    TOOLCHAIN="darwin-x86_64"
fi

NDK_TOOLCHAIN_BIN="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/$TOOLCHAIN/bin"
if [ ! -d "$NDK_TOOLCHAIN_BIN" ]; then
    NDK_TOOLCHAIN_BIN="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/darwin-x86_64/bin"
fi

# Create a LOCAL .cargo/config.toml for Android linker configuration
mkdir -p "$RUST_DIR/.cargo"
cat > "$RUST_DIR/.cargo/config.toml" << EOF
[target.aarch64-linux-android]
linker = "$NDK_TOOLCHAIN_BIN/aarch64-linux-android21-clang"

[target.armv7-linux-androideabi]
linker = "$NDK_TOOLCHAIN_BIN/armv7a-linux-androideabi21-clang"

[target.i686-linux-android]
linker = "$NDK_TOOLCHAIN_BIN/i686-linux-android21-clang"

[target.x86_64-linux-android]
linker = "$NDK_TOOLCHAIN_BIN/x86_64-linux-android21-clang"
EOF

# Build for all Android architectures
echo "🔨 Building Rust library for Android architectures..."
cargo build --release --target aarch64-linux-android
cargo build --release --target armv7-linux-androideabi
cargo build --release --target i686-linux-android
cargo build --release --target x86_64-linux-android

# Copy .so files into jniLibs directory structure
JNILIBS_DIR="$ANDROID_DIR/src/main/jniLibs"
mkdir -p "$JNILIBS_DIR/arm64-v8a"
mkdir -p "$JNILIBS_DIR/armeabi-v7a"
mkdir -p "$JNILIBS_DIR/x86"
mkdir -p "$JNILIBS_DIR/x86_64"

cp target/aarch64-linux-android/release/libexpo_gifski.so   "$JNILIBS_DIR/arm64-v8a/"
cp target/armv7-linux-androideabi/release/libexpo_gifski.so  "$JNILIBS_DIR/armeabi-v7a/"
cp target/i686-linux-android/release/libexpo_gifski.so       "$JNILIBS_DIR/x86/"
cp target/x86_64-linux-android/release/libexpo_gifski.so     "$JNILIBS_DIR/x86_64/"

echo "✅ Android .so libraries copied to jniLibs/"

# Generate UniFFI Kotlin bindings
echo "🔨 Building host dylib for UniFFI binding generation..."
cargo build

# Detect the correct host library extension (.dylib on macOS, .so on Linux)
if [ "$HOST_OS" = "Darwin" ]; then
    HOST_LIB_EXT="dylib"
else
    HOST_LIB_EXT="so"
fi

GENERATED_DIR="$ANDROID_DIR/src/main/java/uniffi/expo_gifski"
mkdir -p "$GENERATED_DIR"

echo "📦 Generating Kotlin bindings with uniffi-bindgen..."
cargo run --bin uniffi-bindgen generate \
  --library "target/debug/libexpo_gifski.$HOST_LIB_EXT" \
  --language kotlin \
  --out-dir "$ANDROID_DIR/src/main/java/" \
  --no-format

echo "✅ Kotlin bindings generated"
echo ""
echo "✅ Android build complete!"
echo "   .so libraries: android/src/main/jniLibs/*/"
echo "   Kotlin bindings: android/src/main/java/uniffi/expo_gifski/"

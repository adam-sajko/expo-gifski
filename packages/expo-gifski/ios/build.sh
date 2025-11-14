#!/bin/bash
set -euo pipefail

# Build Rust library for iOS
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUST_DIR="$SCRIPT_DIR/../rust"
IOS_DIR="$SCRIPT_DIR"
cd "$RUST_DIR"

# Install targets if not already installed
rustup target add aarch64-apple-ios
rustup target add x86_64-apple-ios
rustup target add aarch64-apple-ios-sim

echo "🔨 Building Rust for iOS targets..."

# Build for all iOS architectures
cargo build --release --target aarch64-apple-ios
cargo build --release --target x86_64-apple-ios
cargo build --release --target aarch64-apple-ios-sim

mkdir -p "$IOS_DIR/libs"

# Device library: only ARM64 (aarch64-apple-ios)
cp target/aarch64-apple-ios/release/libexpo_gifski.a "$IOS_DIR/libs/libexpo_gifski.a"

# Simulator library: combine ARM64 sim (Apple Silicon Macs) + x86_64 (Intel Macs)
lipo -create \
  target/aarch64-apple-ios-sim/release/libexpo_gifski.a \
  target/x86_64-apple-ios/release/libexpo_gifski.a \
  -output "$IOS_DIR/libs/libexpo_gifski_sim.a"

echo "✅ iOS static libraries built"
echo "   Device lib:    ios/libs/libexpo_gifski.a (arm64)"
echo "   Simulator lib: ios/libs/libexpo_gifski_sim.a (arm64 + x86_64)"

# Generate UniFFI Swift bindings
echo "🔨 Building host dylib for UniFFI binding generation..."
cargo build

GENERATED_DIR="$IOS_DIR/generated"
mkdir -p "$GENERATED_DIR"

echo "📦 Generating Swift bindings with uniffi-bindgen..."
cargo run --bin uniffi-bindgen generate \
  --library target/debug/libexpo_gifski.dylib \
  --language swift \
  --out-dir "$GENERATED_DIR"

echo "✅ Swift bindings generated in ios/generated/"
echo "   $(ls "$GENERATED_DIR")"
echo ""
echo "✅ iOS build complete!"

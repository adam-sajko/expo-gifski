#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$SCRIPT_DIR/.."

FILES=(
  ios/libs/libexpo_gifski.a
  ios/libs/libexpo_gifski_sim.a
  ios/generated/expo_gifski.swift
  ios/generated/expo_gifskiFFI.h
  ios/generated/expo_gifskiFFI.modulemap
  android/src/main/jniLibs/arm64-v8a/libexpo_gifski.so
  android/src/main/jniLibs/armeabi-v7a/libexpo_gifski.so
  android/src/main/jniLibs/x86/libexpo_gifski.so
  android/src/main/jniLibs/x86_64/libexpo_gifski.so
  android/src/main/java/uniffi/expo_gifski/expo_gifski.kt
)

MISSING=()
for f in "${FILES[@]}"; do
  [ -f "$ROOT/$f" ] || MISSING+=("$f")
done

if [ ${#MISSING[@]} -gt 0 ]; then
  echo ""
  echo "ERROR: Cannot pack expo-gifski — prebuilt Rust binaries are missing."
  echo "Run the build scripts first:"
  echo "  ./ios/build.sh"
  echo "  ./android/build.sh"
  echo ""
  echo "Missing files:"
  for f in "${MISSING[@]}"; do
    echo "  - $f"
  done
  echo ""
  exit 1
fi

echo "All prebuilt binaries present."

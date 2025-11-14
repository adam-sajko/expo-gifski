#!/bin/bash
#
# Open the latest generated GIF from the iOS Simulator in Preview.
#
# Usage:
#   ./scripts/open-gif.sh            # open latest GIF in Preview
#   ./scripts/open-gif.sh --folder   # open the cache folder in Finder
#   ./scripts/open-gif.sh --list     # list all generated GIFs
#

BUNDLE_ID="com.adamsajko.gifskiexample"

DATA_DIR=$(xcrun simctl get_app_container booted "$BUNDLE_ID" data 2>/dev/null)
if [ -z "$DATA_DIR" ]; then
    echo "Error: Could not find app container. Is the simulator running with the app installed?"
    echo "  Bundle ID: $BUNDLE_ID"
    exit 1
fi

CACHE_DIR="$DATA_DIR/Library/Caches"

if [ "$1" = "--folder" ]; then
    echo "Opening: $CACHE_DIR"
    open "$CACHE_DIR"
    exit 0
fi

if [ "$1" = "--list" ]; then
    echo "GIFs in $CACHE_DIR:"
    echo ""
    find "$CACHE_DIR" -name "*.gif" -exec ls -lhS {} + 2>/dev/null
    exit 0
fi

LATEST_GIF=$(find "$CACHE_DIR" -name "*.gif" -print0 2>/dev/null | xargs -0 ls -t 2>/dev/null | head -1)

if [ -z "$LATEST_GIF" ]; then
    echo "No GIF files found in app cache."
    echo "  Looked in: $CACHE_DIR"
    exit 1
fi

SIZE=$(ls -lh "$LATEST_GIF" | awk '{print $5}')
echo "Opening: $(basename "$LATEST_GIF") ($SIZE)"
open -a Preview "$LATEST_GIF"

#!/bin/bash
set -e

#
# Bump the expo-gifski version in package.json and Cargo.toml in lockstep.
#
# Usage:
#   ./scripts/bump-version.sh patch        # 1.0.1 → 1.0.2
#   ./scripts/bump-version.sh minor        # 1.0.1 → 1.1.0
#   ./scripts/bump-version.sh major        # 1.0.1 → 2.0.0
#   ./scripts/bump-version.sh 2.3.0        # set an explicit version
#

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PKG_JSON="$SCRIPT_DIR/../packages/expo-gifski/package.json"
CARGO_TOML="$SCRIPT_DIR/../packages/expo-gifski/rust/Cargo.toml"

if [ -z "$1" ]; then
    echo "Usage: $0 <patch|minor|major|X.Y.Z>"
    exit 1
fi

current=$(node -p "require('$PKG_JSON').version")

bump_semver() {
    local cur=$1 kind=$2
    IFS='.' read -r major minor patch <<< "$cur"
    case "$kind" in
        patch) echo "$major.$minor.$((patch + 1))" ;;
        minor) echo "$major.$((minor + 1)).0" ;;
        major) echo "$((major + 1)).0.0" ;;
    esac
}

case "$1" in
    patch|minor|major) next=$(bump_semver "$current" "$1") ;;
    *)
        if [[ ! "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "Error: '$1' is not a valid semver version or bump keyword (patch|minor|major)."
            exit 1
        fi
        next="$1"
        ;;
esac

if [ "$current" = "$next" ]; then
    echo "Version is already $current — nothing to do."
    exit 0
fi

node -e "
const fs = require('fs');
const pkg = JSON.parse(fs.readFileSync('$PKG_JSON', 'utf8'));
pkg.version = '$next';
fs.writeFileSync('$PKG_JSON', JSON.stringify(pkg, null, 2) + '\n');
"

sed -i '' "s/^version = \"$current\"/version = \"$next\"/" "$CARGO_TOML"

echo "Bumped expo-gifski: $current → $next"
echo "  ✓ packages/expo-gifski/package.json"
echo "  ✓ packages/expo-gifski/rust/Cargo.toml"

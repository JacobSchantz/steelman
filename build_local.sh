#!/bin/bash
set -o pipefail

# Build + install Steelman on a connected iPhone (Release).
# Resolved by `testables build ios` via convention: <repo>/build_local.sh
#
# Usage:  ./build_local.sh [--install-only] [device-id]
echo "Building and running Steelman in release mode on iPhone..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Shared iOS engine: device detection, install with locked-device retry, launch.
COMMON_SH="${TESTABLES_COMMON_SH:-$HOME/testables/scripts/build_ios_common.sh}"
if [ ! -f "$COMMON_SH" ]; then
  echo "ERROR: build_ios_common.sh not found at $COMMON_SH" >&2
  echo "       (clone ~/testables, or export TESTABLES_COMMON_SH=<path>)" >&2
  exit 1
fi
# shellcheck source=/dev/null
source "$COMMON_SH"

DERIVED_DATA="$SCRIPT_DIR/build/DerivedData"
BUILD_LOG="$SCRIPT_DIR/build/build.log"
APP_PATH="$DERIVED_DATA/Build/Products/Release-iphoneos/Steelman.app"
SCHEME="${TESTABLES_SCHEME:-Steelman}"
CONFIG_FILE="$HOME/.testables/config.json"

INSTALL_ONLY=0
POS_ARGS=()
for a in "$@"; do
  case "$a" in
    --install-only) INSTALL_ONLY=1 ;;
    *) POS_ARGS+=("$a") ;;
  esac
done

if [ "$INSTALL_ONLY" = "1" ]; then
  if [ ! -d "$APP_PATH" ]; then
    echo "Error: --install-only but no app at $APP_PATH (run a full build first)" >&2
    exit 1
  fi
  echo "Skipping build, reusing existing app: $APP_PATH"
  DEVICE_ID="${TESTABLES_DEVICE_ID:-${POS_ARGS[0]:-}}"
  [ -n "$DEVICE_ID" ] || DEVICE_ID="$(tb_detect_device)" || exit "$TB_EXIT_NO_DEVICE"
  tb_install_and_launch "$DEVICE_ID" "$APP_PATH"
  exit $?
fi

# Sync to remote so the device runs what's on origin/main (Testables overlay
# verifies the running build by commit hash/count via GitInfo).
echo "Syncing to remote (origin/main)..."
git fetch origin
git reset --hard origin/main
git clean -fd

DEVICE_ID="${TESTABLES_DEVICE_ID:-${POS_ARGS[0]:-}}"
[ -n "$DEVICE_ID" ] || DEVICE_ID="$(tb_detect_device)" || exit "$TB_EXIT_NO_DEVICE"
echo "Target device: $DEVICE_ID"

DEVELOPMENT_TEAM="${TESTABLES_DEVELOPMENT_TEAM:-}"
if [ -z "$DEVELOPMENT_TEAM" ] && [ -f "$CONFIG_FILE" ]; then
  DEVELOPMENT_TEAM="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('development_team',''))" "$CONFIG_FILE" 2>/dev/null)"
fi
DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-563V2QK49N}"
echo "Signing team: $DEVELOPMENT_TEAM"

echo "Cleaning previous builds..."
rm -rf "$SCRIPT_DIR/build"
rm -rf "$SCRIPT_DIR/DerivedData"
mkdir -p "$SCRIPT_DIR/build"

echo "Regenerating Xcode project..."
rm -rf Steelman.xcodeproj
xcodegen generate
rm -f Steelman.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved

# --- Refresh TestablesKit to the latest tip of main -----------------------
# TestablesKit is pinned to `branch: main` in project.yml, but removing
# Package.resolved is NOT enough: SwiftPM resolves `main` against the global
# mirror cache (~/Library/Caches/org.swift.swiftpm/repositories), which can be
# stale. Wipe the testables mirror so the resolve re-clones it fresh, then
# verify the pin matches remote main.
TESTABLES_URL="https://github.com/JacobSchantz/testables"
echo "Refreshing TestablesKit to latest main..."
rm -rf ~/Library/Caches/org.swift.swiftpm/repositories/testables-* 2>/dev/null || true

LATEST_MAIN=$(git ls-remote "$TESTABLES_URL" refs/heads/main | awk '{print $1}')
echo "TestablesKit remote main: ${LATEST_MAIN:-unknown}"

echo "Resolving Swift package dependencies..."
xcodebuild -project "$SCRIPT_DIR/Steelman.xcodeproj" \
  -scheme "$SCHEME" \
  -derivedDataPath "$DERIVED_DATA" \
  -resolvePackageDependencies 2>&1 | tail -3

RESOLVED_FILE="$SCRIPT_DIR/Steelman.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
RESOLVED_MAIN=$(grep -A6 '"identity" : "testables"' "$RESOLVED_FILE" 2>/dev/null \
  | grep '"revision"' | head -1 | sed -E 's/.*"revision" : "([^"]+)".*/\1/')
echo "TestablesKit resolved to:  ${RESOLVED_MAIN:-unknown}"
if [ -n "$LATEST_MAIN" ] && [ "$LATEST_MAIN" != "$RESOLVED_MAIN" ]; then
  echo "⚠️  TestablesKit did not resolve to the latest main (got ${RESOLVED_MAIN:-none})." >&2
fi

echo "Building Steelman for iOS (clean build)... (log: $BUILD_LOG)"
xcodebuild -project "$SCRIPT_DIR/Steelman.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -derivedDataPath "$DERIVED_DATA" \
  -allowProvisioningUpdates \
  CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  IPHONEOS_DEPLOYMENT_TARGET=17.0 \
  clean build 2>&1 | tee "$BUILD_LOG" | tail -5
BUILD_RESULT=${PIPESTATUS[0]}

echo "=== Last 10 lines of build log ==="
tail -10 "$BUILD_LOG"

if [ "$BUILD_RESULT" -ne 0 ]; then
  echo "Build failed! (exit code: $BUILD_RESULT, log: $BUILD_LOG)"
  exit 1
fi

if [ ! -d "$APP_PATH" ]; then
  echo "Error: App not found at $APP_PATH"
  exit 1
fi

tb_install_and_launch "$DEVICE_ID" "$APP_PATH"; RC=$?
[ "$RC" -eq 0 ] && echo "✅ Steelman launched on iPhone!"
exit "$RC"

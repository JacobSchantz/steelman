#!/bin/bash
set -e

# ─────────────────────────────────────────────────────────────────────────────
# drop_to_phone_android.sh — TEMPLATE (copied into a project by `testables setup
# <project>`). Build a release APK and get it onto an Android phone the way every
# testables-instrumented app does: adb-over-WiFi for an attached phone, or an OTA
# publish to Vercel Blob that the in-app updater self-installs over any network.
#
# All the app-agnostic plumbing — adb connection/pairing/install/launch, the
# Vercel Blob publish — lives in scripts/build_android_common.sh under ~/testables
# (shared by atg, buyahabit, keepMovin, …). THIS script only declares the few
# project-specific things in the CONFIG block below, then delegates.
#
# See ~/testables/docs/build-and-drop.md for the full picture (incl. the Vercel
# deploy gotcha that bites the buyahabit.com/<app> pretty URL).
#
# Usage:
#   ./drop_to_phone_android.sh [flavor] [--drop|--serve|--launch|--no-build|--setup|--pair …]
#     --drop    OTA: build signed APK → publish to Vercel Blob → phone self-updates
#     --serve   build → serve over WiFi for a link/QR install (no adb)
#     --setup   one-time USB→WiFi bootstrap (cable-free after)
#     --pair <ip:port> [code]   Android 11+ wireless pairing
#     (default) adb-over-WiFi: build + install + launch on the saved phone
# ─────────────────────────────────────────────────────────────────────────────

# ===== PER-PROJECT CONFIG — edit these for your app ==========================
# Sub-directory of the Flutter app within the repo ("." if the repo root IS it;
# "client_app" for a monorepo like atg).
APP_SUBDIR="."
# Default build flavor (empty string if the app has no flavors).
DEFAULT_FLAVOR="prod"
# flavor → applicationId. Used for the clean-reinstall + launch on the adb path.
package_for_flavor() {
  case "$1" in
    dev)  echo "com.example.app.dev" ;;
    prod) echo "com.example.app" ;;
    *)    echo "com.example.app" ;;
  esac
}
# OTA publish target (the --drop path). BLOB_DIR is the folder in the Vercel Blob
# store; PUBLIC_BASE is the pretty front door that 302-redirects to it (set up in
# the buyahabit site's vercel.json, mirroring /atg). Empty file_prefix → the APK
# is just <flavor>.apk. The in-app Updater must poll "$PUBLIC_BASE/manifest-<flavor>.json".
BLOB_DIR="example"
PUBLIC_BASE="https://buyahabit.com/example"
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$SCRIPT_DIR/$APP_SUBDIR"

# --- Locate the shared Android engine (override with TESTABLES_ANDROID_COMMON_SH).
TB_ANDROID_COMMON_SH="${TESTABLES_ANDROID_COMMON_SH:-$HOME/testables/scripts/build_android_common.sh}"
if [ ! -f "$TB_ANDROID_COMMON_SH" ]; then
  echo "ERROR: build_android_common.sh not found at $TB_ANDROID_COMMON_SH" >&2
  echo "       (clone ~/testables, or export TESTABLES_ANDROID_COMMON_SH=<path>)" >&2
  exit 1
fi
# shellcheck source=/dev/null
source "$TB_ANDROID_COMMON_SH"

FLAVOR="$DEFAULT_FLAVOR"
LAUNCH=0; BUILD=1; CONNECT=""; PAIR_ENDPOINT=""; PAIR_CODE=""; DO_SETUP=0; SERVE=0; DROP=0
while [ $# -gt 0 ]; do
  case "$1" in
    --launch)   LAUNCH=1 ;;
    --no-build) BUILD=0 ;;
    --setup)    DO_SETUP=1 ;;
    --serve)    SERVE=1 ;;
    --drop)     DROP=1 ;;
    --connect)  CONNECT="$2"; shift ;;
    --pair)     PAIR_ENDPOINT="$2"; shift
                case "${2:-}" in -*|"") ;; *) PAIR_CODE="$2"; shift ;; esac ;;
    -*)         echo "Unknown flag: $1" >&2; exit 2 ;;
    *)          FLAVOR="$1" ;;   # a bare word is the flavor
  esac
  shift
done
PACKAGE="$(package_for_flavor "$FLAVOR")"

# --- Build the APK (unless --no-build); prints the APK path on stdout ----------
build_and_locate_apk() {
  cd "$APP_DIR"
  local flavor_arg=(); [ -n "$FLAVOR" ] && flavor_arg=(--flavor "$FLAVOR")
  if [ "$BUILD" -eq 1 ]; then
    # versionCode = git commit count so the OTA manifest only moves forward.
    local COUNT; COUNT="$(git -C "$SCRIPT_DIR" rev-list --count HEAD)"
    echo "Building release APK (flavor '${FLAVOR:-none}', versionCode $COUNT)…" >&2
    if ! flutter build apk --release "${flavor_arg[@]}" --build-number="$COUNT" >&2; then
      # NEVER fall back to a stale APK after a failed build.
      echo "❌ flutter build failed — not falling back to a stale APK." >&2
      return 1
    fi
  fi
  local apk="build/app/outputs/flutter-apk/app${FLAVOR:+-$FLAVOR}-release.apk"
  [ -f "$apk" ] || apk="$(ls -t build/app/outputs/flutter-apk/*.apk 2>/dev/null | head -1)"
  [ -n "$apk" ] && [ -f "$apk" ] || { echo "❌ No APK under $APP_DIR/build/app/outputs/flutter-apk/" >&2; return 1; }
  printf '%s\n' "$PWD/$apk"
}

# --- Connection-management subcommands -----------------------------------------
if [ -n "$PAIR_ENDPOINT" ]; then
  tb_android_pair "$PAIR_ENDPOINT" "$PAIR_CODE"
  echo "✅ Paired. Connect to the main port:  ./drop_to_phone_android.sh --connect <ip>:<connect-port> $FLAVOR"
  exit 0
fi

# --- --serve : zero-ceremony WiFi drop (no adb) --------------------------------
if [ "$SERVE" -eq 1 ]; then
  APK="$(build_and_locate_apk)" || exit 1
  tb_android_serve "$APK" "${BLOB_DIR}${FLAVOR:+-$FLAVOR}.apk"
  exit 0
fi

# --- --drop : OTA publish to Vercel Blob (any network, no adb) ------------------
if [ "$DROP" -eq 1 ]; then
  COUNT="$(git -C "$SCRIPT_DIR" rev-list --count HEAD)"
  HASH="$(git -C "$SCRIPT_DIR" rev-parse --short HEAD)"
  NOTES="$(git -C "$SCRIPT_DIR" log -1 --pretty=%s | tr -d '"\\')"
  VNAME="1.0.$COUNT-$HASH"
  BUILD_NUMBER="$COUNT"
  APK="$(build_and_locate_apk)" || exit 1
  # Empty file_prefix → <flavor>.apk (e.g. example/prod.apk + example/manifest-prod.json).
  MANIFEST_URL="$(tb_android_publish_blob "$APK" "$BLOB_DIR" "" "$FLAVOR" "$COUNT" "$VNAME" "$NOTES" "$PUBLIC_BASE")" || exit 1
  echo "✅ Dropped $VNAME (versionCode $COUNT). The app self-updates on next launch."
  echo "   install  → $PUBLIC_BASE/$FLAVOR.apk"
  echo "   manifest → $MANIFEST_URL"
  exit 0
fi

# --- adb path : resolve the device, build, install -----------------------------
if [ "$DO_SETUP" -eq 1 ]; then
  SERIAL="$(tb_android_setup_from_usb)" || exit 1
  echo "✅ Wireless adb ready ($SERIAL). You can unplug USB now."
elif [ -n "$CONNECT" ]; then
  SERIAL="$(tb_android_connect "$CONNECT")" || { echo "ERROR: couldn't connect to $CONNECT" >&2; exit 3; }
else
  SERIAL="$(tb_android_detect_device)" || exit $?
fi
echo "Target device: $SERIAL"
APK="$(build_and_locate_apk)" || exit 1
tb_android_install_and_launch "$SERIAL" "$APK" "$PACKAGE" "$LAUNCH"

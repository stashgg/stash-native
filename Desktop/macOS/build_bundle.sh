#!/bin/bash
# Builds StashNativeDesktop.bundle (universal arm64 + x86_64) from the macOS host and the shared
# contract with plain clang, no Xcode project needed. Output: Desktop/macOS/build/StashNativeDesktop.bundle
# (override with OUT_DIR). Signs with Developer ID when STASH_SIGN_IDENTITY is set.
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
DESKTOP_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"
OUT_DIR="${OUT_DIR:-$SCRIPT_DIR/build}"
OUT="$OUT_DIR/StashNativeDesktop.bundle"
mkdir -p "$OUT_DIR"

SOURCES=(
    "$SCRIPT_DIR"/Sources/StashNativeDesktop/*.mm
    "$DESKTOP_DIR"/shared/*.cpp
)

clang++ -x objective-c++ -std=c++17 -fobjc-arc -O2 \
    -arch arm64 -arch x86_64 -mmacosx-version-min=11.0 \
    -fvisibility=hidden -DSTASH_NATIVE_DESKTOP_BUILDING -DNDEBUG \
    -Wall -Wextra -Werror \
    -I "$DESKTOP_DIR/include" -I "$DESKTOP_DIR/shared" -I "$SCRIPT_DIR/Sources/StashNativeDesktop/include" \
    -framework Cocoa -framework WebKit -framework QuartzCore \
    -bundle -o "$OUT" \
    "${SOURCES[@]}"

# Every ABI export must be present and visible.
EXPECTED=(
    StashNativeDesktop_SetEventCallback StashNativeDesktop_SetHostWindow
    StashNativeDesktop_OpenCard StashNativeDesktop_OpenModal StashNativeDesktop_OpenBrowser
    StashNativeDesktop_Dismiss StashNativeDesktop_ResetPresentationState
    StashNativeDesktop_IsCurrentlyPresented StashNativeDesktop_IsPurchaseProcessing
    StashNativeDesktop_Prewarm StashNativeDesktop_SetInspectableWebViewsEnabled
    StashNativeDesktop_GetVersion StashNativeDesktop_Shutdown
)
EXPORTS=$(nm -gU "$OUT" | awk '{print $3}')
for symbol in "${EXPECTED[@]}"; do
    if ! grep -qx "_$symbol" <<< "$EXPORTS"; then
        echo "ERROR: $symbol is not exported from $OUT" >&2
        exit 1
    fi
done

if [ -n "${STASH_SIGN_IDENTITY:-}" ]; then
    codesign --force --timestamp --options runtime --sign "$STASH_SIGN_IDENTITY" "$OUT"
    codesign --verify --verbose=2 "$OUT"
fi

echo "Built $OUT"
lipo -info "$OUT"

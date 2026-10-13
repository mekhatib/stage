#!/bin/bash
# Builds Stage.app from Sources/App as a universal (Apple Silicon + Intel) app.
# Usage: ./build.sh [output-folder]   (default: ~/Applications)
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
APP="${1:-${HOME}/Applications}/Stage.app"
ARCHS="${ARCHS:-arm64 x86_64}"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

# The macOS 27 SDK turns SwiftUI's @State into a macro whose plugin ships only with Xcode,
# so plain Command Line Tools builds use the macOS 26 SDK when it's installed.
SDK="${SDK:-}"
if [[ -z "$SDK" && -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk ]]; then
  SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
slices=()
for arch in $ARCHS; do
  swiftc ${SDK:+-sdk "$SDK"} -O -swift-version 5 -parse-as-library -target "$arch-apple-macos26.0" \
    "$HERE"/Sources/App/*.swift -o "$WORK/Stage-$arch"
  slices+=("$WORK/Stage-$arch")
done

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$HERE/Sources/App/Info.plist" "$APP/Contents/Info.plist"
cp "$HERE/Resources/Stage.icns" "$APP/Contents/Resources/Stage.icns"
printf 'APPL????' >"$APP/Contents/PkgInfo"
lipo -create "${slices[@]}" -output "$APP/Contents/MacOS/Stage"
codesign --force --sign - "$APP"
"$LSREGISTER" -f "$APP" 2>/dev/null || true
echo "Built $APP ($(lipo -archs "$APP/Contents/MacOS/Stage"))"

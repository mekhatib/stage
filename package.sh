#!/bin/bash
# Builds Stage.app and zips it into dist/ for sharing (for example as a GitHub release asset).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$HERE/Sources/App/Info.plist")"
DIST="$HERE/dist"

rm -rf "$DIST"
mkdir -p "$DIST"
"$HERE/build.sh" "$DIST"
ditto -c -k --keepParent "$DIST/Stage.app" "$DIST/Stage-$VERSION.zip"
rm -rf "$DIST/Stage.app"
echo "Packaged $DIST/Stage-$VERSION.zip"

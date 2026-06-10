#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/Build/Scope.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

cd "$ROOT_DIR"
if [[ ! -f "$ROOT_DIR/Support/Scope.icns" ]]; then
  swift "$ROOT_DIR/scripts/make-icon.swift"
  iconutil -c icns "$ROOT_DIR/Support/Scope.iconset" -o "$ROOT_DIR/Support/Scope.icns"
fi

swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$ROOT_DIR/.build/release/Scope" "$MACOS_DIR/Scope"
cp "$ROOT_DIR/Support/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$ROOT_DIR/Support/Scope.icns" "$RESOURCES_DIR/Scope.icns"
chmod +x "$MACOS_DIR/Scope"

echo "Built $APP_DIR"

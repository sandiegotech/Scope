#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/Build/Disko.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

cd "$ROOT_DIR"
if [[ ! -f "$ROOT_DIR/Support/Disko.icns" ]]; then
  swift "$ROOT_DIR/scripts/make-icon.swift"
  iconutil -c icns "$ROOT_DIR/Support/Disko.iconset" -o "$ROOT_DIR/Support/Disko.icns"
fi

swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$ROOT_DIR/.build/release/Disko" "$MACOS_DIR/Disko"
cp "$ROOT_DIR/Support/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$ROOT_DIR/Support/Disko.icns" "$RESOURCES_DIR/Disko.icns"
chmod +x "$MACOS_DIR/Disko"

echo "Built $APP_DIR"

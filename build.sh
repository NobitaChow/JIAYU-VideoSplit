#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
app="dist/视频快拆 1.0.1.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" .build
swiftc -target arm64-apple-macosx14.0 -module-cache-path .build Sources/main.swift -o "$app/Contents/MacOS/VideoSplit" -framework Cocoa
cp Assets/Info.plist "$app/Contents/Info.plist"
cp Assets/AppIcon.icns "$app/Contents/Resources/"
cp Assets/Logo.png "$app/Contents/Resources/Brand.png"
cp -R ThirdParty "$app/Contents/Resources/Licenses"
python3 scripts/bundle_engine.py
codesign --force --deep --sign - "$app"
codesign --verify --deep --strict "$app"

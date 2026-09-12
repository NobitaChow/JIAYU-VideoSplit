#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p dist/dmg
 ditto "dist/视频快拆 1.0.1.app" "dist/dmg/视频快拆 1.0.1.app"
[ -L dist/dmg/Applications ] || ln -s /Applications dist/dmg/Applications
hdiutil create -volname "视频快拆 1.0.1" -srcfolder dist/dmg -ov -format UDZO dist/JIAYU-VideoSplit-1.0.1-AppleSilicon.dmg
hdiutil verify dist/JIAYU-VideoSplit-1.0.1-AppleSilicon.dmg

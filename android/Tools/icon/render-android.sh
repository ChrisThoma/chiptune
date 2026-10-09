#!/bin/bash
# Regenerates the Android launcher icon from the iOS AppIcon, so both
# platforms share one source image (Sources/Resources/Assets.xcassets/
# AppIcon.appiconset/icon-1024.png). Needs python3 with Pillow and numpy.
#
# Outputs (see render-android.py):
#   android/app/src/main/res/mipmap-*/ic_launcher_foreground.png (adaptive foreground)
#   android/app/src/main/res/mipmap-*/ic_launcher{,_round}.png   (legacy)
#   android/app/src/main/res/drawable/ic_launcher_monochrome.xml (themed icon)
#   docs/play-store/icon-512.png
#
# The background layer is drawable/ic_launcher_background.xml (#0D0D17) and
# mipmap-anydpi/ic_launcher*.xml wire the layers together; neither is touched.

set -euo pipefail

TOOL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TOOL_DIR/../../.." && pwd)"
SRC="$REPO_ROOT/Sources/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
RES_DIR="$REPO_ROOT/android/app/src/main/res"

python3 "$TOOL_DIR/render-android.py" "$SRC" "$RES_DIR" "$REPO_ROOT/docs/play-store/icon-512.png"

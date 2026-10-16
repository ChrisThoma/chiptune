#!/bin/bash
# Capture the Play Store screenshots from a booted emulator.
#
#   android/Tools/play/shoot.sh <serial> phone|tablet [WxH]
#
# Seeds the same songs the iOS shoot uses (AppStore/make_song.py) into a
# freshly cleared debug install, then opens each screen through the debug-only
# ScreenshotMode extras. Output goes to the fastlane supply layout:
# phoneScreenshots/ or tenInchScreenshots/ under
# android/fastlane/metadata/android/en-US/images/.
#
# WxH overrides the display size for the run (`wm size`) so the shots meet
# Play's aspect rules: a phone's long side at most twice the short, a tablet
# 16:9 for the large-screen listing. Defaults: phone 1080x2160, tablet
# 2560x1440. The override is reset at the end.
set -euo pipefail
SERIAL=$1 KIND=$2
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../../.." && pwd)
ADB=${ADB:-$HOME/Library/Android/sdk/platform-tools/adb}
PKG=dev.individuation.chiptune
APK=$REPO/android/app/build/outputs/apk/debug/app-debug.apk
IMG=$REPO/android/fastlane/metadata/android/en-US/images
a() { "$ADB" -s "$SERIAL" "$@"; }

case $KIND in
  phone)  SIZE=${3:-1080x2160} OUT=$IMG/phoneScreenshots ;;
  tablet) SIZE=${3:-2560x1440} OUT=$IMG/tenInchScreenshots ;;
  *) echo "kind is phone or tablet" >&2; exit 2 ;;
esac
rm -rf "$OUT"; mkdir -p "$OUT"

a install -r "$APK" >/dev/null
a shell pm clear $PKG >/dev/null
a shell wm size "$SIZE"
trap 'a shell wm size reset; a shell am broadcast -a com.android.systemui.demo -e command exit >/dev/null' EXIT
if [ "$KIND" = tablet ]; then
  a shell settings put system accelerometer_rotation 0
  a shell settings put system user_rotation 0
fi

# A clean status bar: fixed time, full battery and signal, no notifications.
a shell settings put global sysui_demo_allowed 1
demo() { a shell am broadcast -a com.android.systemui.demo -e command "$@" >/dev/null; }
# Resizing the display can restart SystemUI, which drops demo mode, so it is
# re-entered before every shot rather than once.
clean_bar() {
  demo enter
  demo clock -e hhmm 0941
  demo battery -e level 100 -e plugged false
  demo network -e wifi show -e level 4
  demo network -e mobile hide
  demo notifications -e visible false
}
sleep 8

# Seed before the first launch, so the app never writes its "First Loop"
# starter and opens the newest seeded song.
SEED=$(mktemp -d)
python3 "$REPO/AppStore/make_song.py" "$SEED" >/dev/null
a shell run-as $PKG mkdir -p files/Songs
for f in "$SEED"/*.json; do
  b=$(basename "$f")
  a push "$f" /data/local/tmp/"$b" >/dev/null
  a shell "run-as $PKG cp /data/local/tmp/$b files/Songs/$b && rm /data/local/tmp/$b"
done
rm -rf "$SEED"

shot() {  # shot <name> <settle-seconds> [extra key]
  local name=$1 settle=$2 key=${3:-}
  a shell am force-stop $PKG
  if [ -n "$key" ]; then
    a shell am start -n $PKG/.ui.MainActivity --es "$key" YES >/dev/null
  else
    a shell am start -n $PKG/.ui.MainActivity >/dev/null
  fi
  # A cold start shows the animated splash for several seconds on an
  # emulator; a short sleep photographs the splash instead of the app.
  sleep "$settle"
  clean_bar
  sleep 1
  a exec-out screencap -p > "$OUT/$name.png"
  # Play wants 24-bit PNGs; screencap writes RGBA.
  python3 -c 'import sys; from PIL import Image; Image.open(sys.argv[1]).convert("RGB").save(sys.argv[1])' "$OUT/$name.png"
  echo "  $name $(sips -g pixelWidth -g pixelHeight "$OUT/$name.png" | awk '/pixel/{printf "%s ", $2}')"
}

echo "$KIND ($SIZE) -> $OUT"
shot 1-grid 12
shot 2-playing 12 shotPlaying
if [ "$KIND" = tablet ]; then
  shot 3-arrangement 15 shotArrangement
  shot 4-pattern 15 shotPatternB
else
  shot 3-editor 15 shotEditor
  shot 4-arrangement 15 shotArrangement
fi
shot 5-export 15 shotExport
shot 6-library 15 shotLibrary
a shell am force-stop $PKG

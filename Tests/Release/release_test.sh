#!/bin/bash
#
# Tests for scripts/release.sh — the version and artifact plumbing only.
#
# Nothing here runs xcodebuild or touches the network. release.sh is written so
# that sourcing it defines the functions without executing a command, which is
# what lets these run in a second instead of twenty minutes.
#
# The bug these exist to prevent: the version lived in project.yml but the
# artifact to upload was named by a hand-typed path in a markdown runbook.
# Each build landed in a new directory, the runbook kept pointing at the first
# one, and `build/export/Chiptune.ipa` quietly rotted into build 2 while
# project.yml said build 4. Uploading it put an old binary on TestFlight.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../../scripts/release.sh
source "$ROOT/scripts/release.sh"

pass=0; fail=0
ok ()   { pass=$((pass+1)); printf '  ok   %s\n' "$1"; }
bad ()  { fail=$((fail+1)); printf '  FAIL %s\n     %s\n' "$1" "$2"; }

assert_eq () {  # assert_eq <name> <expected> <actual>
    if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected '$2', got '$3'"; fi
}

assert_ok () {  # assert_ok <name> <command...>
    local name="$1"; shift
    if out=$("$@" 2>&1); then ok "$name"; else bad "$name" "expected success, failed with: $out"; fi
}

assert_fails () {  # assert_fails <name> <expected substring> <command...>
    local name="$1" want="$2"; shift 2
    if out=$("$@" 2>&1); then
        bad "$name" "expected failure, but it succeeded"
    elif [[ "$out" != *"$want"* ]]; then
        bad "$name" "failed for the wrong reason: $out"
    else
        ok "$name"
    fi
}

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# A project.yml with versions that are nothing like the real ones, so a helper
# that hardcodes 1.0/4 instead of reading the file cannot pass.
fixture_project () {  # fixture_project <marketing> <build> -> path
    local path="$work/project-$1-$2.yml"
    cat > "$path" <<YML
name: Chiptune
targets:
  Chiptune:
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: dev.individuation.chiptune
        MARKETING_VERSION: "$1"
        CURRENT_PROJECT_VERSION: "$2"
        TARGETED_DEVICE_FAMILY: "1,2"
YML
    printf '%s' "$path"
}

# A real .ipa is a zip with Payload/Chiptune.app/Info.plist inside. Building one
# by hand keeps these tests off the gitignored build directory, whose contents
# are exactly the stale artifacts under test.
fixture_ipa () {  # fixture_ipa <marketing> <build> <device families...> -> path
    local short="$1" bundle="$2"; shift 2
    local dir="$work/ipa-$short-$bundle-$*" app
    app="$dir/Payload/Chiptune.app"
    mkdir -p "$app"
    local families="" f
    for f in "$@"; do families+="<integer>$f</integer>"; done
    cat > "$app/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>dev.individuation.chiptune</string>
  <key>CFBundleShortVersionString</key><string>$short</string>
  <key>CFBundleVersion</key><string>$bundle</string>
  <key>UIDeviceFamily</key><array>$families</array>
</dict></plist>
PLIST
    ( cd "$dir" && zip -qr Chiptune.ipa Payload )
    printf '%s' "$dir/Chiptune.ipa"
}

echo "release.sh: the version comes from project.yml"

assert_eq "reads MARKETING_VERSION"      "2.5" "$(marketing_version "$(fixture_project 2.5 17)")"
assert_eq "reads CURRENT_PROJECT_VERSION" "17" "$(build_number     "$(fixture_project 2.5 17)")"
assert_eq "reads the real project.yml"  "1.0" "$(marketing_version "$ROOT/project.yml")"
assert_eq "reads the real build number"   "4" "$(build_number      "$ROOT/project.yml")"

echo
echo "release.sh: every artifact path is derived, never fixed"

# The whole point. There is no such thing as "the export directory" — each
# version and build gets its own, so an old one can never be mistaken for new.
assert_eq "archive path carries the version" \
    "$ROOT/build/Chiptune-2.5-17.xcarchive" "$(archive_path "$(fixture_project 2.5 17)")"
assert_eq "export dir carries the version" \
    "$ROOT/build/export-2.5-17" "$(export_dir "$(fixture_project 2.5 17)")"
assert_eq "ipa path carries the version" \
    "$ROOT/build/export-2.5-17/Chiptune.ipa" "$(ipa_path "$(fixture_project 2.5 17)")"

echo
echo "release.sh: an ipa is verified against project.yml before it can be uploaded"

matching="$(fixture_ipa 1.0 4 1 2)"
assert_ok "accepts the ipa the project asked for" \
    verify_ipa "$matching" "$ROOT/project.yml"

# The regression. build/export/Chiptune.ipa was 1.0 (2) while project.yml said
# 1.0 (4), and every doc pointed at it. This is the assertion that would have
# caught the build that went to TestFlight.
stale="$(fixture_ipa 1.0 2 1 2)"
assert_fails "rejects a stale build number" "build 2" \
    verify_ipa "$stale" "$ROOT/project.yml"

# The other half of the same mess: build 3 went up as 1.1 when nothing had
# shipped, and is stranded in a 1.1 train forever.
wrong_train="$(fixture_ipa 1.1 3 1 2)"
assert_fails "rejects the wrong marketing version" "1.1" \
    verify_ipa "$wrong_train" "$ROOT/project.yml"

# Builds 1 and 2 were iPhone-only. Device family decides which screenshot sets
# App Store Connect demands, so an iPhone-only binary is the wrong artifact
# even when its numbers happen to line up.
phone_only="$(fixture_ipa 1.0 4 1)"
assert_fails "rejects an iphone-only build when the project says 1,2" "device family" \
    verify_ipa "$phone_only" "$ROOT/project.yml"

# A missing file is one problem and should read as one problem. `die` reports
# and returns non-zero, but a caller has to return on it — inside `$(...)` on
# the left of `||`, set -e is suppressed, so a bare `check || die` falls
# through and every later step re-reports the same missing file.
missing_out=$(verify_ipa "$work/not-here.ipa" "$ROOT/project.yml" 2>&1)
assert_eq "a missing ipa reports exactly one error" "1" "$(printf '%s\n' "$missing_out" | grep -c .)"
assert_fails "a missing ipa says so" "no such ipa" \
    verify_ipa "$work/not-here.ipa" "$ROOT/project.yml"

# Likewise something that is not an ipa at all.
printf 'not a zip' > "$work/bogus.ipa"
assert_fails "a file that isn't an ipa says so" "is it an ipa" \
    verify_ipa "$work/bogus.ipa" "$ROOT/project.yml"

echo
echo "release.sh: a build number cannot be uploaded twice"

ledger="$work/uploaded.txt"
printf '1.0 (2)\n1.1 (3)\n' > "$ledger"

assert_fails "refuses a build already recorded as uploaded" "already uploaded" \
    assert_not_yet_uploaded 1.0 2 "$ledger"
assert_ok "allows a build number that is new" \
    assert_not_yet_uploaded 1.0 4 "$ledger"

record_upload 1.0 4 "$ledger"
assert_fails "refuses it once recorded" "already uploaded" \
    assert_not_yet_uploaded 1.0 4 "$ledger"

echo
echo "release.sh: bumping raises the build number and nothing else"

bumpable="$(fixture_project 2.5 17)"
assert_eq "bump returns the new number"   "18"  "$(bump_build "$bumpable")"
assert_eq "bump wrote it to project.yml"  "18"  "$(build_number "$bumpable")"
assert_eq "bump left the marketing version alone" "2.5" "$(marketing_version "$bumpable")"
assert_eq "bump again"                    "19"  "$(bump_build "$bumpable")"

# A build number that isn't a whole number can't be raised by one, and
# guessing would be worse than stopping.
odd="$(fixture_project 2.5 "1.0b")"
assert_fails "refuses to bump a non-numeric build" "whole number" bump_build "$odd"

echo
echo "docs: nothing names a fixed ipa path any more"

# The doc rot itself is the defect, so it gets a test. A path with no version
# in it will be wrong the moment the version changes.
#
# The ban is on *executable* references — anything inside a shell fence, or a
# script, or passed to a flag. Prose is allowed to name the old path, because
# explaining which mistake this all guards against is the reason the guard
# survives someone tidying it up later.
executable_refs () {
    cd "$ROOT" || return 1
    # Scripts and config: any mention at all is a live path.
    grep -rn "build/export/Chiptune.ipa" \
        --include="*.sh" --include="*.py" --include="*.yml" . 2>/dev/null \
        | grep -v "^./build/" | grep -v "^./Tests/Release/"
    # Markdown: only inside ```fences```.
    while IFS= read -r doc; do
        awk -v doc="$doc" '
            /^[[:space:]]*```/ { fenced = !fenced; next }
            fenced && /build\/export\/Chiptune\.ipa/ { print doc ":" NR ":" $0 }
        ' "$doc"
    done < <(find . -name "*.md" -not -path "./build/*" -not -path "./Tests/Release/*")
}

if hits=$(executable_refs) && [ -n "$hits" ]; then
    bad "no runnable step points at an unversioned export path" "still referenced:
$hits"
else
    ok "no runnable step points at an unversioned export path"
fi

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]

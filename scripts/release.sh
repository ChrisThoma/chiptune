#!/bin/bash
#
# The one way to build, check and upload a release.
#
# Why this exists instead of a list of commands in a runbook: the version
# numbers live in project.yml, but the artifact you upload used to be named by
# a path typed into a markdown file. Every build wrote to a new directory
# (`build/export-1.0-4/`) while the runbook went on naming the first one
# (`build/export/`), so the documented path silently aged into an old binary —
# 1.0 (2) long after project.yml said 1.0 (4). Uploading it put a stale build
# on TestFlight. Twice.
#
# So: no path here is ever typed. Every one is derived from project.yml, and
# nothing reaches App Store Connect without the numbers inside the .ipa being
# checked against the numbers in project.yml first.
#
#   ./scripts/release.sh version   what project.yml says ships
#   ./scripts/release.sh bump      raise the build number by one
#   ./scripts/release.sh archive   xcodegen + xcodebuild archive
#   ./scripts/release.sh export    signed .ipa from that archive
#   ./scripts/release.sh verify    check the .ipa against project.yml
#   ./scripts/release.sh upload    verify, then altool, then record it
#   ./scripts/release.sh ship      all of the above in order
#
# Sourcing this file defines the functions without running anything, which is
# what Tests/Release/release_test.sh does.

# Strict mode only when run, not when sourced — a sourced `set -e` would take
# the test harness down with it on the first expected failure.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then set -euo pipefail; fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_YML="$ROOT/project.yml"
# Where uploads are remembered. Under AppStore/, which is excluded from git, so
# this is a record of what this machine has sent — enough to stop the same
# build going up twice, which is the mistake that actually happens.
LEDGER="$ROOT/AppStore/uploaded-builds.txt"

# Reports and fails. It cannot return on the caller's behalf, so every call
# site pairs it with an explicit `return 1` — see the note in
# Tests/Release/release_test.sh about why a bare `check || die` keeps going.
die () { printf 'release: %s\n' "$*" >&2; return 1; }

# --- project.yml is the single source of truth ------------------------------

# Read one build setting out of the Chiptune target. Deliberately a plain
# grep rather than a YAML parser: the value has to be readable with no tools
# installed, on a clean clone, before xcodegen has ever run.
setting () {  # setting <key> [project.yml]
    local key="$1" yml="${2:-$PROJECT_YML}" value
    value=$(grep -m1 "^[[:space:]]*${key}:" "$yml" 2>/dev/null | sed -e "s/^[^:]*:[[:space:]]*//" -e 's/^"//' -e 's/"$//' -e 's/[[:space:]]*$//')
    [ -n "$value" ] || { die "no $key in $yml"; return 1; }
    printf '%s' "$value"
}

marketing_version () { setting MARKETING_VERSION        "${1:-$PROJECT_YML}"; }
build_number ()      { setting CURRENT_PROJECT_VERSION  "${1:-$PROJECT_YML}"; }
device_family ()     { setting TARGETED_DEVICE_FAMILY   "${1:-$PROJECT_YML}"; }

# --- every path carries the version it holds --------------------------------
#
# The fix for the whole class of bug. There is no "the archive" or "the export
# directory": a path names exactly one version and build, so an old artifact
# can never be picked up in place of a new one, and a missing new one is a
# missing file rather than a stale success.

archive_path () { printf '%s/build/Chiptune-%s-%s.xcarchive' "$ROOT" "$(marketing_version "${1:-$PROJECT_YML}")" "$(build_number "${1:-$PROJECT_YML}")"; }
export_dir ()   { printf '%s/build/export-%s-%s'             "$ROOT" "$(marketing_version "${1:-$PROJECT_YML}")" "$(build_number "${1:-$PROJECT_YML}")"; }
ipa_path ()     { printf '%s/Chiptune.ipa' "$(export_dir "${1:-$PROJECT_YML}")"; }

# --- checking an .ipa against what was asked for ----------------------------

# An .ipa is a zip; the numbers that count are the ones baked into the bundle,
# not the ones in the filename or the directory it sits in.
ipa_plist () {  # ipa_plist <ipa> -> path to an extracted copy
    local ipa="$1" out
    [ -f "$ipa" ] || { die "no such ipa: $ipa"; return 1; }
    out=$(mktemp -t chiptune-ipa-plist) || return 1
    if ! unzip -p "$ipa" 'Payload/*.app/Info.plist' > "$out" 2>/dev/null || [ ! -s "$out" ]; then
        rm -f "$out"
        die "$ipa has no app Info.plist — is it an ipa?"; return 1
    fi
    printf '%s' "$out"
}

verify_ipa () {  # verify_ipa [ipa] [project.yml]
    local yml="${2:-$PROJECT_YML}"
    local ipa="${1:-$(ipa_path "$yml")}"
    local plist want_version want_build want_family got_version got_build got_family status=0

    want_version=$(marketing_version "$yml") || return 1
    want_build=$(build_number "$yml")        || return 1
    want_family=$(device_family "$yml")      || return 1
    # Last, so the temp plist it creates can't leak past an early return above.
    plist=$(ipa_plist "$ipa") || return 1

    got_version=$(plutil -extract CFBundleShortVersionString raw -o - "$plist" 2>/dev/null || printf '?')
    got_build=$(plutil   -extract CFBundleVersion            raw -o - "$plist" 2>/dev/null || printf '?')
    # json gives `[1,2]`; strip the brackets and spaces to compare against the
    # `"1,2"` spelling project.yml uses.
    got_family=$(plutil -extract UIDeviceFamily json -o - "$plist" 2>/dev/null | sed 's/[][ ]//g' || printf '?')
    rm -f "$plist"

    # Marketing version first, so a build from the wrong train is reported as
    # the wrong train rather than as an off-by-one build number.
    if [ "$got_version" != "$want_version" ]; then
        die "$ipa carries version $got_version, but project.yml ships $want_version"; status=1
    elif [ "$got_build" != "$want_build" ]; then
        die "$ipa carries build $got_build, but project.yml ships build $want_build — this is an old export, rebuild it"; status=1
    fi

    # Builds 1 and 2 went up iPhone-only. Device family decides which
    # screenshot sets App Store Connect demands, so this is part of being the
    # right artifact, not a detail of it.
    if [ "$got_family" != "$want_family" ]; then
        die "$ipa has device family [$got_family], but project.yml ships \"$want_family\""; status=1
    fi

    [ "$status" -eq 0 ] || return 1
    printf 'release: %s is %s (%s), device family %s — matches project.yml\n' "$ipa" "$got_version" "$got_build" "$got_family"
}

# --- a build number is used once --------------------------------------------
#
# App Store Connect rejects a duplicate build number, and an upload can never
# be withdrawn, so the cheap check belongs before the upload rather than in
# the error it comes back with.

assert_not_yet_uploaded () {  # assert_not_yet_uploaded <version> <build> [ledger]
    local ledger="${3:-$LEDGER}"
    [ -f "$ledger" ] || return 0
    if grep -qFx "$1 ($2)" "$ledger"; then
        die "$1 ($2) was already uploaded — run './scripts/release.sh bump' first"
    fi
}

record_upload () {  # record_upload <version> <build> [ledger]
    local ledger="${3:-$LEDGER}"
    mkdir -p "$(dirname "$ledger")"
    printf '%s (%s)\n' "$1" "$2" >> "$ledger"
}

# Raise the build number, in project.yml and nowhere else. The marketing
# version is left alone on purpose: it moves only when a released version
# exists to move on from, which is how build 3 ended up stranded in a 1.1
# train that had nothing in it.
bump_build () {  # bump_build [project.yml]
    local yml="${1:-$PROJECT_YML}" now next
    now=$(build_number "$yml") || return 1
    case "$now" in (*[!0-9]*|'') die "build number '$now' is not a whole number"; return 1;; esac
    next=$((now + 1))
    /usr/bin/sed -i '' -E "s/^([[:space:]]*CURRENT_PROJECT_VERSION:[[:space:]]*).*/\1\"$next\"/" "$yml"
    printf '%s' "$next"
}

# --- the commands -----------------------------------------------------------

cmd_version () {
    printf '%s (%s), device family %s\n' "$(marketing_version)" "$(build_number)" "$(device_family)"
}

cmd_bump () {
    local was; was=$(build_number)
    printf 'release: build %s -> %s in project.yml\n' "$was" "$(bump_build)"
}

cmd_archive () {
    local archive; archive=$(archive_path)
    [ -n "${CHIPTUNE_TEAM_ID:-}" ] || { die "set CHIPTUNE_TEAM_ID before archiving, or the project generates with no signing team"; return 1; }
    ( cd "$ROOT" && xcodegen generate )
    rm -rf "$archive"
    ( cd "$ROOT" && xcodebuild archive \
        -project Chiptune.xcodeproj -scheme Chiptune \
        -configuration Release -destination 'generic/platform=iOS' \
        -archivePath "$archive" )
    printf 'release: archived %s\n' "$archive"
}

cmd_export () {
    local archive dir
    archive=$(archive_path); dir=$(export_dir)
    [ -d "$archive" ] || { die "no archive for this version — run './scripts/release.sh archive' first"; return 1; }
    rm -rf "$dir"
    ( cd "$ROOT" && xcodebuild -exportArchive \
        -archivePath "$archive" \
        -exportOptionsPlist "$ROOT/AppStore/ExportOptions.plist" \
        -exportPath "$dir" )
    printf 'release: exported %s\n' "$(ipa_path)"
}

# Organizer's Distribute is the wrong path on this Mac: the archive signs
# under the free personal team, which isn't enrolled, so it refuses to go on.
# The export step re-signs under the enrolled team and altool takes it from
# there.
cmd_upload () {
    local version build ipa
    version=$(marketing_version); build=$(build_number); ipa=$(ipa_path)
    assert_not_yet_uploaded "$version" "$build"
    verify_ipa "$ipa"
    : "${ASC_KEY_ID:?set ASC_KEY_ID (App Store Connect API key id)}"
    : "${ASC_ISSUER_ID:?set ASC_ISSUER_ID (App Store Connect issuer id)}"
    xcrun altool --upload-app --type ios --file "$ipa" \
        --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
    record_upload "$version" "$build"
    printf 'release: uploaded %s (%s) and recorded it in %s\n' "$version" "$build" "$LEDGER"
}

cmd_ship () {
    assert_not_yet_uploaded "$(marketing_version)" "$(build_number)"
    cmd_archive; cmd_export; cmd_upload
}

main () {
    case "${1:-}" in
        version)  cmd_version ;;
        bump)     cmd_bump ;;
        archive)  cmd_archive ;;
        export)   cmd_export ;;
        verify)   verify_ipa "${2:-}" ;;
        upload)   cmd_upload ;;
        ship)     cmd_ship ;;
        ipa-path) ipa_path; echo ;;
        *) sed -n '3,26p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 1 ;;
    esac
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then main "$@"; fi

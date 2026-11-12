#!/bin/bash
# Release check: confirms Scripts/build-app.sh still matches the Xcode build.
#
# Builds the app both ways, compares the Swift flags and the bundles, then runs three
# end-to-end checks on the script build. Needs Xcode. Quits any running AudioPeek
# while it runs and reopens /Applications/AudioPeek.app afterwards if it was running.
#
#   Scripts/check-builds.sh         asks before starting
#   Scripts/check-builds.sh --yes   starts without asking

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$ROOT"
CHECK="$ROOT/build/check"
XCODE_APP="$CHECK/dd/Build/Products/Release/AudioPeek.app"
SCRIPT_APP="$ROOT/build/AudioPeek.app"
RELEASE_APP="/Applications/AudioPeek.app"
CLT_DIR="/Library/Developer/CommandLineTools"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
IGNORED_XCODE_FLAGS="-enable-experimental-feature DebugDescriptionMacro"

build_process_ids() {
    ps -axww -o pid=,comm= | while read -r pid executable; do
        case "$executable" in
            "$ROOT/build/"*/Contents/MacOS/AudioPeek) printf '%s\n' "$pid" ;;
        esac
    done
}

stop_build_apps() {
    local pid attempt pids
    pids="$(build_process_ids)" || return 1
    for pid in $pids; do kill "$pid" 2>/dev/null || true; done
    for ((attempt = 0; attempt < 50; attempt++)); do
        pids="$(build_process_ids)" || return 1
        [ -n "$pids" ] || return 0
        # Give the app four seconds to quit, then stop any surviving build copies.
        if [ "$attempt" -eq 40 ]; then
            for pid in $pids; do kill -KILL "$pid" 2>/dev/null || true; done
        fi
        sleep 0.1
    done
    echo "Could not stop the build copies of AudioPeek; leaving the installed app closed." >&2
    return 1
}

# Quits any AudioPeek started from this repo's build folder, unregisters those copies so
# Open With and Spotlight keep pointing at Applications, and reopens the release copy.
cleanup() {
    local stopped=0
    stop_build_apps && stopped=1
    "$LSREGISTER" -u "$SCRIPT_APP" > /dev/null 2>&1
    "$LSREGISTER" -u "$XCODE_APP" > /dev/null 2>&1
    if [ "$stopped" = "1" ] && [ "$RELEASE_WAS_RUNNING" = "1" ] && [ -d "$RELEASE_APP" ]; then
        open "$RELEASE_APP"
    fi
}

record() {
    STEP_NAMES+=("$1")
    STEP_RESULTS+=("$2")
    echo "[$2] $1"
}

# Prints a binary's recorded minimum macOS or SDK (field is minos or sdk).
build_version() {
    xcrun otool -l "$1" 2> /dev/null | awk -v field="$2" '/LC_BUILD_VERSION/{f=1} f&&$1==field{print $2;exit}'
}

signing_settings() {
    local app="$1" prefix="$2" details flags
    codesign --verify --deep --strict "$app" || return 1
    details="$(codesign --display --verbose=4 "$app" 2>&1)" || return 1
    flags="$(printf '%s\n' "$details" | sed -n 's/^CodeDirectory .* flags=\([^ ]*\) .*/\1/p')"
    [ -n "$flags" ] || return 1
    {
        printf 'flags=%s\n' "$flags"
        printf '%s\n' "$details" | sed -n '/^Identifier=/p; /^Signature=/p; /^Authority=/p; /^TeamIdentifier=/p'
    } > "$prefix-signing.txt" || return 1
    codesign --display --entitlements - --xml "$app" > "$prefix-entitlements.plist" || return 1
    # No entitlements and an empty dictionary grant the same capabilities.
    if [ ! -s "$prefix-entitlements.plist" ]; then
        plutil -create xml1 "$prefix-entitlements.plist" || return 1
    fi
    plutil -convert xml1 "$prefix-entitlements.plist"
}

compare_signing() {
    local signing_status entitlements_status
    signing_settings "$1" "$CHECK/xcode" || return 1
    signing_settings "$2" "$CHECK/script" || return 1
    diff -u "$CHECK/xcode-signing.txt" "$CHECK/script-signing.txt" > "$CHECK/signing.diff"
    signing_status=$?
    diff -u "$CHECK/xcode-entitlements.plist" "$CHECK/script-entitlements.plist" > "$CHECK/entitlements.diff"
    entitlements_status=$?
    [ "$signing_status" -eq 0 ] && [ "$entitlements_status" -eq 0 ]
}

# Lists every file and link under Contents/Frameworks with its hash, so two builds that
# embed the same Sparkle, stripped and signed the same way, give the same list.
frameworks_manifest() {
    local dir="$1/Contents/Frameworks" file
    [ -d "$dir" ] || return 1
    (
        cd "$dir" || exit 1
        find . \( -type f -o -type l \) | LC_ALL=C sort | while IFS= read -r file; do
            if [ -L "$file" ]; then
                printf '%s -> %s\n' "$file" "$(readlink "$file")"
            else
                printf '%s %s\n' "$file" "$(shasum -a 256 "$file" | awk '{print $1}')" || exit 1
            fi
        done
    )
}

compare_frameworks() {
    frameworks_manifest "$1" > "$CHECK/xcode-frameworks.txt" || return 1
    frameworks_manifest "$2" > "$CHECK/script-frameworks.txt" || return 1
    [ -s "$CHECK/xcode-frameworks.txt" ] || return 1
    diff -u "$CHECK/xcode-frameworks.txt" "$CHECK/script-frameworks.txt" > "$CHECK/frameworks.diff"
}

# Allow verify-build-checks.sh to exercise these helpers without launching the app.
if [ "${BASH_SOURCE[0]}" != "$0" ]; then
    return
fi

echo "This builds AudioPeek with Xcode and with Scripts/build-app.sh, compares them, and runs"
echo "verify-panel, verify-playback and verify-appearance on the script build (a few minutes)."
echo "It quits any running AudioPeek and reopens the one in Applications when it's done."
if [ "${1:-}" != "--yes" ]; then
    read -r -p "Continue? [y/N] " answer
    case "$answer" in
        y | Y | yes) ;;
        *) echo "Stopped. Nothing was run."; exit 1 ;;
    esac
fi

RELEASE_WAS_RUNNING=0
if pgrep -f "$RELEASE_APP/Contents/MacOS/AudioPeek" > /dev/null 2>&1; then
    RELEASE_WAS_RUNNING=1
fi
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p "$CHECK"
STEP_NAMES=()
STEP_RESULTS=()

if Scripts/verify-build-checks.sh > "$CHECK/verify-build-checks.log" 2>&1; then
    record "Build-check regressions" PASS
else
    record "Build-check regressions (see build/check/verify-build-checks.log)" FAIL
fi

echo ""
echo "1. Building with Xcode (clean Release build)..."
if xcodebuild -project AudioPeek.xcodeproj -scheme AudioPeek -configuration Release \
    -destination 'platform=macOS' -derivedDataPath "$CHECK/dd" clean build > "$CHECK/xcodebuild.log" 2>&1; then
    record "Xcode build" PASS
else
    record "Xcode build (see build/check/xcodebuild.log)" FAIL
fi

echo "2. Comparing Swift flags..."
# The AudioPeek target's compile line, not the tests target's.
COMPILE_LINE="$(grep -E -- '-module-name AudioPeek( |$)' "$CHECK/xcodebuild.log" | grep -m 1 'swiftc')"
echo "$COMPILE_LINE" | tr ' ' '\n' | awk '
    take { print prev " " $0; take = 0; next }
    $0 == "-swift-version" || $0 == "-enable-upcoming-feature" || $0 == "-enable-experimental-feature" || $0 == "-D" { prev = $0; take = 1; next }
    $0 == "-enable-bare-slash-regex" || $0 ~ /^-default-isolation/ || $0 ~ /^-strict-concurrency/ || $0 ~ /^-D./ { print $0 }
' | grep -v -x -F -- "$IGNORED_XCODE_FLAGS" | LC_ALL=C sort -u > "$CHECK/xcode-flags.txt"
Scripts/build-app.sh --print-swift-flags | LC_ALL=C sort -u > "$CHECK/script-flags.txt"
if [ ! -s "$CHECK/xcode-flags.txt" ]; then
    record "Swift flags: none found in the Xcode log (the log format changed; fix the parser in check-builds.sh)" FAIL
elif diff "$CHECK/xcode-flags.txt" "$CHECK/script-flags.txt" > "$CHECK/flags.diff"; then
    record "Swift flags match ($(wc -l < "$CHECK/xcode-flags.txt" | tr -d ' ') flags)" PASS
else
    echo "   < Xcode only, > build-app.sh only:"
    sed 's/^/   /' "$CHECK/flags.diff"
    record "Swift flags differ: mirror the change in SWIFT_FLAGS in Scripts/build-app.sh" FAIL
fi

echo "3. Building with Scripts/build-app.sh..."
if [ -d "$CLT_DIR" ]; then
    BUILD_ENV="DEVELOPER_DIR=$CLT_DIR"
    TOOLCHAIN="Command Line Tools"
else
    BUILD_ENV="DEVELOPER_DIR=$(xcode-select -p)"
    TOOLCHAIN="the selected Xcode"
fi
if env "$BUILD_ENV" Scripts/build-app.sh > "$CHECK/build-app.log" 2>&1; then
    record "Script build with $TOOLCHAIN" PASS
else
    record "Script build with $TOOLCHAIN (see build/check/build-app.log)" FAIL
fi

echo "4. Comparing the two apps..."
if [ -d "$XCODE_APP" ] && [ -d "$SCRIPT_APP" ]; then
    XCODE_MIN="$(build_version "$XCODE_APP/Contents/MacOS/AudioPeek" minos)"
    SCRIPT_MIN="$(build_version "$SCRIPT_APP/Contents/MacOS/AudioPeek" minos)"
    echo "   SDK: Xcode $(build_version "$XCODE_APP/Contents/MacOS/AudioPeek" sdk), script $(build_version "$SCRIPT_APP/Contents/MacOS/AudioPeek" sdk)"
    if [ -n "$XCODE_MIN" ] && [ "$XCODE_MIN" = "$SCRIPT_MIN" ]; then
        record "Same minimum macOS ($XCODE_MIN)" PASS
    else
        record "Minimum macOS differs (Xcode '$XCODE_MIN', script '$SCRIPT_MIN')" FAIL
    fi
    if diff <(ls "$XCODE_APP/Contents/Resources" | grep -v -x Assets.car) <(ls "$SCRIPT_APP/Contents/Resources") > /dev/null; then
        record "Same resources" PASS
    else
        record "Resources differ: mirror the new resource in Scripts/build-app.sh" FAIL
    fi
    if compare_signing "$XCODE_APP" "$SCRIPT_APP"; then
        record "Same signing flags, identity and entitlements" PASS
    else
        record "Signing differs or could not be read (see build/check/signing.diff and entitlements.diff)" FAIL
    fi
    SPARKLE_PLIST="Contents/Frameworks/Sparkle.framework/Resources/Info.plist"
    XCODE_SPARKLE="$(plutil -extract CFBundleShortVersionString raw -o - "$XCODE_APP/$SPARKLE_PLIST" 2> /dev/null)"
    if compare_frameworks "$XCODE_APP" "$SCRIPT_APP"; then
        record "Same embedded frameworks, byte for byte (Sparkle $XCODE_SPARKLE)" PASS
    else
        record "Embedded frameworks differ or are missing (see build/check/frameworks.diff)" FAIL
    fi
else
    record "App comparison skipped: a build failed" FAIL
fi

echo "5. Running end-to-end checks on the script build..."
if [ -d "$SCRIPT_APP" ]; then
    for name in panel playback appearance; do
        if swift "Scripts/verify-$name.swift" "$SCRIPT_APP" > "$CHECK/verify-$name.log" 2>&1; then
            record "verify-$name" PASS
        else
            record "verify-$name (see build/check/verify-$name.log; rerun it against $XCODE_APP to tell a flaky check from a script-build problem)" FAIL
        fi
    done
else
    record "End-to-end checks skipped: no script build" FAIL
fi

echo ""
echo "Summary:"
FAILED=0
i=0
while [ "$i" -lt "${#STEP_NAMES[@]}" ]; do
    echo "  ${STEP_RESULTS[$i]}  ${STEP_NAMES[$i]}"
    [ "${STEP_RESULTS[$i]}" = "PASS" ] || FAILED=$((FAILED + 1))
    i=$((i + 1))
done
if [ "$FAILED" -eq 0 ]; then
    echo "All checks passed."
    exit 0
fi
echo "$FAILED check(s) failed."
exit 1

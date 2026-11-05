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

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
CHECK="$ROOT/build/check"
XCODE_APP="$CHECK/dd/Build/Products/Release/AudioPeek.app"
SCRIPT_APP="$ROOT/build/AudioPeek.app"
RELEASE_APP="/Applications/AudioPeek.app"
CLT_DIR="/Library/Developer/CommandLineTools"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
IGNORED_XCODE_FLAGS="-enable-experimental-feature DebugDescriptionMacro"

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

# Quits any AudioPeek started from this repo's build folder, unregisters those copies so
# Open With and Spotlight keep pointing at Applications, and reopens the release copy.
cleanup() {
    ps -axo pid=,comm= | awk -v prefix="$ROOT/build/" 'index($2, prefix) == 1 && $2 ~ /AudioPeek$/ {print $1}' |
        while read -r pid; do kill "$pid" 2> /dev/null; done
    "$LSREGISTER" -u "$SCRIPT_APP" > /dev/null 2>&1
    "$LSREGISTER" -u "$XCODE_APP" > /dev/null 2>&1
    if [ "$RELEASE_WAS_RUNNING" = "1" ] && [ -d "$RELEASE_APP" ]; then
        open "$RELEASE_APP"
    fi
}
trap cleanup EXIT

mkdir -p "$CHECK"
STEP_NAMES=()
STEP_RESULTS=()

record() {
    STEP_NAMES+=("$1")
    STEP_RESULTS+=("$2")
    echo "[$2] $1"
}

# Prints a binary's recorded minimum macOS or SDK (field is minos or sdk).
build_version() {
    xcrun otool -l "$1" 2> /dev/null | awk -v field="$2" '/LC_BUILD_VERSION/{f=1} f&&$1==field{print $2;exit}'
}

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

#!/bin/bash
# Regression checks for signing comparisons and cleanup. Never launches AudioPeek.
set -Eeuo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/check-builds.sh"
mkdir -p "$ROOT/build"
SCRATCH="$(mktemp -d "$ROOT/build/check-tests.XXXXXX")"
CHECK="$SCRATCH/comparison"
mkdir -p "$CHECK"
TEST_PIDS=""
finish() {
    local pid
    for pid in $TEST_PIDS; do
        kill -KILL "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
    done
    rm -rf "$SCRATCH"
}
trap finish EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

cat > "$SCRATCH/fixture.c" <<'C'
#include <signal.h>
#include <stdio.h>
#include <unistd.h>

int main(int argc, char **argv) {
    if (argc > 1) signal(SIGTERM, SIG_IGN);
    puts("ready");
    fflush(stdout);
    for (;;) pause();
}
C
xcrun clang "$SCRATCH/fixture.c" -o "$SCRATCH/baseline"
codesign --force --sign - --identifier com.landschoot.audiopeek.fixture "$SCRATCH/baseline"
cp "$SCRATCH/baseline" "$SCRATCH/candidate"
compare_signing "$SCRATCH/baseline" "$SCRATCH/candidate" || fail "identical signatures rejected"
pass "identical signing settings match"

codesign --force --sign - --options runtime --identifier com.landschoot.audiopeek.fixture "$SCRATCH/candidate"
if compare_signing "$SCRATCH/baseline" "$SCRATCH/candidate"; then
    fail "hardened runtime mismatch accepted"
fi
pass "hardened runtime mismatch fails"

cat > "$SCRATCH/entitlements.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>com.apple.security.network.client</key><true/>
<key>com.apple.security.network.server</key><true/>
</dict></plist>
PLIST
codesign --force --sign - --options 0 --identifier com.landschoot.audiopeek.fixture \
    --entitlements "$SCRATCH/entitlements.plist" "$SCRATCH/candidate"
if compare_signing "$SCRATCH/baseline" "$SCRATCH/candidate"; then
    fail "entitlement mismatch accepted"
fi
[ ! -s "$CHECK/signing.diff" ] || fail "entitlement test also changed signing flags or identity"
pass "entitlement mismatch fails independently of signing flags"

cat > "$SCRATCH/reordered.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>com.apple.security.network.server</key><true/>
<key>com.apple.security.network.client</key><true/>
</dict></plist>
PLIST
cp "$SCRATCH/baseline" "$SCRATCH/reordered"
codesign --force --sign - --identifier com.landschoot.audiopeek.fixture \
    --entitlements "$SCRATCH/reordered.plist" "$SCRATCH/reordered"
compare_signing "$SCRATCH/reordered" "$SCRATCH/candidate" || fail "equivalent entitlements rejected"
pass "entitlement dictionary order does not affect comparison"

codesign --remove-signature "$SCRATCH/candidate"
if compare_signing "$SCRATCH/baseline" "$SCRATCH/candidate"; then
    fail "unsigned binary accepted"
fi
pass "unreadable signing settings fail closed"

make_framework_app() {
    local app="$1"
    mkdir -p "$app/Contents/Frameworks/Fake.framework/Versions/B"
    printf 'binary' > "$app/Contents/Frameworks/Fake.framework/Versions/B/Fake"
    ln -s B "$app/Contents/Frameworks/Fake.framework/Versions/Current"
    ln -s Versions/Current/Fake "$app/Contents/Frameworks/Fake.framework/Fake"
}
make_framework_app "$SCRATCH/xcode.app"
make_framework_app "$SCRATCH/script.app"
compare_frameworks "$SCRATCH/xcode.app" "$SCRATCH/script.app" || fail "identical frameworks rejected"
pass "identical embedded frameworks match"

printf 'changed' > "$SCRATCH/script.app/Contents/Frameworks/Fake.framework/Versions/B/Fake"
if compare_frameworks "$SCRATCH/xcode.app" "$SCRATCH/script.app"; then
    fail "changed framework file accepted"
fi
pass "a changed framework file fails"

make_framework_app "$SCRATCH/headers.app"
mkdir -p "$SCRATCH/headers.app/Contents/Frameworks/Fake.framework/Versions/B/Headers"
printf 'header' > "$SCRATCH/headers.app/Contents/Frameworks/Fake.framework/Versions/B/Headers/Fake.h"
if compare_frameworks "$SCRATCH/xcode.app" "$SCRATCH/headers.app"; then
    fail "extra framework file accepted"
fi
pass "an extra framework file fails"

rm -f "$SCRATCH/script.app/Contents/Frameworks/Fake.framework/Versions/Current"
ln -s A "$SCRATCH/script.app/Contents/Frameworks/Fake.framework/Versions/Current"
printf 'binary' > "$SCRATCH/script.app/Contents/Frameworks/Fake.framework/Versions/B/Fake"
if compare_frameworks "$SCRATCH/xcode.app" "$SCRATCH/script.app"; then
    fail "changed symlink target accepted"
fi
pass "a changed symlink target fails"

mkdir -p "$SCRATCH/none.app/Contents"
if compare_frameworks "$SCRATCH/xcode.app" "$SCRATCH/none.app" || compare_frameworks "$SCRATCH/none.app" "$SCRATCH/none.app"; then
    fail "missing Frameworks folder accepted"
fi
pass "a missing Frameworks folder fails closed"

ROOT="$SCRATCH/Audio Peek"
BUILD_BINARY="$ROOT/build/Test.app/Contents/MacOS/AudioPeek"
OTHER_BINARY="$ROOT/build-other/Test.app/Contents/MacOS/AudioPeek"
mkdir -p "$(dirname "$BUILD_BINARY")" "$(dirname "$OTHER_BINARY")"
cp "$SCRATCH/baseline" "$BUILD_BINARY"
cp "$SCRATCH/baseline" "$OTHER_BINARY"
"$OTHER_BINARY" > "$SCRATCH/other.log" &
OTHER_PID=$!
TEST_PIDS="$OTHER_PID"
for mode in normal ignore-term; do
    if [ "$mode" = normal ]; then
        "$BUILD_BINARY" > "$SCRATCH/build.log" &
    else
        "$BUILD_BINARY" ignore-term > "$SCRATCH/build.log" &
    fi
    BUILD_PID=$!
    TEST_PIDS="$OTHER_PID $BUILD_PID"
    for ((attempt = 0; attempt < 50; attempt++)); do
        grep -q ready "$SCRATCH/build.log" && break
        sleep 0.1
    done
    grep -q ready "$SCRATCH/build.log" || fail "fixture did not start"
    [ "$(build_process_ids)" = "$BUILD_PID" ] || fail "process selection did not preserve the spaced path"
    stop_build_apps || fail "cleanup did not stop the $mode fixture"
    wait "$BUILD_PID" 2>/dev/null || true
    TEST_PIDS="$OTHER_PID"
    if kill -0 "$BUILD_PID" 2>/dev/null; then fail "cleanup returned before the process exited"; fi
    kill -0 "$OTHER_PID" 2>/dev/null || fail "cleanup killed a process outside build/"
    pass "cleanup handles $mode process in a spaced path and leaves other processes running"
done

echo "All build-check regressions passed."

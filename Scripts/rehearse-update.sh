#!/bin/bash
# Tries a real in-place update before a release, without touching the installed AudioPeek.
#
# Builds the current source three times as "AudioPeek Rehearsal" (bundle id
# com.landschoot.audiopeek.rehearsal, versions <version>.1, .2 and .3), signed with the real
# release certificate and update key, and serves updates from a local feed instead of GitHub.
# Its Finder permission, settings and login item are separate from AudioPeek's.
#
#   Scripts/rehearse-update.sh          build all three; the feed offers .2
#   Scripts/rehearse-update.sh --next   after updating to .2, make the feed offer .3
#
# Then follow the steps it prints. Quit AudioPeek first so the two don't share the hotkey.

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
# shellcheck source=Scripts/release-common.sh
source "$ROOT/Scripts/release-common.sh"

WORK="$ROOT/build/rehearsal"
FEED="$WORK/feed"
NEXT="$WORK/next"
PORT=8642
FEED_URL="http://127.0.0.1:$PORT/"
BUNDLE_ID="com.landschoot.audiopeek.rehearsal"
NAME="AudioPeek Rehearsal"
STEP="starting"
trap 'echo "rehearse-update: failed at: $STEP." >&2' ERR

TOOLS="$("$ROOT/Scripts/fetch-sparkle.sh")"

# Rebuilds the feed so it offers exactly the disk image given, and checks it.
publish() {
    local dmg="$1" app="$2"
    rm -rf "$FEED"
    mkdir -p "$FEED"
    cp "$dmg" "$FEED/"
    printf 'Rehearsal build %s.\n' "$(plutil -extract CFBundleShortVersionString raw -o - "$app/Contents/Info.plist")" \
        > "$FEED/$(basename "$dmg" .dmg).md"
    "$TOOLS/bin/generate_appcast" --account "$SPARKLE_ACCOUNT" --download-url-prefix "$FEED_URL" \
        --embed-release-notes --maximum-deltas 0 -o "$FEED/appcast.xml" "$FEED" > "$WORK/generate_appcast.log" 2>&1 ||
        release_die "generate_appcast failed. See build/rehearsal/generate_appcast.log."
    swift "$ROOT/Scripts/verify-appcast.swift" "$FEED/appcast.xml" "$FEED/$(basename "$dmg")" "$app" \
        "$FEED_URL$(basename "$dmg")" > /dev/null
}

if [ "${1:-}" = "--next" ]; then
    STEP="publishing the third build"
    [ -f "$NEXT/AudioPeek-Rehearsal-3.dmg" ] || release_die "No third build. Run Scripts/rehearse-update.sh first."
    publish "$NEXT/AudioPeek-Rehearsal-3.dmg" "$NEXT/$NAME.app"
    trap - ERR
    echo "The feed now offers build 3. Leave the feed server running and carry on with the steps."
    exit 0
fi
[ $# -eq 0 ] || release_die "Unknown option '$1'."

STEP="preflight"
require_release_certificate
read_setting() {
    xcodebuild -project AudioPeek.xcodeproj -target AudioPeek -configuration Release -showBuildSettings 2>/dev/null |
        awk -v key="$1" '$1 == key && value == "" { value = $3 } END { print value }'
}
VERSION="$(read_setting MARKETING_VERSION)"
BUILD="$(read_setting CURRENT_PROJECT_VERSION)"
[ -n "$VERSION" ] && [ -n "$BUILD" ] || release_die "Couldn't read the version from the Xcode project."

STEP="building (clean Release)"
rm -rf "$WORK"
mkdir -p "$WORK" "$NEXT"
xcodebuild -project AudioPeek.xcodeproj -scheme AudioPeek -configuration Release \
    -destination 'platform=macOS' -derivedDataPath "$WORK/dd" clean build > "$WORK/xcodebuild.log" 2>&1 ||
    release_die "The Xcode build failed. See build/rehearsal/xcodebuild.log."
BUILT="$WORK/dd/Build/Products/Release/AudioPeek.app"
require_update_key "$TOOLS" "$BUILT"

echo "Signing three rehearsal builds. macOS may ask to let codesign use the certificate: enter your login password and choose Always Allow."
for n in 1 2 3; do
    STEP="making rehearsal build $n"
    dir="$WORK/build-$n"
    app="$dir/$NAME.app"
    mkdir -p "$dir"
    ditto "$BUILT" "$app"
    plist="$app/Contents/Info.plist"
    plutil -replace CFBundleIdentifier -string "$BUNDLE_ID" "$plist"
    plutil -replace CFBundleName -string "$NAME" "$plist"
    plutil -replace CFBundleDisplayName -string "$NAME" "$plist"
    plutil -replace CFBundleShortVersionString -string "$VERSION.$n" "$plist"
    plutil -replace CFBundleVersion -string "$BUILD.$n" "$plist"
    plutil -replace SUFeedURL -string "${FEED_URL}appcast.xml" "$plist"
    plutil -replace NSAppTransportSecurity -json '{"NSAllowsLocalNetworking":true}' "$plist"
    # No Open With entries for a throwaway copy.
    plutil -remove CFBundleDocumentTypes "$plist"
    plutil -remove UTImportedTypeDeclarations "$plist"
    sign_with_release_certificate "$app"
    check_release_identity "$app"
    make_release_dmg "$app" "$dir/AudioPeek-Rehearsal-$n.dmg" "$NAME"
    check_release_dmg "$dir/AudioPeek-Rehearsal-$n.dmg" "$NAME.app" "$VERSION.$n" "$BUILD.$n"
done

STEP="arranging the builds"
INSTALL="$WORK/install/AudioPeek-Rehearsal-1.dmg"
mkdir -p "$WORK/install"
cp "$WORK/build-1/AudioPeek-Rehearsal-1.dmg" "$INSTALL"
# Marked as downloaded, so the first install meets Gatekeeper like a real download does.
xattr -w com.apple.quarantine "0083;$(printf '%x' "$(date +%s)");Safari;" "$INSTALL"
cp "$WORK/build-3/AudioPeek-Rehearsal-3.dmg" "$NEXT/"
ditto "$WORK/build-3/$NAME.app" "$NEXT/$NAME.app"
publish "$WORK/build-2/AudioPeek-Rehearsal-2.dmg" "$WORK/build-2/$NAME.app"

trap - ERR
cat <<EOF

Rehearsal ready: $NAME $VERSION.1 to install, the feed offers $VERSION.2, and $VERSION.3 waits in reserve.
All three carry: $(codesign -d -r- "$WORK/build-1/$NAME.app" 2>&1 | sed -n 's/^designated => //p')

1. Quit AudioPeek. In a separate terminal, start the feed and leave it running:
     python3 -m http.server $PORT --bind 127.0.0.1 --directory "$FEED"
2. Open build/rehearsal/install/AudioPeek-Rehearsal-1.dmg, drag "$NAME" to Applications, open it,
   and use Open Anyway in System Settings > Privacy & Security if macOS blocks it.
3. Select an audio file in Finder, press the hotkey, and choose Allow for Finder access.
4. Menu bar eye > Check for Updates… > Install Update. It should relaunch as $VERSION.2 with no
   Open Anyway and no Finder prompt; preview a file to confirm.
5. Background check: run Scripts/rehearse-update.sh --next, then quit $NAME, run
     defaults delete $BUNDLE_ID SULastCheckTime
   and reopen it. Within a minute or two the eye should get a dot and the menu should read
   "Update to $VERSION.3…", with no window. Hide the menu bar icon in Settings and check the
   Updates section names $VERSION.3 too, then show the icon again. Don't install $VERSION.3 yet.
6. Automatic install: in Settings > Updates, turn on Install updates automatically. Quit, run the
   same defaults delete command, reopen, and close Settings. It should download $VERSION.3 quietly
   (the menu reads "Restart to Install $VERSION.3") and, within about a minute of sitting idle,
   install and relaunch by itself. Preview a file: no Finder prompt.

Clean up afterwards:
  rm -rf "/Applications/$NAME.app"
  tccutil reset AppleEvents $BUNDLE_ID
  defaults delete $BUNDLE_ID
EOF

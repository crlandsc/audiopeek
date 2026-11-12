#!/bin/bash
# Builds an AudioPeek release, ready to upload: build/release/AudioPeek.dmg and
# build/release/appcast.xml. It publishes nothing; it prints the command that does.
#
# Before running: bump MARKETING_VERSION and CURRENT_PROJECT_VERSION in the Xcode project,
# commit, run Scripts/check-builds.sh, and write the release notes to
# build/release-notes-<version>.md (Markdown; they go in the update window and on GitHub).
# The two release keys must be in the login keychain (Scripts/make-release-keys.sh).
#
#   Scripts/release.sh

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
# shellcheck source=Scripts/release-common.sh
source "$ROOT/Scripts/release-common.sh"

REPO_URL="https://github.com/crlandsc/audiopeek"
OUT="$ROOT/build/release"
DD="$OUT/dd"
STEP="starting"
trap 'echo "release: failed at: $STEP." >&2' ERR

STEP="preflight"
[ -z "$(git status --porcelain)" ] || release_die "The working tree has changes. Commit or stash them first, so the release matches a commit."
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
[ "$BRANCH" = "main" ] || echo "Note: releasing from '$BRANCH', not main."
COMMIT="$(git rev-parse --short HEAD)"
FULL_COMMIT="$(git rev-parse HEAD)"
read_setting() {
    xcodebuild -project AudioPeek.xcodeproj -target AudioPeek -configuration Release -showBuildSettings 2>/dev/null |
        awk -v key="$1" '$1 == key { print $3; exit }'
}
VERSION="$(read_setting MARKETING_VERSION)"
BUILD="$(read_setting CURRENT_PROJECT_VERSION)"
[ -n "$VERSION" ] && [ -n "$BUILD" ] || release_die "Couldn't read the version from the Xcode project."
NOTES="$ROOT/build/release-notes-$VERSION.md"
[ -s "$NOTES" ] || release_die "No release notes at build/release-notes-$VERSION.md."
if git rev-parse -q --verify "refs/tags/v$VERSION" > /dev/null; then
    echo "Note: the tag v$VERSION already exists. Bump the version unless this is a rehearsal."
fi
require_release_certificate
TOOLS="$("$ROOT/Scripts/fetch-sparkle.sh")"
echo "Releasing AudioPeek $VERSION (build $BUILD) from $COMMIT."

STEP="building (clean Release)"
rm -rf "$OUT"
mkdir -p "$OUT"
xcodebuild -project AudioPeek.xcodeproj -scheme AudioPeek -configuration Release \
    -destination 'platform=macOS' -derivedDataPath "$DD" clean build > "$OUT/xcodebuild.log" 2>&1 ||
    release_die "The Xcode build failed. See build/release/xcodebuild.log."
APP="$OUT/AudioPeek.app"
ditto "$DD/Build/Products/Release/AudioPeek.app" "$APP"
[ "$(plutil -extract CFBundleShortVersionString raw -o - "$APP/Contents/Info.plist")" = "$VERSION" ] &&
    [ "$(plutil -extract CFBundleVersion raw -o - "$APP/Contents/Info.plist")" = "$BUILD" ] ||
    release_die "The built app's version doesn't match the project."
require_update_key "$TOOLS" "$APP"

STEP="signing with the release certificate"
echo "Signing. macOS may ask to let codesign use the certificate: enter your login password and choose Always Allow."
sign_with_release_certificate "$APP"

STEP="checking the signature"
check_release_identity "$APP"
echo "Identity: $(codesign -d -r- "$APP" 2>&1 | sed -n 's/^designated => //p')"

STEP="making the disk image"
UPDATES="$OUT/updates"
mkdir -p "$UPDATES"
DMG="$UPDATES/AudioPeek.dmg"
make_release_dmg "$APP" "$DMG" AudioPeek
check_release_dmg "$DMG" AudioPeek.app "$VERSION" "$BUILD"

STEP="writing the appcast"
# The notes go into the appcast next to the disk image they describe; only the disk
# image and appcast.xml are uploaded.
cp "$NOTES" "$UPDATES/AudioPeek.md"
DOWNLOAD_PREFIX="$REPO_URL/releases/download/v$VERSION/"
"$TOOLS/bin/generate_appcast" --account "$SPARKLE_ACCOUNT" \
    --download-url-prefix "$DOWNLOAD_PREFIX" \
    --full-release-notes-url "$REPO_URL/releases/tag/v$VERSION" \
    --link "$REPO_URL" \
    --embed-release-notes --maximum-deltas 0 \
    -o "$UPDATES/appcast.xml" "$UPDATES" > "$OUT/generate_appcast.log" 2>&1 ||
    release_die "generate_appcast failed. See build/release/generate_appcast.log."

STEP="checking the appcast"
swift "$ROOT/Scripts/verify-appcast.swift" "$UPDATES/appcast.xml" "$DMG" "$APP" "${DOWNLOAD_PREFIX}AudioPeek.dmg"
cp "$DMG" "$OUT/AudioPeek.dmg"
cp "$UPDATES/appcast.xml" "$OUT/appcast.xml"

trap - ERR
cat <<EOF

Ready: build/release/AudioPeek.dmg and build/release/appcast.xml (AudioPeek $VERSION, build $BUILD, $COMMIT).

To publish, push the commit, then run:

  gh release create v$VERSION build/release/AudioPeek.dmg build/release/appcast.xml --target $FULL_COMMIT --title "AudioPeek $VERSION" --notes-file build/release-notes-$VERSION.md

Both files must go up together: installed copies read appcast.xml from the latest release.
EOF

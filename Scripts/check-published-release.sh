#!/bin/bash
# Checks a published release the way an installed copy will meet it. Run it after
# `gh release create`, with the new version installed.
#
# Downloads the feed from the address inside the installed app, then the disk image the
# feed points to, and checks: the feed offers the installed version, the download URL is
# that version's release, the disk image's update signature verifies with the key inside
# the installed app, and the app in the disk image carries the release certificate.
#
#   Scripts/check-published-release.sh                    checks /Applications/AudioPeek.app
#   Scripts/check-published-release.sh <path to the app>

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=Scripts/release-common.sh
source "$ROOT/Scripts/release-common.sh"

APP="${1:-/Applications/AudioPeek.app}"
PLIST="$APP/Contents/Info.plist"
[ -f "$PLIST" ] || release_die "No app at $APP."
FEED="$(plutil -extract SUFeedURL raw -o - "$PLIST" 2>/dev/null)" || release_die "$APP has no SUFeedURL, so it can't update itself."
VERSION="$(plutil -extract CFBundleShortVersionString raw -o - "$PLIST")"
BUILD="$(plutil -extract CFBundleVersion raw -o - "$PLIST")"
[ "$FEED" = "$RELEASE_FEED_URL" ] || release_die "$APP reads its updates from '$FEED', not the pinned feed."
check_release_identity "$APP"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
DOWNLOAD="https://github.com/crlandsc/audiopeek/releases/download/v$VERSION/AudioPeek.dmg"
echo "Installed: AudioPeek $VERSION ($BUILD). Downloading the feed and the disk image..."
curl -fsSL --retry 2 -o "$WORK/appcast.xml" "$FEED" || release_die "Couldn't download $FEED."
curl -fsSL --retry 2 -o "$WORK/AudioPeek.dmg" "$DOWNLOAD" || release_die "Couldn't download $DOWNLOAD."

swift "$ROOT/Scripts/verify-appcast.swift" "$WORK/appcast.xml" "$WORK/AudioPeek.dmg" "$APP" "$DOWNLOAD"
check_release_dmg "$WORK/AudioPeek.dmg" AudioPeek.app "$VERSION" "$BUILD"
echo "The published release matches the installed AudioPeek $VERSION ($BUILD)."
echo "Last check by hand: menu bar eye > Check for Updates… should say you're up to date."

#!/bin/bash
# Gets Sparkle, the updater AudioPeek embeds, and prints the folder it unpacked to.
#
# Downloads Sparkle-for-Swift-Package-Manager.zip for the version the Xcode project pins,
# once, into build/sparkle/<version>/, and checks it against the SHA-256 pinned below.
# The folder holds Sparkle.xcframework and Sparkle's tools in bin/ (generate_keys,
# generate_appcast, sign_update).
#
#   Scripts/fetch-sparkle.sh            the version pinned in AudioPeek.xcodeproj
#   Scripts/fetch-sparkle.sh <version>  a given version (build-app.sh passes its own reading)

set -Eeuo pipefail

# SHA-256 of Sparkle-for-Swift-Package-Manager.zip for each Sparkle version, the same
# checksum Sparkle's Package.swift gives Swift Package Manager. A new Sparkle pin in
# Xcode needs its line here.
sparkle_sha256() {
    case "$1" in
        2.10.1) echo 4c2e48a3e50ebcc2c88a58a4c7264a1a99c3c31857ce754357afb9cdb323022a ;;
        *) return 1 ;;
    esac
}

die() {
    echo "fetch-sparkle: $*" >&2
    exit 1
}

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT/AudioPeek.xcodeproj/project.pbxproj"

pinned_version() {
    local root count i ref
    root="$(plutil -extract rootObject raw -o - "$PROJECT" 2>/dev/null)" || return 1
    count="$(plutil -extract "objects.$root.packageReferences" raw -o - "$PROJECT" 2>/dev/null)" || return 1
    i=0
    while [ "$i" -lt "$count" ]; do
        ref="$(plutil -extract "objects.$root.packageReferences.$i" raw -o - "$PROJECT")"
        if [ "$(plutil -extract "objects.$ref.repositoryURL" raw -o - "$PROJECT")" = "https://github.com/sparkle-project/Sparkle" ] &&
            [ "$(plutil -extract "objects.$ref.requirement.kind" raw -o - "$PROJECT")" = "exactVersion" ]; then
            plutil -extract "objects.$ref.requirement.version" raw -o - "$PROJECT"
            return
        fi
        i=$((i + 1))
    done
    return 1
}

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
    VERSION="$(pinned_version)" || die "AudioPeek.xcodeproj doesn't pin Sparkle to an exact version."
fi
SHA256="$(sparkle_sha256 "$VERSION")" ||
    die "No pinned checksum for Sparkle $VERSION. Add it to sparkle_sha256 in Scripts/fetch-sparkle.sh."

DIR="$ROOT/build/sparkle/$VERSION"
ZIP="$DIR/Sparkle-for-Swift-Package-Manager.zip"
UNPACKED="$DIR/unpacked"

if [ ! -f "$ZIP" ]; then
    echo "Downloading Sparkle $VERSION (first time only)..." >&2
    mkdir -p "$DIR"
    curl -fsSL --retry 2 -o "$ZIP.part" \
        "https://github.com/sparkle-project/Sparkle/releases/download/$VERSION/Sparkle-for-Swift-Package-Manager.zip" ||
        die "Couldn't download Sparkle $VERSION from GitHub. Check the network and run this again."
    mv "$ZIP.part" "$ZIP"
fi
if [ "$(shasum -a 256 "$ZIP" | awk '{print $1}')" != "$SHA256" ]; then
    rm -f "$ZIP"
    rm -rf "$UNPACKED"
    die "The Sparkle $VERSION download doesn't match its pinned checksum, so it was deleted. Run this again."
fi
if [ ! -d "$UNPACKED/Sparkle.xcframework" ] || [ ! -x "$UNPACKED/bin/generate_appcast" ]; then
    rm -rf "$UNPACKED" "$UNPACKED.part"
    ditto -x -k "$ZIP" "$UNPACKED.part"
    mv "$UNPACKED.part" "$UNPACKED"
fi
echo "$UNPACKED"

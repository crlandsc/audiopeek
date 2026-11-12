#!/bin/bash
# Shared by Scripts/release.sh and Scripts/rehearse-update.sh. Sourced, not run.
#
# The two release keys live in the login keychain (Scripts/make-release-keys.sh made them).
# Their public halves are pinned here and in AudioPeek/Info.plist; a build signed with
# anything else is refused.

# SHA-1 of the "AudioPeek Release Signing" certificate. Every release carries it in its
# designated requirement, which is what keeps the Finder permission across updates.
# Changing it resets that permission for everyone.
RELEASE_CERT_NAME="AudioPeek Release Signing"
RELEASE_CERT_SHA1="29670BFD70DBB74870CD13C2827DCC0C01E15B0A"
# The keychain account Sparkle's tools keep the update key under.
SPARKLE_ACCOUNT="audiopeek"
RELEASE_KEYCHAIN="${RELEASE_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"

release_die() {
    echo "$(basename "$0"): $*" >&2
    exit 1
}

# Fails unless the keychain holds the pinned certificate.
require_release_certificate() {
    security find-certificate -a -c "$RELEASE_CERT_NAME" -Z "$RELEASE_KEYCHAIN" 2>/dev/null |
        grep -q "^SHA-1 hash: $RELEASE_CERT_SHA1\$" ||
        release_die "The '$RELEASE_CERT_NAME' certificate ($RELEASE_CERT_SHA1) isn't in $RELEASE_KEYCHAIN. Restore it from your backup, or run Scripts/make-release-keys.sh on a new Mac."
}

# Fails unless Sparkle's update key in the keychain matches the public key in the app.
require_update_key() {
    local tools="$1" app="$2" keychain_key app_key
    app_key="$(plutil -extract SUPublicEDKey raw -o - "$app/Contents/Info.plist" 2>/dev/null)" ||
        release_die "$app has no SUPublicEDKey."
    keychain_key="$("$tools/bin/generate_keys" --account "$SPARKLE_ACCOUNT" -p 2>/dev/null)" ||
        release_die "No Sparkle update key (account '$SPARKLE_ACCOUNT') in the keychain. Restore it from your backup with generate_keys -f."
    [ "$keychain_key" = "$app_key" ] ||
        release_die "The update key in the keychain doesn't match SUPublicEDKey in the app. Updates signed with it would be refused."
}

# Re-signs an app with the release certificate, inside out: Sparkle's helpers, the
# framework, then the app. Downloader.xpc keeps its entitlements (network access).
sign_with_release_certificate() {
    local app="$1"
    local fw="$app/Contents/Frameworks/Sparkle.framework"
    local sign=(codesign --force --timestamp=none --sign "$RELEASE_CERT_SHA1" --keychain "$RELEASE_KEYCHAIN")
    "${sign[@]}" "$fw/Versions/B/XPCServices/Installer.xpc"
    "${sign[@]}" --preserve-metadata=entitlements "$fw/Versions/B/XPCServices/Downloader.xpc"
    "${sign[@]}" "$fw/Versions/B/Autoupdate"
    "${sign[@]}" "$fw/Versions/B/Updater.app"
    "${sign[@]}" "$fw"
    "${sign[@]}" "$app"
}

# Fails unless the app and every signed part inside it carry the release certificate,
# and the app's designated requirement is its bundle id plus that certificate.
check_release_identity() {
    local app="$1" bundle_id requirement part leaf
    local fw="$app/Contents/Frameworks/Sparkle.framework"
    codesign --verify --deep --strict "$app" || release_die "$app fails a deep signature check."
    bundle_id="$(plutil -extract CFBundleIdentifier raw -o - "$app/Contents/Info.plist")"
    leaf="$(echo "$RELEASE_CERT_SHA1" | tr '[:upper:]' '[:lower:]')"
    requirement="$(codesign -d -r- "$app" 2>&1 | sed -n 's/^designated => //p')"
    [ "$requirement" = "identifier \"$bundle_id\" and certificate leaf = H\"$leaf\"" ] ||
        release_die "$app has the wrong identity: '$requirement'."
    for part in "$fw/Versions/B/XPCServices/Installer.xpc" "$fw/Versions/B/XPCServices/Downloader.xpc" \
        "$fw/Versions/B/Autoupdate" "$fw/Versions/B/Updater.app" "$fw"; do
        codesign -dvv "$part" 2>&1 | grep -qx "Authority=$RELEASE_CERT_NAME" ||
            release_die "$part isn't signed with the release certificate."
    done
}

# Makes a disk image holding the app and an Applications link.
make_release_dmg() {
    local app="$1" dmg="$2" volume="$3" stage
    stage="$(mktemp -d)"
    ditto "$app" "$stage/$(basename "$app")"
    ln -s /Applications "$stage/Applications"
    rm -f "$dmg"
    hdiutil create -quiet -volname "$volume" -srcfolder "$stage" -format UDZO "$dmg" ||
        release_die "hdiutil couldn't make $dmg."
    rm -rf "$stage"
}

# Mounts a disk image and checks the app inside: version, build and release identity.
check_release_dmg() {
    local dmg="$1" app_name="$2" version="$3" build="$4" mount inside
    mount="$(mktemp -d)"
    hdiutil attach -quiet -nobrowse -readonly -mountpoint "$mount" "$dmg" || release_die "Couldn't mount $dmg."
    inside="$mount/$app_name"
    local ok=1
    [ "$(plutil -extract CFBundleShortVersionString raw -o - "$inside/Contents/Info.plist" 2>/dev/null)" = "$version" ] || ok=0
    [ "$(plutil -extract CFBundleVersion raw -o - "$inside/Contents/Info.plist" 2>/dev/null)" = "$build" ] || ok=0
    [ -L "$mount/Applications" ] || ok=0
    if [ "$ok" = "1" ]; then
        (check_release_identity "$inside") || ok=0
    fi
    hdiutil detach -quiet "$mount" || hdiutil detach -quiet -force "$mount"
    rmdir "$mount" 2>/dev/null || true
    [ "$ok" = "1" ] || release_die "The app inside $dmg isn't version $version ($build) with the release identity, or the Applications link is missing."
}

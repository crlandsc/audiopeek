#!/bin/bash
# Builds build/AudioPeek.app with only Apple's Command Line Tools, no Xcode.
#
# This mirrors the AudioPeek target in AudioPeek.xcodeproj by hand. When a build
# setting changes in Xcode, change it here too. Scripts/check-builds.sh catches drift.
#
# The one dependency, Sparkle (the updater), is read from the Xcode project's package
# pin. Scripts/fetch-sparkle.sh downloads that release from GitHub into build/sparkle/
# on the first build and checks it against a pinned SHA-256.
#
#   Scripts/build-app.sh                      build the app
#   Scripts/build-app.sh --print-swift-flags  print the Swift flags and exit

set -Eeuo pipefail

# Swift flags, copied from Xcode's own compile command for the AudioPeek target.
# They mirror these project.pbxproj settings:
#   SWIFT_VERSION = 5.0                                  -swift-version 5
#   SWIFT_ENABLE_BARE_SLASH_REGEX (Xcode default YES)    -enable-bare-slash-regex
#   SWIFT_APPROACHABLE_CONCURRENCY = YES                 the five concurrency features below
#   SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY      MemberImportVisibility
#   SWIFT_DEFAULT_ACTOR_ISOLATION = nonisolated          no flag (the default)
# Xcode also passes -enable-experimental-feature DebugDescriptionMacro. Nothing uses
# @DebugDescription, so it is left out on purpose.
SWIFT_FLAGS=(
    "-swift-version 5"
    "-enable-bare-slash-regex"
    "-enable-upcoming-feature DisableOutwardActorInference"
    "-enable-upcoming-feature GlobalActorIsolatedTypesUsability"
    "-enable-upcoming-feature InferIsolatedConformances"
    "-enable-upcoming-feature InferSendableFromCaptures"
    "-enable-upcoming-feature MemberImportVisibility"
    "-enable-upcoming-feature NonisolatedNonsendingByDefault"
)

if [ "${1:-}" = "--print-swift-flags" ]; then
    printf '%s\n' "${SWIFT_FLAGS[@]}"
    exit 0
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT/AudioPeek.xcodeproj/project.pbxproj"
SOURCE_DIR="$ROOT/AudioPeek"
ICONSET_SOURCE="$SOURCE_DIR/Assets.xcassets/AppIcon.appiconset"
WORK="$ROOT/build/app"
STAGE="$WORK/stage/AudioPeek.app"
OUT="$ROOT/build/AudioPeek.app"
CLT_DIR="/Library/Developer/CommandLineTools"

STEP="starting"
trap 'echo "build-app: failed at: $STEP. build/AudioPeek.app was not changed." >&2' ERR

die() {
    echo "build-app: $*" >&2
    exit 1
}

# 15.0 -> 15, 26.1 -> 26.1, so 15 and 15.0 compare equal.
normalize_version() {
    echo "$1" | sed -E 's/(\.0)+$//'
}

STEP="checking this Mac"
if [ "$(sysctl -in hw.optional.arm64 2>/dev/null)" != "1" ]; then
    die "AudioPeek needs a Mac with Apple silicon."
fi

STEP="finding the toolchain"
CLT_MESSAGE="Needs Apple's Command Line Tools 26 or newer (macOS 15.6 or later). Install with 'xcode-select --install' or update in Software Update."

# Sets SDK_PATH and SDK_VERSION from the toolchain xcrun picks. Fails if the SDK is older than 26.
find_sdk() {
    SDK_PATH="$(xcrun --sdk macosx --show-sdk-path 2>/dev/null)" || return 1
    SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version 2>/dev/null)" || return 1
    [ -n "$SDK_PATH" ] && [ "${SDK_VERSION%%.*}" -ge 26 ] 2>/dev/null
}

if ! find_sdk; then
    # An older Xcode may be selected while newer Command Line Tools are installed.
    if [ -d "$CLT_DIR" ]; then
        export DEVELOPER_DIR="$CLT_DIR"
        find_sdk || die "$CLT_MESSAGE"
    else
        die "$CLT_MESSAGE"
    fi
fi

STEP="reading the Xcode project"
[ -f "$PROJECT" ] || die "Can't find AudioPeek.xcodeproj. Run this from a copy of the AudioPeek repo."

pbx() {
    plutil -extract "$1" raw -o - "$PROJECT" 2>/dev/null
}

ROOT_OBJECT="$(pbx rootObject)" || die "Can't read $PROJECT."
APP_TARGET=""
target_count="$(pbx "objects.$ROOT_OBJECT.targets")"
i=0
while [ "$i" -lt "$target_count" ]; do
    target="$(pbx "objects.$ROOT_OBJECT.targets.$i")"
    if [ "$(pbx "objects.$target.name")" = "AudioPeek" ]; then
        APP_TARGET="$target"
    fi
    i=$((i + 1))
done
[ -n "$APP_TARGET" ] || die "No AudioPeek target in the Xcode project."

CONFIG_LIST="$(pbx "objects.$APP_TARGET.buildConfigurationList")"
RELEASE_CONFIG=""
config_count="$(pbx "objects.$CONFIG_LIST.buildConfigurations")"
i=0
while [ "$i" -lt "$config_count" ]; do
    config="$(pbx "objects.$CONFIG_LIST.buildConfigurations.$i")"
    if [ "$(pbx "objects.$config.name")" = "Release" ]; then
        RELEASE_CONFIG="$config"
    fi
    i=$((i + 1))
done
[ -n "$RELEASE_CONFIG" ] || die "No Release configuration for the AudioPeek target."

setting() {
    local value
    value="$(pbx "objects.$RELEASE_CONFIG.buildSettings.$1")" || die "The AudioPeek target has no $1 setting. Mirror the change in Scripts/build-app.sh."
    case "$value" in
        "" | *'$('*) die "Can't use the $1 setting ('$value'). Mirror the change in Scripts/build-app.sh." ;;
    esac
    echo "$value"
}

PRODUCT_NAME="$(setting PRODUCT_NAME)"
BUNDLE_ID="$(setting PRODUCT_BUNDLE_IDENTIFIER)"
MARKETING_VERSION="$(setting MARKETING_VERSION)"
BUILD_NUMBER="$(setting CURRENT_PROJECT_VERSION)"
MIN_MACOS="$(setting MACOSX_DEPLOYMENT_TARGET)"

STEP="checking the project has nothing this script misses"
MIRROR_HINT="Mirror it in Scripts/build-app.sh, then update this check."

# Packages: exactly one, Sparkle, pinned to an exact version, used by the app target.
[ "$(pbx "objects.$ROOT_OBJECT.packageReferences" || echo 0)" = "1" ] || die "The Xcode project's Swift packages changed. $MIRROR_HINT"
SPARKLE_PACKAGE="$(pbx "objects.$ROOT_OBJECT.packageReferences.0")"
[ "$(pbx "objects.$SPARKLE_PACKAGE.repositoryURL")" = "https://github.com/sparkle-project/Sparkle" ] ||
    die "The Xcode project's Swift package is not Sparkle. $MIRROR_HINT"
[ "$(pbx "objects.$SPARKLE_PACKAGE.requirement.kind")" = "exactVersion" ] ||
    die "Sparkle must be pinned to an exact version in the Xcode project."
SPARKLE_VERSION="$(pbx "objects.$SPARKLE_PACKAGE.requirement.version")"
[ "$(pbx "objects.$APP_TARGET.packageProductDependencies" || echo 0)" = "1" ] || die "The AudioPeek target's package products changed. $MIRROR_HINT"
SPARKLE_PRODUCT="$(pbx "objects.$APP_TARGET.packageProductDependencies.0")"
[ "$(pbx "objects.$SPARKLE_PRODUCT.productName")" = "Sparkle" ] &&
    [ "$(pbx "objects.$SPARKLE_PRODUCT.package")" = "$SPARKLE_PACKAGE" ] ||
    die "The AudioPeek target uses a package product other than Sparkle. $MIRROR_HINT"

# Build phases: only the standard three. Sources and Resources are empty (the synchronized
# folder supplies the files); Frameworks links Sparkle and nothing else.
phase_count="$(pbx "objects.$APP_TARGET.buildPhases")"
i=0
while [ "$i" -lt "$phase_count" ]; do
    phase="$(pbx "objects.$APP_TARGET.buildPhases.$i")"
    case "$(pbx "objects.$phase.isa")" in
        PBXFrameworksBuildPhase)
            [ "$(pbx "objects.$phase.files")" = "1" ] &&
                [ "$(pbx "objects.$(pbx "objects.$phase.files.0").productRef")" = "$SPARKLE_PRODUCT" ] ||
                die "The AudioPeek target links something other than Sparkle. $MIRROR_HINT"
            ;;
        PBXSourcesBuildPhase | PBXResourcesBuildPhase)
            [ "$(pbx "objects.$phase.files")" = "0" ] || die "A build phase of the AudioPeek target lists files. $MIRROR_HINT"
            ;;
        *) die "The AudioPeek target has a new kind of build phase. $MIRROR_HINT" ;;
    esac
    i=$((i + 1))
done

# The synchronized AudioPeek folder: the only file left out of the target is Info.plist.
[ "$(pbx "objects.$APP_TARGET.fileSystemSynchronizedGroups")" = "1" ] || die "The AudioPeek target has a new source folder. $MIRROR_HINT"
GROUP="$(pbx "objects.$APP_TARGET.fileSystemSynchronizedGroups.0")"
[ "$(pbx "objects.$GROUP.path")" = "AudioPeek" ] || die "The AudioPeek target's source folder moved. $MIRROR_HINT"
exception_count="$(pbx "objects.$GROUP.exceptions" || echo 0)"
i=0
while [ "$i" -lt "$exception_count" ]; do
    exception="$(pbx "objects.$GROUP.exceptions.$i")"
    if [ "$(pbx "objects.$exception.membershipExceptions")" != "1" ] ||
        [ "$(pbx "objects.$exception.membershipExceptions.0")" != "Info.plist" ]; then
        die "The AudioPeek target leaves out a new file. $MIRROR_HINT"
    fi
    i=$((i + 1))
done

# Resources: the source folder holds only Swift files, Info.plist and the app icon.
extra_files="$(cd "$SOURCE_DIR" && find . -type f ! -name '*.swift' ! -name '.DS_Store' \
    ! -path './Info.plist' ! -path './Assets.xcassets/Contents.json' \
    ! -path './Assets.xcassets/AppIcon.appiconset/*')"
[ -z "$extra_files" ] || die "New resource files in AudioPeek/ ($(echo "$extra_files" | tr '\n' ' ')). $MIRROR_HINT"

STEP="getting Sparkle $SPARKLE_VERSION"
SPARKLE_UNPACKED="$("$ROOT/Scripts/fetch-sparkle.sh" "$SPARKLE_VERSION")" || die "Couldn't get Sparkle $SPARKLE_VERSION."
SPARKLE_FRAMEWORKS="$SPARKLE_UNPACKED/Sparkle.xcframework/macos-arm64_x86_64"
[ -d "$SPARKLE_FRAMEWORKS/Sparkle.framework" ] || die "The Sparkle $SPARKLE_VERSION download has no macOS framework."

STEP="compiling"
SOURCES=()
while IFS= read -r file; do
    SOURCES+=("$file")
done < <(find "$SOURCE_DIR" -name '*.swift' -type f | LC_ALL=C sort)
[ "${#SOURCES[@]}" -gt 0 ] || die "No Swift files found in AudioPeek/."

FLAG_WORDS=()
for flag in "${SWIFT_FLAGS[@]}"; do
    # Each entry is one flag or a flag and its value; none contain spaces inside a word.
    for word in $flag; do
        FLAG_WORDS+=("$word")
    done
done

mkdir -p "$WORK/ModuleCache"
rm -f "$WORK/$PRODUCT_NAME"
echo "Compiling ${#SOURCES[@]} Swift files with the macOS $SDK_VERSION SDK..."
SDKROOT="$SDK_PATH" xcrun swiftc \
    -sdk "$SDK_PATH" \
    -target "arm64-apple-macos$MIN_MACOS" \
    -O -whole-module-optimization \
    -module-name "$PRODUCT_NAME" \
    -module-cache-path "$WORK/ModuleCache" \
    -F "$SPARKLE_FRAMEWORKS" -framework Sparkle \
    -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
    "${FLAG_WORDS[@]}" \
    "${SOURCES[@]}" \
    -o "$WORK/$PRODUCT_NAME"

STEP="assembling the app"
rm -rf "$STAGE"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"
cp "$WORK/$PRODUCT_NAME" "$STAGE/Contents/MacOS/$PRODUCT_NAME"
printf 'APPL????' > "$STAGE/Contents/PkgInfo"

# Info.plist: fill in the Xcode variables, then add the keys Xcode adds itself.
PLIST="$STAGE/Contents/Info.plist"
sed -e "s/\$(EXECUTABLE_NAME)/$PRODUCT_NAME/g" \
    -e "s/\$(PRODUCT_BUNDLE_IDENTIFIER)/$BUNDLE_ID/g" \
    -e "s/\$(MARKETING_VERSION)/$MARKETING_VERSION/g" \
    -e "s/\$(CURRENT_PROJECT_VERSION)/$BUILD_NUMBER/g" \
    -e "s/\$(MACOSX_DEPLOYMENT_TARGET)/$MIN_MACOS/g" \
    "$SOURCE_DIR/Info.plist" > "$PLIST"
if grep -q '\$(' "$PLIST"; then
    die "Info.plist uses an Xcode variable this script doesn't fill in: $(grep -o '\$([A-Z_]*)' "$PLIST" | sort -u | tr '\n' ' '). Mirror it in Scripts/build-app.sh."
fi
plutil -replace CFBundleIconFile -string AppIcon "$PLIST"
plutil -replace CFBundleSupportedPlatforms -json '["MacOSX"]' "$PLIST"
plutil -lint "$PLIST" > /dev/null

STEP="making the app icon"
ICONSET="$WORK/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
cp "$ICONSET_SOURCE"/*.png "$ICONSET/"
iconutil -c icns "$ICONSET" -o "$STAGE/Contents/Resources/AppIcon.icns"

STEP="embedding Sparkle"
mkdir -p "$STAGE/Contents/Frameworks"
ditto "$SPARKLE_FRAMEWORKS/Sparkle.framework" "$STAGE/Contents/Frameworks/Sparkle.framework"
# Xcode leaves headers and module maps out of embedded frameworks; so does this.
for part in Headers Modules PrivateHeaders; do
    rm -rf "$STAGE/Contents/Frameworks/Sparkle.framework/$part" \
        "$STAGE/Contents/Frameworks/Sparkle.framework/Versions/B/$part"
done
EMBEDDED_SPARKLE="$(plutil -extract CFBundleShortVersionString raw -o - \
    "$STAGE/Contents/Frameworks/Sparkle.framework/Resources/Info.plist" 2>/dev/null)" || EMBEDDED_SPARKLE=""
[ "$EMBEDDED_SPARKLE" = "$SPARKLE_VERSION" ] || die "The embedded Sparkle is '$EMBEDDED_SPARKLE', not $SPARKLE_VERSION."

STEP="signing"
# The same as Xcode's embed step: Sparkle's helpers ship ad-hoc signed, so only the
# framework is re-signed, keeping its identifier, entitlements and flags.
codesign --force --sign - --preserve-metadata=identifier,entitlements,flags \
    --generate-entitlement-der --strip-disallowed-xattrs \
    "$STAGE/Contents/Frameworks/Sparkle.framework/Versions/B"
codesign --force --sign - "$STAGE"
codesign --verify --deep --strict "$STAGE"

STEP="checking the built app"
BINARY="$STAGE/Contents/MacOS/$PRODUCT_NAME"
LOAD_COMMANDS="$(xcrun otool -l "$BINARY" 2>/dev/null)"
RECORDED_SDK="$(echo "$LOAD_COMMANDS" | awk '/LC_BUILD_VERSION/{f=1} f&&$1=="sdk"{print $2;exit}')"
RECORDED_MIN="$(echo "$LOAD_COMMANDS" | awk '/LC_BUILD_VERSION/{f=1} f&&$1=="minos"{print $2;exit}')"
if [ "$(normalize_version "$RECORDED_SDK")" != "$(normalize_version "$SDK_VERSION")" ]; then
    die "The app records SDK '$RECORDED_SDK' instead of $SDK_VERSION, so macOS would draw it like an older app."
fi
if [ "$(normalize_version "$RECORDED_MIN")" != "$(normalize_version "$MIN_MACOS")" ]; then
    die "The app records minimum macOS '$RECORDED_MIN' instead of $MIN_MACOS."
fi

STEP="moving the app into build/"
if pgrep -f "$OUT/Contents/MacOS/" > /dev/null 2>&1; then
    echo "Note: an older build/AudioPeek.app is running. Quit and reopen it to use the new build."
fi
rm -rf "$OUT"
mv "$STAGE" "$OUT"

trap - ERR
echo ""
echo "Built build/AudioPeek.app (version $MARKETING_VERSION, build $BUILD_NUMBER, macOS $SDK_VERSION SDK, Sparkle $SPARKLE_VERSION)."
echo "Drag it into Applications, replacing any other copy, then open it."

#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repository_root="$(cd "$script_dir/.." && pwd)"
dist_directory="${OPENMAC_DIST_DIR:-$repository_root/dist}"
launch_smoke=0
allow_dirty="${OPENMAC_ALLOW_DIRTY:-0}"

if [[ "${1:-}" == "--launch-smoke" ]]; then
    launch_smoke=1
elif [[ $# -gt 0 ]]; then
    echo "Usage: $0 [--launch-smoke]" >&2
    exit 64
fi

temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/openmac-test-build.XXXXXX")"
cleanup() {
    rm -rf "$temporary_root"
}
trap cleanup EXIT

derived_data="$temporary_root/DerivedData"
build_settings="$temporary_root/build-settings.txt"

cd "$repository_root"
source_tree_dirty=false
if [[ -n "$(git status --porcelain --untracked-files=normal)" ]]; then
    source_tree_dirty=true
fi
if [[ "$source_tree_dirty" == "true" && "$allow_dirty" != "1" ]]; then
    echo "Refusing to package a dirty source tree." >&2
    echo "Commit the intended build state, or set OPENMAC_ALLOW_DIRTY=1 for local verification." >&2
    exit 1
fi

xcodebuild \
    -project OpenMac.xcodeproj \
    -scheme OpenMac \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -showBuildSettings > "$build_settings"

version="$(
    awk -F ' = ' '/^[[:space:]]*MARKETING_VERSION = / { print $2; exit }' \
        "$build_settings"
)"
build_number="$(
    awk -F ' = ' '/^[[:space:]]*CURRENT_PROJECT_VERSION = / { print $2; exit }' \
        "$build_settings"
)"

if [[ -z "$version" || -z "$build_number" ]]; then
    echo "Could not resolve OpenMac version settings." >&2
    exit 1
fi

package_name="OpenMac-${version}-test.${build_number}-macOS"
if [[ "$source_tree_dirty" == "true" ]]; then
    package_name="$package_name-dirty"
fi
package_directory="$temporary_root/$package_name"
archive_path="$dist_directory/$package_name.zip"
checksum_path="$archive_path.sha256"

xcodebuild build \
    -project OpenMac.xcodeproj \
    -scheme OpenMac \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -derivedDataPath "$derived_data" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    MACOSX_DEPLOYMENT_TARGET=14.0 \
    SWIFT_ACTIVE_COMPILATION_CONDITIONS=OPENMAC_DELIVERY_V2 \
    >/dev/null

built_app="$derived_data/Build/Products/Release/OpenMac.app"
if [[ ! -d "$built_app" ]]; then
    echo "Release build did not produce OpenMac.app." >&2
    exit 1
fi

mkdir -p "$package_directory"
ditto "$built_app" "$package_directory/OpenMac.app"
cp "$repository_root/LICENSE" "$package_directory/LICENSE.txt"
cp \
    "$repository_root/docs/v2/TEST_BUILD_INSTALL.md" \
    "$package_directory/INSTALL.md"

commit_identifier="$(git rev-parse HEAD)"
build_timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
cat > "$package_directory/BUILD-INFO.json" <<EOF
{
  "build": "$build_number",
  "commit": "$commit_identifier",
  "minimumMacOS": "14.0",
  "notarized": false,
  "signature": "ad-hoc",
  "sourceTreeDirty": $source_tree_dirty,
  "testFeatureFlag": "OPENMAC_DELIVERY_V2",
  "timestamp": "$build_timestamp",
  "version": "$version"
}
EOF

codesign \
    --force \
    --deep \
    --sign - \
    --options runtime \
    --timestamp=none \
    "$package_directory/OpenMac.app"
codesign \
    --verify \
    --deep \
    --strict \
    --verbose=2 \
    "$package_directory/OpenMac.app"

app_executable="$package_directory/OpenMac.app/Contents/MacOS/OpenMac"
architectures="$(lipo -archs "$app_executable")"
if [[ "$architectures" != *"arm64"* || "$architectures" != *"x86_64"* ]]; then
    echo "Expected a universal arm64 + x86_64 executable; found: $architectures" >&2
    exit 1
fi

minimum_system="$(
    /usr/libexec/PlistBuddy \
        -c "Print :LSMinimumSystemVersion" \
        "$package_directory/OpenMac.app/Contents/Info.plist"
)"
if [[ "$minimum_system" != "14.0" ]]; then
    echo "Expected minimum macOS 14.0; found: $minimum_system" >&2
    exit 1
fi

mkdir -p "$dist_directory"
rm -f "$archive_path" "$checksum_path"
ditto \
    -c \
    -k \
    --sequesterRsrc \
    --keepParent \
    "$package_directory" \
    "$archive_path"

verification_directory="$temporary_root/verification"
mkdir -p "$verification_directory"
ditto -x -k "$archive_path" "$verification_directory"
verified_app="$verification_directory/$package_name/OpenMac.app"
codesign --verify --deep --strict --verbose=2 "$verified_app"

verified_architectures="$(
    lipo -archs "$verified_app/Contents/MacOS/OpenMac"
)"
if [[ "$verified_architectures" != "$architectures" ]]; then
    echo "Archive architecture verification failed." >&2
    exit 1
fi

if [[ "$launch_smoke" -eq 1 ]]; then
    smoke_log="$temporary_root/launch-smoke.log"
    LLVM_PROFILE_FILE="$temporary_root/openmac-launch-%p.profraw" \
        "$verified_app/Contents/MacOS/OpenMac" \
        -ApplePersistenceIgnoreState YES \
        >"$smoke_log" 2>&1 &
    application_pid=$!
    sleep 3
    if ! kill -0 "$application_pid" 2>/dev/null; then
        echo "OpenMac exited during launch smoke:" >&2
        sed -n '1,120p' "$smoke_log" >&2
        exit 1
    fi
    kill "$application_pid"
    wait "$application_pid" 2>/dev/null || true
fi

(
    cd "$dist_directory"
    shasum -a 256 "$(basename "$archive_path")" \
        > "$(basename "$checksum_path")"
)

echo "Created test build:"
echo "  $archive_path"
echo "  $checksum_path"
echo "  version $version ($build_number), macOS 14.0+, $architectures"
echo "  ad-hoc signed, not notarized"

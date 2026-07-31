#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repository_root="$(cd "$script_dir/.." && pwd)"
base_url="${OPENMAC_AO_LIVE_URL:-http://127.0.0.1:3001}"
project_id=""
harness="fake"
base_branch=""
base_commit=""

usage() {
    echo "Usage: $0 [--url URL]"
    echo "       $0 --start-project ID --harness NAME \\"
    echo "          --base-branch BRANCH --base-commit SHA [--url URL]"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --url)
            base_url="${2:-}"
            shift 2
            ;;
        --start-project)
            project_id="${2:-}"
            shift 2
            ;;
        --harness)
            harness="${2:-}"
            shift 2
            ;;
        --base-branch)
            base_branch="${2:-}"
            shift 2
            ;;
        --base-commit)
            base_commit="${2:-}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            usage >&2
            exit 64
            ;;
    esac
done

if [[ -n "$project_id" ]] \
    && [[ -z "$base_branch" || -z "$base_commit" ]]; then
    echo "--start-project requires --base-branch and --base-commit." >&2
    exit 64
fi

temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/openmac-ao-live.XXXXXX")"
cleanup() {
    rm -rf "$temporary_root"
}
trap cleanup EXIT

derived_data="$temporary_root/DerivedData"

cd "$repository_root"
xcodebuild build-for-testing \
    -project OpenMac.xcodeproj \
    -scheme OpenMac \
    -configuration Debug \
    -destination "platform=macOS" \
    -derivedDataPath "$derived_data" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    MACOSX_DEPLOYMENT_TARGET=14.0 \
    >/dev/null

test_bundle="$derived_data/Build/Products/Debug/OpenMac.app/Contents/PlugIns/OpenMacTests.xctest"
frameworks_directory="$test_bundle/Contents/Frameworks"
if [[ ! -d "$test_bundle" ]]; then
    echo "The OpenMacTests bundle was not produced." >&2
    exit 1
fi

mkdir -p "$frameworks_directory"
ln -sf \
    ../../../../MacOS/OpenMac.debug.dylib \
    "$frameworks_directory/OpenMac.debug.dylib"

export OPENMAC_AO_LIVE_URL="$base_url"
export OPENMAC_AO_LIVE_HARNESS="$harness"
export LLVM_PROFILE_FILE="$temporary_root/openmac-ao-live-%p.profraw"
unset OPENMAC_AO_LIVE_PROJECT_ID
unset OPENMAC_AO_LIVE_BASE_BRANCH
unset OPENMAC_AO_LIVE_BASE_COMMIT
if [[ -n "$project_id" ]]; then
    export OPENMAC_AO_LIVE_PROJECT_ID="$project_id"
    export OPENMAC_AO_LIVE_BASE_BRANCH="$base_branch"
    export OPENMAC_AO_LIVE_BASE_COMMIT="$base_commit"
    echo "Authorized live AO session start for project $project_id."
else
    echo "Running read-only AO health, readiness, and project discovery smoke."
fi

xcrun xctest \
    -XCTest OpenMacTests.AgentOrchestratorLiveSmokeTests \
    "$test_bundle"

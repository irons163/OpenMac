#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repository_root="$(cd "$script_dir/.." && pwd)"
dashboard_url="${OPENMAC_AO_DASHBOARD_URL:-http://127.0.0.1:3000}"
project_id="${OPENMAC_AO_DASHBOARD_PROJECT_ID:-openmac-ao-fixture}"
session_id="${OPENMAC_AO_DASHBOARD_SESSION_ID:-}"

usage() {
    echo "Usage: $0 [--url URL] [--project-id PROJECT_ID] [--session-id SESSION_ID]"
    echo
    echo "The URL must serve the AO web renderer and be loopback-only."
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --url)
            dashboard_url="${2:-}"
            shift 2
            ;;
        --project-id)
            project_id="${2:-}"
            shift 2
            ;;
        --session-id)
            session_id="${2:-}"
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

if [[ -z "$dashboard_url" || -z "$project_id" ]]; then
    usage >&2
    exit 64
fi

cd "$repository_root"
export OPENMAC_AO_DASHBOARD_URL="$dashboard_url"
export OPENMAC_AO_DASHBOARD_PROJECT_ID="$project_id"
if [[ -n "$session_id" ]]; then
    export OPENMAC_AO_DASHBOARD_SESSION_ID="$session_id"
else
    unset OPENMAC_AO_DASHBOARD_SESSION_ID
fi

echo "Verifying AO dashboard HTML at $dashboard_url for project $project_id."
if [[ -n "$session_id" ]]; then
    echo "Also verifying session route for $session_id."
fi
temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/openmac-ao-dashboard.XXXXXX")"
cleanup() {
    rm -rf "$temporary_root"
}
trap cleanup EXIT

derived_data="$temporary_root/DerivedData"
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

xcrun xctest \
    -XCTest OpenMacTests.AgentOrchestratorDashboardLiveTests \
    "$test_bundle"

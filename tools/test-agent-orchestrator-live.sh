#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repository_root="$(cd "$script_dir/.." && pwd)"
base_url="${OPENMAC_AO_LIVE_URL:-http://127.0.0.1:3001}"
project_id=""
harness="fake"
base_branch=""
base_commit=""
xcode_repository_root=""
xcode_scheme="OpenMacAOFixture"
xcode_workspace_root=""
pr_url=""

usage() {
    echo "Usage: $0 [--url URL]"
    echo "       $0 --start-project ID --harness NAME --base-branch BRANCH --base-commit SHA [--url URL]"
    echo "       $0 --start-project ID --base-branch BRANCH --base-commit SHA --xcode-repository-root PATH [--xcode-scheme SCHEME] [--xcode-workspace-root PATH]"
    echo "       $0 --start-project ID --base-branch BRANCH --base-commit SHA --pr-url GITHUB_PR_URL"
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
        --xcode-repository-root)
            xcode_repository_root="${2:-}"
            shift 2
            ;;
        --xcode-scheme)
            xcode_scheme="${2:-}"
            shift 2
            ;;
        --xcode-workspace-root)
            xcode_workspace_root="${2:-}"
            shift 2
            ;;
        --pr-url)
            pr_url="${2:-}"
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

if [[ -n "$xcode_repository_root" ]]; then
    if [[ -z "$project_id" ]]; then
        echo "--xcode-repository-root requires --start-project." >&2
        exit 64
    fi
    if [[ ! -d "$xcode_repository_root" ]]; then
        echo "The Xcode repository root is not a directory: $xcode_repository_root" >&2
        exit 64
    fi
    if [[ -z "$xcode_scheme" ]]; then
        echo "--xcode-scheme must not be empty." >&2
        exit 64
    fi
fi

if [[ -n "$xcode_workspace_root" && -z "$xcode_repository_root" ]]; then
    echo "--xcode-workspace-root requires --xcode-repository-root." >&2
    exit 64
fi

if [[ -n "$xcode_workspace_root" && ! -d "$xcode_workspace_root" ]]; then
    echo "The AO workspace root is not a directory: $xcode_workspace_root" >&2
    exit 64
fi

if [[ -n "$pr_url" && -z "$project_id" ]]; then
    echo "--pr-url requires --start-project." >&2
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
unset OPENMAC_AO_LIVE_XCODE
unset OPENMAC_AO_LIVE_REPOSITORY_ROOT
unset OPENMAC_AO_LIVE_XCODE_SCHEME
unset OPENMAC_AO_LIVE_WORKSPACE_ROOT
unset OPENMAC_AO_LIVE_PR_URL
if [[ -n "$project_id" ]]; then
    export OPENMAC_AO_LIVE_PROJECT_ID="$project_id"
    export OPENMAC_AO_LIVE_BASE_BRANCH="$base_branch"
    export OPENMAC_AO_LIVE_BASE_COMMIT="$base_commit"
    echo "Authorized live AO session start for project $project_id."
else
    echo "Running read-only AO health, readiness, and project discovery smoke."
fi

if [[ -n "$xcode_repository_root" ]]; then
    export OPENMAC_AO_LIVE_XCODE=1
    export OPENMAC_AO_LIVE_REPOSITORY_ROOT="$xcode_repository_root"
    export OPENMAC_AO_LIVE_XCODE_SCHEME="$xcode_scheme"
    if [[ -n "$xcode_workspace_root" ]]; then
        export OPENMAC_AO_LIVE_WORKSPACE_ROOT="$xcode_workspace_root"
    fi
    echo "Authorized live Xcode verification for $xcode_repository_root ($xcode_scheme)."
fi

if [[ -n "$pr_url" ]]; then
    export OPENMAC_AO_LIVE_PR_URL="$pr_url"
    echo "Authorized live PR facts verification for $pr_url."
fi

xcrun xctest \
    -XCTest OpenMacTests.AgentOrchestratorLiveSmokeTests \
    "$test_bundle"

#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repository_root="$(cd "$script_dir/.." && pwd)"
archive_path="${1:-$repository_root/dist/OpenMac-0.1.0-test.3-macOS.zip}"

if [[ ! -f "$archive_path" ]]; then
    echo "Packaged OpenMac archive was not found: $archive_path" >&2
    echo "Run tools/package-test-build.sh --launch-smoke first." >&2
    exit 1
fi

temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/openmac-packaged-restart.XXXXXX")"
first_pid=""
second_pid=""
cleanup() {
    for process_id in "$second_pid" "$first_pid"; do
        if [[ -n "$process_id" ]] && kill -0 "$process_id" 2>/dev/null; then
            kill -TERM "$process_id" 2>/dev/null || true
            wait "$process_id" 2>/dev/null || true
        fi
    done
    rm -rf "$temporary_root"
}
trap cleanup EXIT

verification_directory="$temporary_root/verification"
mkdir -p "$verification_directory"
ditto -x -k "$archive_path" "$verification_directory"

package_directory="$(find "$verification_directory" -mindepth 1 -maxdepth 1 -type d -name 'OpenMac-*-macOS' -print -quit)"
if [[ -z "$package_directory" ]]; then
    echo "The archive did not contain an OpenMac test package directory." >&2
    exit 1
fi
app_executable="$package_directory/OpenMac.app/Contents/MacOS/OpenMac"
if [[ ! -x "$app_executable" ]]; then
    echo "The packaged OpenMac executable was not found: $app_executable" >&2
    exit 1
fi

wait_for_process() {
    local process_id="$1"
    local label="$2"
    for _ in {1..30}; do
        if kill -0 "$process_id" 2>/dev/null; then
            return 0
        fi
        sleep 0.2
    done
    echo "Packaged OpenMac exited during $label smoke." >&2
    return 1
}

stop_process() {
    local process_id="$1"
    kill -TERM "$process_id" 2>/dev/null || true
    for _ in {1..50}; do
        if ! kill -0 "$process_id" 2>/dev/null; then
            wait "$process_id" 2>/dev/null || true
            return 0
        fi
        sleep 0.2
    done
    # A short-lived macOS app can be a zombie until its parent reaps it, so
    # kill -0 alone is not a reliable termination check. Reap the child after
    # the grace period; if it is still running, force-stop only this process
    # that the smoke itself started.
    kill -KILL "$process_id" 2>/dev/null || true
    wait "$process_id" 2>/dev/null || true
    if kill -0 "$process_id" 2>/dev/null; then
        echo "Packaged OpenMac did not terminate (pid $process_id)." >&2
        return 1
    fi
}

LLVM_PROFILE_FILE="$temporary_root/openmac-packaged-restart-%p.profraw" \
    "$app_executable" \
    -ApplePersistenceIgnoreState YES \
    -ui-testing \
    >"$temporary_root/first-launch.log" 2>&1 &
first_pid=$!
wait_for_process "$first_pid" "first-launch"
stop_process "$first_pid"
first_pid=""

LLVM_PROFILE_FILE="$temporary_root/openmac-packaged-restart-%p.profraw" \
    "$app_executable" \
    -ApplePersistenceIgnoreState YES \
    -ui-testing \
    >"$temporary_root/second-launch.log" 2>&1 &
second_pid=$!
wait_for_process "$second_pid" "restart"
stop_process "$second_pid"
second_pid=""

echo "Packaged OpenMac restart smoke passed: launch, terminate, relaunch, terminate."

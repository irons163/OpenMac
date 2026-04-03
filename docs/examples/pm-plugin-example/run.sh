#!/bin/zsh
set -eu

SCRIPT_DIR=${0:A:h}
exec python3 "$SCRIPT_DIR/run.py"

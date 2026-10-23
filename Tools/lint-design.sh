#!/usr/bin/env bash
# Design-system lint: fails if a view writes a raw value instead of a token or component.
# Usage: Tools/lint-design.sh [--quiet] [files…]   Rules in Tools/lint-design.py and docs/DESIGN_SYSTEM.md.
set -euo pipefail
cd "$(dirname "$0")/.."
exec python3 Tools/lint-design.py "$@"

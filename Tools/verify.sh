#!/usr/bin/env bash
# The one verification command: package tests + app build.
# Usage: Tools/verify.sh [package|app]   (no args = both)
set -euo pipefail
cd "$(dirname "$0")/.."
mode="${1:-all}"
# Design-system lint first: it takes a second and catches raw values before a long build.
Tools/lint-design.sh --quiet
if [[ "$mode" == all || "$mode" == package ]]; then
  (cd Packages/CentavoCore && swift test)
fi
if [[ "$mode" == all || "$mode" == app ]]; then
  # At most 2 builds on the Mac, counting every session; one folder for every session of this
  # project, so a build picks up what the last one compiled.
  while [[ "$(pgrep -x xcodebuild | wc -l)" -ge 2 ]]; do echo "Esperando a que termine otro build…"; sleep 30; done
  xcodegen generate -q
  xcodebuild -project Centavo.xcodeproj -scheme Centavo -destination 'generic/platform=iOS' \
    -derivedDataPath "${CENTAVO_DERIVED_DATA:-/tmp/dd-centavo}" CODE_SIGNING_ALLOWED=NO -jobs 4 -quiet build
fi
echo "verify: OK"

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
  log="$(mktemp -t centavo-verify)"
  xcodebuild -project Centavo.xcodeproj -scheme Centavo -destination 'generic/platform=iOS' \
    -derivedDataPath "${CENTAVO_DERIVED_DATA:-/tmp/dd-centavo}" CODE_SIGNING_ALLOWED=NO -jobs 4 -quiet build 2>&1 | tee "$log"
  # An expression the Mac type-checks slowly is one the CI's older compiler gives up on
  # (project.yml, OTHER_SWIFT_FLAGS): split it into stages before pushing.
  if grep -q "to type-check (limit" "$log"; then
    echo "verify: una expresión tarda demasiado en revisarse de tipo; pártela en etapas (la CI no la compila):"
    grep -B3 "to type-check (limit" "$log" | grep -E "\.swift:[0-9]+" | sort -u
    rm -f "$log"; exit 1
  fi
  rm -f "$log"
  # The tests too: they are compiled only when they run, so one that no longer builds was found
  # out by the CI (2026-11-11).
  xcodebuild build-for-testing -project Centavo.xcodeproj -scheme Centavo \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "${CENTAVO_DERIVED_DATA:-/tmp/dd-centavo}" CODE_SIGNING_ALLOWED=NO -jobs 4 -quiet
fi
echo "verify: OK"

#!/bin/bash
# Stamps the built app (and its widget) with the build number and the commit, so the owner can
# tell in «Ajustes» whether the iPhone has the latest: CFBundleVersion = commits on the branch,
# CentavoCommit = the short hash («+» when built with changes not committed yet).
# Run by Xcode after the build (project.yml, postBuildScripts); needs no arguments.
set -euo pipefail
cd "$SRCROOT"
count=$(git rev-list --count HEAD 2>/dev/null || echo 0)
hash=$(git rev-parse --short HEAD 2>/dev/null || echo local)
if [ -n "$(git status --porcelain 2>/dev/null)" ]; then hash="$hash+"; fi
plist="$TARGET_BUILD_DIR/$INFOPLIST_PATH"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $count" "$plist"
/usr/libexec/PlistBuddy -c "Delete :CentavoCommit" "$plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CentavoCommit string $hash" "$plist"

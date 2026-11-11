#!/usr/bin/env bash
# Installs Al día on the owner's iPhone as the app a person gets: the Release build (optimized,
# symbols stripped), signed with the free developer account (no iCloud: CentavoGratis.entitlements).
# The Debug build that the Mac compiles all day is five times heavier and not optimized.
#
# Usage: Tools/instalar.sh            (the iPhone connected and unlocked)
#        CENTAVO_IPHONE=<udid> CENTAVO_TEAM=<team> Tools/instalar.sh
# The free account's signature lasts 7 days: run it again to renew it.
set -euo pipefail
cd "$(dirname "$0")/.."
iphone="${CENTAVO_IPHONE:-00008150-000145922192401C}"
team="${CENTAVO_TEAM:-B7KRCF776Z}"
data="${CENTAVO_DEVICE_DERIVED_DATA:-/tmp/dd-centavo-device}"

# At most 2 builds on the Mac, counting every session.
while [[ "$(pgrep -x xcodebuild | wc -l)" -ge 2 ]]; do echo "Esperando a que termine otro build…"; sleep 30; done
xcodegen generate -q
xcodebuild -project Centavo.xcodeproj -scheme Centavo -configuration Release \
  -destination "id=$iphone" -derivedDataPath "$data" -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$team" CODE_SIGN_ENTITLEMENTS=Centavo/CentavoGratis.entitlements \
  DEPLOYMENT_POSTPROCESSING=YES -jobs 4 -quiet build
app="$data/Build/Products/Release-iphoneos/Centavo.app"
echo "Peso: $(du -sh "$app" | cut -f1)"
xcrun devicectl device install app --device "$iphone" "$app"
echo "instalar: OK ($(/usr/libexec/PlistBuddy -c 'Print :CentavoCommit' "$app/Info.plist"))"

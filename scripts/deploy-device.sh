#!/usr/bin/env bash
# Builds SkyRay for a real iPhone with automatic signing, installs it and launches it. The Apple ID signed in to
# Xcode (Settings → Accounts) must belong to team SG5BT8WSLT. Arguments after the script name go to the app:
#   scripts/deploy-device.sh -ImportLink 'https://fra.skyrayconfig.org/sub/…' -AutoConnect YES
#   scripts/deploy-device.sh -Disconnect YES
# The phone: DEVICE="<its name>" (see `xcrun devicectl list devices`), else the first one listed. docs/device-testing.md.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/_device.sh
DEVICE_NAME=$(resolve_device)
[ -n "$DEVICE_NAME" ] || { echo "no iPhone found: plug one in and trust the Mac, or set DEVICE=<name>"; exit 1; }
scripts/fetch-libxray.sh
scripts/fetch-hev.sh
xcodegen generate >/dev/null
mkdir -p build
set -o pipefail
xcodebuild -project SkyRay.xcodeproj -scheme SkyRay -configuration Debug -destination "platform=iOS,name=$DEVICE_NAME" \
  -derivedDataPath build/DerivedData -allowProvisioningUpdates -allowProvisioningDeviceRegistration build 2>&1 \
  | tee build/device-build.log | grep -E "error:|warning: .*sign|BUILD (SUCCEEDED|FAILED)" || true
grep -q "BUILD SUCCEEDED" build/device-build.log || { echo "the build failed: build/device-build.log has the details"; exit 1; }
APP=build/DerivedData/Build/Products/Debug-iphoneos/SkyRay.app
xcrun devicectl device install app --device "$DEVICE_NAME" "$APP"
xcrun devicectl device process launch --terminate-existing --device "$DEVICE_NAME" com.allion.skyray -- "$@"
echo "DEPLOYED to $DEVICE_NAME"

#!/usr/bin/env bash
# Copies the app's logs (app, tunnel, xray) from the iPhone into build/device-logs/ and prints the tunnel's tail.
# Development builds mirror the logs into the app's Documents folder for this. DEVICE="<name>" picks the phone.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/_device.sh
DEVICE_NAME=$(resolve_device)
[ -n "$DEVICE_NAME" ] || { echo "no iPhone found"; exit 1; }
mkdir -p build/device-logs
for f in app.log tunnel.log xray.log; do
  rm -f "build/device-logs/$f"
  xcrun devicectl device copy from --device "$DEVICE_NAME" --source "Documents/logs/$f" --destination "build/device-logs/$f" \
    --domain-type appDataContainer --domain-identifier com.allion.skyray >/dev/null 2>&1 || echo "$f: not on the phone yet"
done
echo "=== tunnel.log (tail) ==="; tail -n 60 build/device-logs/tunnel.log 2>/dev/null || true
echo "=== app.log (tail) ==="; tail -n 30 build/device-logs/app.log 2>/dev/null || true
echo "=== xray.log (tail) ==="; tail -n 30 build/device-logs/xray.log 2>/dev/null || true

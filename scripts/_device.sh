# Sourced by the device scripts: picks the iPhone. DEVICE=<name or identifier> wins; else the first device
# `xcrun devicectl list devices` knows (plugged in and trusted, or paired over Wi-Fi).
resolve_device() {
  if [ -n "${DEVICE:-}" ]; then echo "$DEVICE"; return; fi
  mkdir -p build
  xcrun devicectl list devices --json-output build/devices.json >/dev/null 2>&1 || true
  python3 - <<'PY' 2>/dev/null
import json
d = json.load(open("build/devices.json"))
devices = d.get("result", {}).get("devices", [])
for dev in devices:
    name = dev.get("deviceProperties", {}).get("name") or dev.get("identifier")
    if name:
        print(name); break
PY
}

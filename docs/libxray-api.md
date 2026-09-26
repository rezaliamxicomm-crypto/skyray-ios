# libXray v26.9.9 — what SkyRay uses (snapshot of the release README)

`LibXray.xcframework` (static, module `LibXray`, header `libXray.h`): `char* CGoInvoke(char* requestJSON)` and
`void CGoFree(char* value)`; every non-null response must be freed with `CGoFree`. Slices: ios-arm64,
ios-arm64_x86_64-simulator, macos-arm64_x86_64, tvos. Minimum iOS 15.0. One Go runtime per process.

Request `{"apiVersion": 3, "method": "<name>", "payload": {…}}` → response `{"success": bool, "data": …, "error": ""}`.
Envelopes are limited to 16 MiB. A top-level `env` in the request is ignored: Xray runtime env (the utun fd
`xray.tun.fd` / `XRAY_TUN_FD`, `XRAY_LOCATION_ASSET`) goes into the **Xray config's root `env` object**.

| method | payload | data |
|---|---|---|
| `runXray` | `{"xrayJson": "<config JSON text>"}` | `{}` — the managed instance; `stopXray` stops it |
| `stopXray` | – | `{}` |
| `xrayVersion` | – | the core version |
| `getXrayState` | – | state of the managed instance |
| `getFreePorts` | `{"count": n, "excludePorts": [...]}` | `{"ports": [...]}` (candidates, not reservations; TCP only) |
| `convertShareLinksToXrayJson` | `{"text": "<links or base64 body>", "age": {"secretKey": …}?}` | `{"outbounds": [...]}` (source order, invalid ones skipped; XHTTP `extra` kept) |
| `pingBatch` | `{"configs": [{"xrayJson": …, "outboundTag": "proxy"}…] (≤ 5), "timeout": s, "url": …}` | one result per config, `delay` ms: 10000 = error, 11000 = timeout; refuses while `runXray` is active in the same process |
| `testXray` | `{"xrayJson": …}` | `{}` — builds and closes a temporary instance |

Memory: on iOS a GC runs once a second. `SetDNS`/`ResetDNS` exist only in the Android artifact.

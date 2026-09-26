# SkyRay for iOS

The iPhone client of the EthaVPN service — the counterpart of [SkyRay for Android](https://github.com/rezaliamxicomm-crypto/ethavpn-app).
A native SwiftUI app on [Xray-core](https://github.com/XTLS/Xray-core) through [libXray](https://github.com/XTLS/libXray):
the customer taps the link the Telegram bot gave them (or the app finds it on the clipboard after the
install), the app adds the account, picks the fastest line and connects. Days and data left on the home
screen; Support in the app; renewals happen in Telegram.

## Layout

- `SkyRay/` — the app (SwiftUI): `App/` entry points, `Model/` the state and the subscription pipeline,
  `Views/`, `Theme/`, `Resources/` (asset catalog, `Localizable.xcstrings` en/fa/ru, Vazirmatn).
- `SkyRayTunnel/` — the Network Extension: runs Xray on the utun file descriptor, probes the line, switches
  lines when one dies, logs its memory footprint.
- `Packages/SkyRayCore/` — pure Swift, unit-tested: link and header parsing, auto-select, server rows, the
  Xray config builder, the App Group store, app↔tunnel messages.
- `Packages/SkyRayXray/` — the libXray binary target (downloaded, not committed) and the bridge to its JSON API.
- `Config/` — Info.plist and entitlements per target. `Vendor/` — the pinned libXray release and the lite geo
  files. `scripts/` — fetch scripts and the icon painter. `ci/` — export options. `docs/` — release process,
  the libXray API snapshot, server prerequisites.

## Building

```bash
scripts/fetch-libxray.sh        # LibXray.xcframework (pinned tag + sha256 in Vendor/libxray.lock)
brew install xcodegen && xcodegen generate
open SkyRay.xcodeproj           # a real iPhone: Network Extensions do not run in the Simulator
swift test --package-path Packages/SkyRayCore
```

CI (`.github/workflows/ios.yml`) builds every push on a macOS runner and uploads tags to TestFlight. Release
process: `docs/RELEASE.md`. Server-side prerequisites (universal links, the landing page): `docs/server-prereqs.md`.

## Licences

SkyRay is MIT. Xray-core (MPL-2.0), libXray (MIT), Vazirmatn (OFL, `SkyRay/Resources/Fonts/OFL-vazirmatn.txt`),
Iran-v2ray-rules lite geo files (GPL-3.0, data). Privacy: `PRIVACY.md`.

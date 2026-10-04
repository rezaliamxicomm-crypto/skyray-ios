# SkyRay for iOS

The iPhone client of the EthaVPN service — the counterpart of [SkyRay for Android](https://github.com/rezaliamxicomm-crypto/ethavpn-app),
with the same look (Vazirmatn, the same colours, the same screens and server list). A native SwiftUI app on
[Xray-core](https://github.com/XTLS/Xray-core) through [libXray](https://github.com/XTLS/libXray), with
[hev-socks5-tunnel](https://github.com/heiher/hev-socks5-tunnel) turning the phone's packets into SOCKS5 connections
to it: the customer taps the link the Telegram bot gave them (or the app finds it on the clipboard after the install),
the app adds the account, picks the fastest line and connects. Days and data left on the home screen; Support in the
app; renewals happen in Telegram. Built for networks that filter hard: real HTTP probes through every line, the
fastest wins, a watchdog that switches lines when one dies, Iranian sites and the LAN direct, DNS through the tunnel,
QUIC blocked, and a TLS-fragment mode in the config builder for when a handshake is dropped by its SNI.

## Layout

- `SkyRay/` — the app (SwiftUI): `App/` entry points, `Model/` the state and the subscription pipeline, `Views/`,
  `Theme/` (the Android palette, Vazirmatn, Material buttons, the power glyph), `Resources/` (asset catalog,
  `Localizable.xcstrings` en/fa/ru, Vazirmatn).
- `SkyRayTunnel/` — the Network Extension (`com.allion.skyray.PacketTunnel`): runs Xray on a loopback SOCKS5 port and
  hev-socks5-tunnel on the utun file descriptor, probes the line, switches lines when one dies, logs its memory.
- `Packages/SkyRayCore/` — pure Swift, unit-tested: link and header parsing, the move of links from earlier addresses,
  auto-select, server rows, the Xray config builder, the App Group store, app↔tunnel messages, the previous app's files.
- `Packages/SkyRayXray/` — the libXray binary target (downloaded, not committed) and the bridge to its JSON API and
  to the subscription fetch compiled into it.
- `echfetch/` — the subscription fetch with Encrypted Client Hello, in Go: the same directory, file for file, as in the
  Android repository. `libxray/` — its C export. Both are compiled into LibXray (`scripts/build-libxray.sh`).
- `Packages/SkyRayHev/` — the hev-socks5-tunnel binary target (built from the pinned source release, not committed)
  and its Swift wrapper.
- `Config/` — Info.plist and entitlements per target. `Vendor/` — the pinned libXray and hev releases, the lite geo
  files. `scripts/` — the fetch/build scripts, the icon painter, the device scripts. `ci/` — export options.
  `docs/` — release process, device testing, the libXray API snapshot, server prerequisites.

## Building

```bash
scripts/fetch-libxray.sh        # LibXray.xcframework: this repository's own release (tag + sha256 in Vendor/libxray.lock)
scripts/fetch-hev.sh            # HevSocks5Tunnel.xcframework, built from the pinned source (Vendor/hev.lock)
brew install xcodegen && xcodegen generate
open SkyRay.xcodeproj           # a real iPhone: Network Extensions do not run in the Simulator
swift test --package-path Packages/SkyRayCore
```

Signing is automatic under team `SG5BT8WSLT` (ALLION LLC): an Apple ID of that team signed in to Xcode is all a
development build needs. `scripts/deploy-device.sh` builds, installs and launches on a plugged-in iPhone;
`scripts/pull-logs.sh` fetches the logs (`docs/device-testing.md`).

CI (`.github/workflows/ios.yml`) builds every push to `main` and to a `claude/…` work branch on a macOS runner (unit
tests, then both targets; unsigned until the signing secrets exist) and uploads tags to TestFlight. A failed run posts
its errors as a comment on the commit and as annotations on the check.

**The link is fetched with Encrypted Client Hello enforced** (`SubscriptionImporter` → `EchFetch` →
`LibXrayBridge.fetchSubscriptionEch`): the link host's name is not stated in the clear. Only when nobody answered that
way is the link fetched once more as before 1.3.6, by URLSession without ECH — the last resort for a network that
blocks ECH itself. The ECH key is asked over plain UDP DNS of public resolvers (the HTTPS record of the ECH
public name), or is the pinned key, which the server's retry key refreshes; the connection goes to a Cloudflare address
the app already knows, never to the host's A record. While the tunnel is up: first past it, bound to the phone's own
interface, then through it. Apple's own networking cannot be made to enforce ECH, and one process holds one Go runtime,
so the fetch is Go code inside LibXray: `.github/workflows/libxray.yml` builds XTLS/libXray at the tag in
`Vendor/libxray-source.lock` with `echfetch/` compiled in and publishes the zip as a release of this repository;
`Vendor/libxray.lock` pins that file, for CI and for an Xcode archive on a Mac alike. Release process: `docs/RELEASE.md`. Server-side prerequisites (universal links, the
landing page): `docs/server-prereqs.md`.

## Licences

SkyRay is MIT. Xray-core (MPL-2.0), libXray (MIT), hev-socks5-tunnel (MIT), Vazirmatn (OFL,
`SkyRay/Resources/Fonts/OFL-vazirmatn.txt`), Iran-v2ray-rules lite geo files (GPL-3.0, data). Privacy: `PRIVACY.md`.

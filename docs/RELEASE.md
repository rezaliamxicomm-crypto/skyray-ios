# Releasing SkyRay for iOS

## What an update depends on

Not a key. The App Store record (id 6809038308, seller ALLION LLC) belongs to Apple team `SG5BT8WSLT`; an update is any
build signed under that team with the bundle ids `com.allion.skyray` / `com.allion.skyray.PacketTunnel` and a higher
version and build number. Apple re-signs it for the store. Certificates and profiles are the team's, expire yearly and
are replaced without consequence. What must never be lost is access to the team's developer account.

## Two ways to get a build to TestFlight

**From the Mac (no secrets):** `scripts/fetch-libxray.sh && scripts/fetch-hev.sh && xcodegen generate && open
SkyRay.xcodeproj`, then Product → Archive → Distribute App → App Store Connect. Automatic signing under the team does
the rest. Set `VERSION` (below) first; the build number is `CURRENT_PROJECT_VERSION` in `project.yml` for a Mac
archive — raise it by hand above the last one uploaded.

**From CI (once the secrets exist):** the workflow signs manually with the distribution certificate and the two App
Store profiles, and uploads with the App Store Connect API key.

1. App IDs (developer portal): `com.allion.skyray` with **Network Extensions**, **App Groups**
   (`group.com.allion.skyray`) and **Associated Domains**; `com.allion.skyray.PacketTunnel` with Network Extensions
   and the same App Group. (Xcode's automatic signing on the Mac registers these itself.)
2. An **Apple Distribution** certificate made on the Mac (Keychain Access → Certificate Assistant → Request a
   Certificate → upload the CSR in the portal → download → export as `.p12` with a password).
3. Two App Store provisioning profiles named exactly **SkyRay AppStore** (`com.allion.skyray`) and
   **SkyRay Tunnel AppStore** (`com.allion.skyray.PacketTunnel`).
4. An App Store Connect **API key** (Users and Access → Integrations → App Store Connect API, role App Manager):
   note the Key ID and Issuer ID, download the `.p8` once.
5. Repository secrets (Settings → Secrets and variables → Actions): `APPLE_TEAM_ID` (`SG5BT8WSLT`),
   `IOS_DIST_P12_BASE64` (`base64 -i dist.p12`), `IOS_DIST_P12_PASSWORD`, `IOS_PROFILE_APP_BASE64`,
   `IOS_PROFILE_TUNNEL_BASE64` (`base64 -i X.mobileprovision`), `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY`
   (the `.p8` file's text). Without them CI still compiles the app unsigned.
6. TestFlight: internal testers (your Apple ID on the iPhones you test with).

## Every release

1. Set `VERSION`: above the version on the App Store and the same number as the Android release it goes with (one
   version number everywhere). CI's build numbers are `100 + the run number`, always above the store's.
2. Push `main`; the push build must be green (unit tests, compile).
3. `git tag vX.Y.Z && git push github vX.Y.Z` — the tag must equal `VERSION`; CI archives, exports and uploads to
   TestFlight. (A manual run with "upload" ticked does the same for an untagged commit.)
4. App Store Connect: the build appears under TestFlight after processing (10–30 min); test it; then App Store → the
   new version → select the build → submit for review with the review notes (a working demo link, the steps,
   "nothing is sold in the app").

Rollback: submit the previous build again (builds stay in App Store Connect); phones do not downgrade.

## Bumping the native libraries

libXray: change `tag` and `sha256` in `Vendor/libxray.lock` (`shasum -a 256` of the release's `libxray-apple-cgo.zip`),
re-read its README against `docs/libxray-api.md`. hev-socks5-tunnel: `tag`, `asset` and `sha256` in `Vendor/hev.lock`
(the release's `.tar.xz`). Then push, and re-run the device checklist: connect on a WS line and an XHTTP line, watch
`tunnel.log`'s memory lines.

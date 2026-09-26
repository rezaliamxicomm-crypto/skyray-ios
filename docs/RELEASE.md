# Releasing SkyRay for iOS

## Once (the operator, in the Apple developer portal and App Store Connect)

1. App IDs: `com.allion.skyray` (the existing App Store app) with **Network Extensions**, **App Groups**
   (`group.com.allion.skyray`) and **Associated Domains**; `com.allion.skyray.tunnel` with Network
   Extensions and the same App Group.
2. An **Apple Distribution** certificate made on the Mac (Keychain Access → Certificate Assistant → Request a
   Certificate → upload the CSR in the portal → download → export as `.p12` with a password).
3. Two App Store provisioning profiles named exactly **SkyRay AppStore** (`com.allion.skyray`) and
   **SkyRay Tunnel AppStore** (`com.allion.skyray.tunnel`).
4. An App Store Connect **API key** (Users and Access → Integrations → App Store Connect API, role Developer or
   App Manager): note the Key ID and Issuer ID, download the `.p8` once.
5. Repository secrets (Settings → Secrets and variables → Actions): `APPLE_TEAM_ID`, `IOS_DIST_P12_BASE64`
   (`base64 -i dist.p12`), `IOS_DIST_P12_PASSWORD`, `IOS_PROFILE_APP_BASE64`, `IOS_PROFILE_TUNNEL_BASE64`
   (`base64 -i X.mobileprovision`), `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY` (the `.p8` file's text).
   Without them CI still compiles the app unsigned.
6. TestFlight: internal testers (your Apple ID on the iPhones you test with).

## Every release

1. Set `VERSION` (the marketing version; it must be higher than the version on the App Store and the same
   for the app and the extension). Both build numbers are `100 + the CI run number`.
2. Push `main`; the push build must be green (unit tests, archive).
3. `git tag vX.Y.Z && git push github vX.Y.Z` — the tag must equal `VERSION`; CI archives, exports and
   uploads to TestFlight. (A manual run with "upload" ticked does the same for an untagged commit.)
4. App Store Connect: the build appears under TestFlight after processing (10–30 min); test it; then
   App Store → the new version → select the build → submit for review with the review notes
   (`store/ios/listing.md`: a working demo link, the steps, "nothing is sold in the app").

Rollback: submit the previous build again (builds stay in App Store Connect); phones do not downgrade.

## Bumping libXray

Change `tag` and `sha256` in `Vendor/libxray.lock` (`shasum -a 256` of the release's
`libxray-apple-cgo.zip`), re-read its README against `docs/libxray-api.md`, push, and re-run the device
checklist: connect on a WS line and an XHTTP line, watch `tunnel.log`'s memory lines.

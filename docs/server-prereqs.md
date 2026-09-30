# What the EthaVPN server needs for SkyRay iOS

Staged on the server as `/opt/staging/skyray-ios-links/` (runbook, tests, rollback; written for the previous app and
reverted, to be re-run against the live files when this app ships):

1. **Universal links.** `https://<each link host>/.well-known/apple-app-site-association`, served as
   `application/json` with no redirect (nginx `location =` next to `assetlinks.json`, on `fra.skyrayconfig.org`
   and the two earlier link hosts, for links in old messages):
   `{"applinks":{"details":[{"appIDs":["SG5BT8WSLT.com.allion.skyray"],"components":[{"/":"/sub/*"}]}]}}`.
   Apple's CDN must be able to fetch it through Cloudflare — and must not be asked before the file is live: it
   caches a 404 for hours (`https://app-site-association.cdn-apple.com/a/v1/<host>`).
2. **The landing page** (`app/landing.py`): SkyRay is the iOS default as it is Android's; an iPhone that never
   fetched with SkyRay gets one App Store button (`https://apps.apple.com/app/id6809038308`, the link copied first),
   "Open in SkyRay" (`ethavpn://install-sub?url=…`), the Smart App Banner.
3. **The bot's fix-it screen**: "SkyRay on the App Store (iPhone)" instead of V2Box. **The panel**: the User-Agent
   `SkyRay/<v> (ios)` shown as "SkyRay iOS".
4. **The privacy page** `https://allionapp.com/skyray-privacy` mentions iOS (no update check, no Renew).

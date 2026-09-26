# What the EthaVPN server needs for SkyRay iOS

Staged and applied on the server as `/opt/staging/skyray-ios/` (runbook, tests, rollback):

1. **Universal links.** `https://fra.mobileiphone.org/.well-known/apple-app-site-association`, served as
   `application/json` with no redirect (nginx `location =` block, also in the ops template):
   `{"applinks":{"details":[{"appIDs":["<TEAMID>.com.allion.skyray"],"components":[{"/":"/sub/*"}]}]}}`.
   Apple's CDN must be able to fetch it through Cloudflare; check
   `https://app-site-association.cdn-apple.com/a/v1/fra.mobileiphone.org`.
2. **The landing page** (`app/landing.py`): the SkyRay entry gains `ios` with `skyray://install-sub?url=<enc>&name=<enc>`;
   on iOS the SkyRay install screen is one App Store button (the link is copied to the clipboard first);
   SkyRay becomes the iOS default behind a `settings.app_ios` switch once the store version is live.
3. **The bot's fix-it screen**: "SkyRay on the App Store" next to V2Box (iPhone). **The panel**: the
   User-Agent `SkyRay/<v> (ios)` shown as "SkyRay iOS".
4. **The privacy page** `https://allionapp.com/skyray-privacy` mentions iOS (no update check, no Renew).

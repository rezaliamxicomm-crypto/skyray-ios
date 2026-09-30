# Testing on an iPhone

Nothing compiles on the server that writes this code: GitHub's Mac runner compiles every push (the Actions tab), and a
real phone is the only place a packet tunnel runs. This is the loop between the two: one command on the Mac, then the
logs pasted back.

## Once

1. Xcode on the Mac, signed in (Xcode → Settings → Accounts) with an Apple ID that belongs to team **SG5BT8WSLT**
   (ALLION LLC). Nothing else is needed for a development build: the project uses automatic signing.
2. `brew install xcodegen`.
3. Clone the repo, then in it: `scripts/fetch-libxray.sh` and `scripts/fetch-hev.sh` (the two native libraries; a few
   minutes the first time, cached after).
4. The iPhone plugged in, unlocked, trusting the Mac (or paired for wireless debugging). Developer Mode on
   (Settings → Privacy & Security → Developer Mode) on iOS 16+.

## Every build

```bash
scripts/deploy-device.sh                      # build, install, launch
scripts/deploy-device.sh -ImportLink 'https://fra.skyrayconfig.org/sub/<token>' -AutoConnect YES   # …and add a link, connect
scripts/pull-logs.sh                          # the app's, the tunnel's and Xray's logs → build/device-logs/, tails printed
```

The first run on a phone asks to allow the VPN configuration (the system prompt); after it, `-AutoConnect YES`
connects without a tap. `-Disconnect YES` disconnects. `DEVICE="<the phone's name>"` picks a phone when several are
known (`xcrun devicectl list devices`).

Paste the output of `pull-logs.sh` back into the chat: `tunnel.log` says which line came up, the probe results and the
memory footprint every 30 s (the number to watch: the extension dies above about 50 MiB); `xray.log` carries Xray's
warnings; `app.log` the imports and refreshes.

If the build fails, `build/device-build.log` has the full compiler output; the lines with `error:` are enough.

## What to check on the phone, in order

1. A link tapped in Telegram opens the app and adds the account (universal links need the server's
   `apple-app-site-association` file; until then the page's button and the clipboard import do it).
2. Connect → "Finding the best server…" → Connected with the line and its delay; browse a foreign site (proxied) and an
   Iranian one (direct); a Google search works; an Iranian banking app works while connected.
3. Wi-Fi ↔ cellular: the tunnel stays up; after airplane mode, it recovers within a minute.
4. Lock the phone for ten minutes, then use it: still connected.
5. Test again re-picks the fastest line; picking a line pins it; Auto unpins.
6. Settings → Delete account: the VPN profile goes, the empty card is back, the clipboard does not re-add the link.

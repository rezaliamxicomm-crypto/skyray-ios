# SkyRay for iOS — privacy

**English**

SkyRay is a VPN client. It sends this phone's traffic through the EthaVPN servers named in your
subscription link and nothing else. The app collects no analytics, no identifiers and no logs, and sends
nothing to the developers.

What leaves your phone because the service cannot work without it:

- The subscription link you added is fetched from the EthaVPN server (every few hours, and when you tap
  Refresh). That request carries the app's name and version (`SkyRay/<version> (ios)`). The server records
  the time of the last fetch per subscription so that support can tell whether your app has received the
  servers. The link is fetched with Encrypted Client Hello, so its address is not visible on the way (only
  when that gets no answer is it fetched as an ordinary request); for that the app asks three public DNS services (Google, Cloudflare, Quad9) for Cloudflare's public
  encryption key — a question that names Cloudflare, not you and not your link.
- Your VPN traffic goes to the EthaVPN servers. What the servers keep is described by the service, not by
  this app; the app adds nothing to it.
- The Support button opens the EthaVPN Telegram bot; from there on Telegram's rules apply.

What stays on this phone only: your subscription link, the server list it returns and the app's own log
files (shared only when you tap "Send logs to support"). "Delete account" in Settings removes all of it.

Nothing is sold or shared with third parties. The app is open source (MIT), built on Xray-core and libXray.
The full policy: https://allionapp.com/skyray-privacy

**فارسی**

اسکای‌ری یک کلاینت VPN است. ترافیک این گوشی را از سرورهای EthaVPN که در لینک اشتراک شما نام برده
شده‌اند عبور می‌دهد و بس. برنامه هیچ آمار، شناسه یا لاگی جمع نمی‌کند و چیزی برای سازندگان نمی‌فرستد.

آنچه از گوشی شما خارج می‌شود چون سرویس بدون آن کار نمی‌کند: لینک اشتراک هر چند ساعت (و با زدن
بروزرسانی) از سرور EthaVPN گرفته می‌شود و این درخواست نام و نسخه‌ی برنامه را همراه دارد (لینک با Encrypted
Client Hello گرفته می‌شود تا نشانی آن در مسیر دیده نشود، و فقط اگر این راه پاسخی نگیرد با یک درخواست معمولی؛ برای این کار برنامه کلید عمومی Cloudflare را از سه
سرویس DNS عمومی — گوگل، Cloudflare و Quad9 — می‌پرسد، پرسشی که نام Cloudflare را دارد، نه شما و نه لینک شما)؛ ترافیک VPN شما به
سرورهای EthaVPN می‌رود؛ دکمه‌ی پشتیبانی ربات تلگرام را باز می‌کند.

آنچه فقط روی گوشی می‌ماند: لینک اشتراک، فهرست سرورها و لاگ‌های خود برنامه. «حذف حساب» در تنظیمات همه را
پاک می‌کند. چیزی به کسی فروخته یا داده نمی‌شود. متن کامل: https://allionapp.com/skyray-privacy

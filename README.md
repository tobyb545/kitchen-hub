# Kitchen Hub

An iPad app that turns an iPad into a kitchen display: recipes, timers, a shopping list,
and one-tap smart-home scenes through Alexa.

## Build
```
xcodegen generate
open KitchenHub.xcodeproj   # pick your iPad, Run
```

## Sending recipes
The app runs a small web server on the Wi-Fi while it's open (port 8080, shown on Home with a QR code).
- Open `http://<ipad-ip>:8080` on any phone/computer and paste a link or recipe text.
- `POST /api/recipe` with `{"url": "..."}` or `{"text": "..."}`; `POST /api/timer` with `{"minutes": 10, "label": "Pasta"}`.
- iPhone Share-sheet Shortcut: see Settings › "Send from iPhone's Share menu".

Import order for links: schema.org JSON-LD → hidden WebKit render (bot-checked sites) → text parser on the page text.

## Other ways in
- **Share menu** (`KitchenHubShare` extension): links, text, photos, PDFs → App Group inbox
  (`group.com.tobyblunt.kitchenhub`, `Shared/ImportInbox.swift`) → imported when the app is active.
  AirDropped links open in Safari on the iPad, then Share › Kitchen Hub.
- **AirDrop / Open in** for PDFs, images, text and HTML files (`CFBundleDocumentTypes`).
- **Photos**: on-device text recognition (Vision, two-column aware) → `RecipeSplitter` → text parser. Everything runs on the iPad; no API keys. From the camera
  document scanner, the photo picker, the Share menu, or the Wi-Fi page (`POST /api/photos`).

## Alexa scenes
Amazon has no public API for apps to run Alexa routines, so scenes call Voice Monkey
(`https://api-v3.voicemonkey.io/trigger`), which presses a virtual Alexa "Routine Trigger".
Set up per scene: Voice Monkey trigger ID ⇄ Alexa routine. Guide is in the app.

## URL scheme
`kitchenhub://tab/<home|recipes|timers|shopping|scenes|settings>`, `kitchenhub://recipe/latest`,
`kitchenhub://add?url=…`, `kitchenhub://timer?minutes=10&label=Pasta`, `kitchenhub://scene/<name>`.

## TestFlight (Codemagic)

`codemagic.yaml` builds, signs and uploads to App Store Connect (workflow **Kitchen Hub - App Store**).
One-time setup is in the file header: App Groups on both App IDs, an App Store Connect app record,
and its numeric Apple ID in `APP_STORE_CONNECT_APP_ID`.

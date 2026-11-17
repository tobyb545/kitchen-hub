# Kitchen Hub — App Store Connect listing

Copy each field into App Store Connect › Kitchen Hub › App Store (the version page) and App Information.
Character limits are Apple's.

## App Information

| Field | Value |
|---|---|
| Name (30) | Kitchen Hub |
| Subtitle (30) | Recipes, timers & cook mode |
| Primary category | Food & Drink |
| Secondary category | Productivity |
| Content rights | Does not contain third-party content that requires rights (recipes are imported by the user) |
| Age rating | 4+ (answer "None" to every question; no web browser — pages are only fetched to read recipes) |

If "Kitchen Hub" is already taken, use **Kitchen Hub: Recipe Display** or **Kitchen Hub for iPad**.

## Version information

**Promotional text (170)**
> Turn your iPad into a kitchen display. Send recipes from any site, phone or cookbook, cook step by step with built-in timers, and set the lights with one tap.

**Description (4000)**
> Kitchen Hub turns your iPad into the command centre for your kitchen. Recipes, timers, the shopping list and your lights, all on one screen you can read from across the room.
>
> SEND RECIPES FROM ANYWHERE
> • Paste a link from any recipe website and get just the ingredients and method, without the adverts or the life story
> • Share from Safari or any app with the Share menu, or AirDrop to the iPad
> • Scan a cookbook page with the camera, or add screenshots and photos. Several recipes in one batch are split automatically
> • Send from your phone over Wi-Fi: open the iPad's address in any browser, no app needed
>
> COOK MODE
> • Big, one-step-at-a-time instructions you can read with flour on your hands
> • Tap any time in a step ("simmer for 10 minutes") to start a timer
> • Scale servings up or down and every quantity updates
>
> YOUR UNITS, EVERY TIME
> • Switch any recipe between cups and grams, °F and °C
> • Ingredient-aware: a cup of flour and a cup of sugar convert to different weights
> • Oven temperatures are rounded to real oven settings
>
> TIMERS THAT GET NOTICED
> • Run as many named timers as you like
> • A loud full-screen alarm when one finishes, plus a notification if you've left the app
>
> SHOPPING LIST
> • Send everything you haven't ticked off straight to the shopping list
>
> SET THE MOOD
> • Scenes run your Alexa routines through the free Voice Monkey skill, so one tap sets the lights for cooking, dinner or a film night
> • Or call any web address (webhook) for other smart home systems
>
> MADE FOR THE KITCHEN COUNTER
> • Keeps the screen on while it's open
> • Recipe reading, photo text recognition and conversions all happen on your iPad. No account, no subscription, no tracking

**Keywords (100)** — comma-separated, no spaces needed:
```
recipe,cooking,kitchen,timer,cook mode,meal,shopping list,grams,cups,converter,scan,cookbook,display
```

**What's New (first version)**
> First release.

**Support URL** — required. A public page with a way to contact you (e.g. a GitHub Pages site, or the repo's README if the repo is public).
**Marketing URL** — optional.
**Privacy Policy URL** — required for every app. Publish `privacy-policy.md` (next to this file) somewhere public and use that link.
**Copyright** — 2026 Toby Blunt

## App Privacy (App Store Connect › App Privacy)

Answer **"No, we do not collect data from this app."** Kitchen Hub has no account, analytics or server of its own:
- Recipes, photos, timers and the shopping list stay on the iPad.
- Recipe links are fetched directly from the recipe website.
- The Voice Monkey token is stored in the iPad's Keychain and only sent to Voice Monkey when you run a scene.

## App Review notes

> Kitchen Hub works without an account. To try it: Recipes › + › paste a recipe link (e.g. any BBC Good Food or AllRecipes page) or some recipe text.
> Scenes need the user's own Voice Monkey account linked to Amazon Alexa, so they can't be demonstrated without one; tapping a scene with no token set shows an explanation.
> The Wi-Fi receiver (Settings › Recipe receiver) serves a page on the local network so recipes can be sent from a phone; it asks for Local Network permission.

## Screenshots

In `AppStore/screenshots/`: 2752 × 2064 (13-inch iPad, landscape), which App Store Connect also uses for smaller iPads.
Upload the `framed/` versions (with captions) in order 01–08; `raw/` holds the plain captures.

1. Your kitchen, at a glance (Home)
2. Import recipes from anywhere (Add recipe: link, scan, photos)
3. Send it from your phone (iPhone send page + recipe arriving on the iPad)
4. Any recipe, beautifully tidy
5. Cook step by step
6. Cups or grams? °F or °C?
7. Timers you won't miss
8. Never forget the lemons (shopping list)

To regenerate: run a Debug build in the "Screenshots iPad 13" simulator with `-screenshotSeed`
(see `KitchenHub/Support/ScreenshotSeed.swift`), capture, then `python3 AppStore/frame_screenshots.py`.

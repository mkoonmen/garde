# Garde — Michael's personal chef AI (iPhone)

*Garde* is short for **garde-manger**, the kitchen station that keeps the larder: stocked, labeled, nothing wasted.

A private kitchen assistant. The AI is Apple's on-device model; your food, receipts and tastes stay on the iPhone. The only network calls are Gmail (if you connect it) and barcode lookups (Open Food Facts, barcode number only).

## Tabs
| Tab | What's there |
|---|---|
| **Kitchen** | Inventory by fridge / freezer / pantry / counter, expiration countdowns, "use these first", leftovers badge, swipe **Ate it** or **Tossed** (tossed feeds the waste tracker) |
| **Scan** | **Live scan**: beep through barcodes as you unpack, tap a printed date to attach it, allergen warning if a product contains one of yours. **Photo scan**: receipt, grocery haul / fridge, or label → reviewed list of items |
| **Chef** | **Ask the chef** (offline chat, type or talk) · Recipe ideas from what you have (soonest-expiring first, mood, time, must-use, **remix leftovers**). **Week plan** (toolbar): dinners for 2–7 days built around expirations, missing groceries sent to the List. Recipe pages show **estimated cost**, **pairing from your bar**, and **Cook mode** |
| **List** | Smart shopping list in store-walk order. Auto-adds what you're about to run out of (learned from your buying pace), staples you finished, low/empty spices, and week-plan needs. Ticks itself off when groceries are scanned or imported |
| **More** | Spice rack · Bar & cellar · Insights (spend, waste, cost per meal, taste memory) · Allergies & tastes · Receipts · Gmail receipts · Used-up history · JSON export/import |

### Cook mode
Full screen, big text, screen stays on. Steps can be read aloud; say **"next", "back", "repeat", "start timer", "how long"** (speech recognized on-device). Steps with a time get a one-tap timer (with a backup notification if the phone locks). When you finish: rate it (1–5, "what I'd change", "never again"), mark ingredients used, save leftovers with a 4-day countdown.

### Taste memory
Every rating is fed back into the chef and the week planner: loved dishes steer suggestions, feedback is applied, "never again" dishes are filtered out in code.

### Siri & widgets
- "What's expiring in Garde" · "What's for dinner in Garde" · "Add to my Garde list"
- Home-screen widget (small / medium) and lock-screen widgets: tonight's planned dinner + what to use first.

### Gmail receipts (one-time setup)
1. Google Cloud Console → new project → enable **Gmail API**.
2. OAuth consent screen: External, add yourself as a **test user**.
3. Credentials → OAuth client ID → type **iOS**, bundle ID `com.michaelkoonmen.garde`.
4. In Garde: More → Gmail receipts → paste the client ID → Connect.
Read-only scope. Garde searches only for grocery/order receipts (search is editable), reads them on the phone, and imports items + the receipt.

## Allergy safety
Allergies are an absolute rule in every AI prompt **and** every recipe and plan is re-checked in plain code (`Services/AllergenGuard.swift`, e.g. "shellfish" expands to shrimp, crab, lobster, scallop…). Anything that mentions one is discarded. Barcode scans warn when a product's listed allergens match. Strong net, not a guarantee: always read real labels.

## Requirements
iPhone 15 Pro or newer (built for 17 Pro), iOS 26, Apple Intelligence on. Without it, scanning falls back to a simpler receipt reader and the chef explains why it's off.

## Project layout
```
project.yml                     XcodeGen spec (app + widget; .xcodeproj is generated)
Shared/                         used by app AND widget
  Models.swift                  SwiftData models + GardeStore (App Group container)
  ShelfLife.swift  Theme.swift  Seasonal.swift (local produce by month)
Garde/
  App/GardeApp.swift            entry, tabs, background refresh hooks
  Services/
    ChefAI.swift                on-device model: scan parsing, recipes, week plan, pairing, taste prompts
    AllergenGuard.swift         hard allergen filter
    TextRecognizer.swift        Vision OCR + image labels
    GmailImporter.swift         OAuth (PKCE) + Gmail read-only import, Keychain
    BarcodeLookup.swift         Open Food Facts lookup
    ShoppingBrain.swift         buying-pace learning, list automation, aisle order
    CostCalculator.swift        cost per recipe, waste report
    PriceBook.swift             price history per item, cheapest store
    RecipeScaler.swift          rescales ingredient amounts for servings
    Takeout.swift               DoorDash/Uber Eats/restaurant receipts → takeout favorites
    CookVoice.swift             speech in/out, step-time parsing
    GardeIntents.swift          Siri / Shortcuts
    Notifier.swift  DataExport.swift
  Views/                        SwiftUI screens
GardeWidget/GardeWidget.swift   home + lock screen widgets
GardeTests/GardeTests.swift     automated tests (run in CI before upload)
  Services/ReceiptLexicon.swift receipt abbreviation dictionary
.github/workflows/testflight.yml   builds on GitHub's Macs, uploads to TestFlight
```

## Building & installing (TestFlight)
**Main route (Mac, ~/Developer/garde):** double-click `build-upload.command`. It regenerates the Xcode project, archives, and uploads to TestFlight using the Apple account signed in to Xcode; the log goes to `build-log.txt`. `setup-xcode.command` only regenerates the project and opens it in Xcode. App Store Connect record: "Garde Kitchen" (bundle ID `com.michaelkoonmen.garde`, TestFlight internal group "Me"). Home-screen name stays "Garde".

**Optional cloud route:** the GitHub workflow builds and uploads, but only when run by hand from the Actions tab. Repo secrets:

| Secret | Where it comes from |
|---|---|
| `APPLE_TEAM_ID` | developer.apple.com → Membership → Team ID |
| `ASC_KEY_ID` | App Store Connect → Users and Access → Integrations → App Store Connect API |
| `ASC_ISSUER_ID` | same page |
| `ASC_KEY_P8` | contents of the downloaded `AuthKey_XXXX.p8` |

One-time: create the app in App Store Connect with bundle ID `com.michaelkoonmen.garde`, then add your personal Apple ID as an internal tester. The App Group `group.com.michaelkoonmen.garde` is registered automatically by signing; if the first build complains about it, create it under developer.apple.com → Identifiers → App Groups.

## Not built yet
- Live deal tracking across local stores and national brands (needs internet; planned as a separate, opt-in service)

## Change log
- 2026-11-05 — v2.8 (in progress): Price book (every price you've paid, lowest, average, cheapest store, "going up" list; shopping-list rows show last price and cheapest store). Recipes: servings stepper that rescales every ingredient amount offline, ⇄ ingredient substitutions (allergen-checked, prefers what you already have). Chef tab: "Cook again" (dishes rated 4+ not made in 3 weeks), "In season now" (Long Island month-by-month produce, also fed to the chef), "Only what I have" no-shopping mode. **Host a dinner** (guests, occasion, guests' allergies → make-ahead menu, prep timeline, one-tap shopping list; allergen-checked for you and guests). Bar: **Mix tonight** (cocktails from your bottles and kitchen citrus/herbs, moods, allergen-checked including liqueurs). Kitchen dashboard "This week" strip (cooked, eaten, tossed, spent). Review fixes: re-import can no longer wipe data mid-import, old receipts don't tick off today's list, takeout status emails don't duplicate orders, emails wait for the AI instead of being lost, non-UTF-8 receipts read, more grocery chains (Kroger, Safeway, Acme, Giant, H-E-B, C-Town, Western Beef…), whole-word store matching, DoorDash/Uber Eats grocery orders count as groceries, downloaded Qwen model works for every chef feature. Tests for scaling, price keys, Gmail filters, takeout senders, seasonal list vs. nut allergy.
- 2026-11-05 — v2.7: Gmail receipts cleaned up: only known grocery/big-box senders count as grocery receipts (no more Anthropic, Qwen, etc.); shipping/pickup/review/refund emails skipped; a receipt needs a total or 3+ food items; McDonald's, Wendy's and other restaurant-app receipts go to Takeout favorites; junk from earlier imports is removed automatically on launch.
- 2026-11-05 — v2.6: Takeout favorites: DoorDash / Uber Eats / Grubhub / Seamless / Caviar / Postmates receipts in Gmail become takeout history (restaurant, cuisine, dishes, total); favorite dishes ranked with one-tap "Cook it" homemade versions; the chef's suggestions lean toward what you order. (No direct DoorDash/Uber Eats login exists for third-party apps; Gmail receipts are the source.)
- 2026-11-05 — v2.5: Back to the 2.1 layout (glass lists + Kitchen dashboard); cartoon kitchen removed. New background: deep navy with slow navy/teal/indigo aurora bands at the top, thin copper rim light, vignette and fine grain (no center blob).
- 2026-11-05 — v2.4: Kitchen tab is now an illustrated kitchen (fridge, freezer drawer, pantry, counter, spice rack, wine rack with count magnets); tapping one swings it open into a themed room (lit fridge with shelves/drawers, frosty freezer with snow, wooden pantry, butcher-block counter) with foods as emoji cards; expiring items glow and wobble; long-press to ate/toss/freeze/thaw; list view kept. Other screens use the tiled kitchen-wall background instead of the gradient blob.
- 2026-11-05 — v2.3: Gmail import searches all orders/receipts from the past year across ~50 grocery and big-box stores (Target, Walmart, Costco, BJ's, King Kullen, Stop & Shop, Fine Fare, Whole Foods, Sprouts, Trader Joe's, Wegmans, Instacart, Amazon…), up to 1,500 emails, resumable.
- 2026-11-05 — v2.2: Allergies with exceptions ("Tree nuts except almonds, hazelnuts"; picker in Allergies & tastes); unnamed "nuts"/"may contain nuts" are blocked; barcode "may contain" traces checked. Deals rebuilt on real weekly grocery circulars (flyers by ZIP → items), ZIP Update button, browse/search, store toggles. Bar & cellar: scan a bottle label (barcode + label text → name, type, vintage, region; rescans add to count). Gmail import rebuilt: grocery-only search over 90 days, item-section extraction + chunked reading, real totals, non-food filter, duplicate protection, progress, re-read all, imported-receipt list; old orders go to history.
- 2026-11-05 — v2.1: Redesign: drifting navy/copper mesh-gradient background, frosted-glass lists and menus, Kitchen dashboard (greeting + fridge/freezer/pantry tiles that filter), glowing expiring cards, gradient Cook button, translucent bars. Password-protected Developer options (More → Developer options) now hold the Koonmen OS feed and Gmail internals; testers don't see them and get no default ZIP code.
- 2026-11-05 — v2.0: Live deals (weekly ads via Flipp search, ZIP + store settings, planner uses sales); optional Qwen3 8B on-device chef via MLX (iOS 27+); Share → Garde for TikTok/Instagram/web/photos (schema.org recipes read exactly) and receipt emails from Mail; Siri "used / bought / do I have"; Koonmen OS kitchen feed (garde-kitchen.json in iCloud Drive, see docs/KOONMEN_OS.md); fridge check-in photo; iCloud sync (same Apple ID); navy page color instead of black; per-category Reset; Gmail sign-in built in for any Google account.
- 2026-11-05 — First real build: compiled cleanly and uploaded to TestFlight (build scripts added).
- 2026-11-05 — v1.3.1: Independent code review (separate reviewer, 18 findings), all fixed: regex literals enabled for the Swift 5 build, Vision/OCR double-resume crash, barcode cache race, Gmail sign-in sheet closing early and double imports, cook-mode voice restart loop, item editor overwriting real dates, chat forgetting context after opening a recipe, live scan camera permission, broth/canned tomatoes/sauces/buttermilk/deli shelf lives, week plan now built one dinner at a time to fit the on-device model, cook timers' backup alerts cancelled properly, no duplicate list items, "I made this" matching, re-plan respects cooked days, timezone-safe tests, CI picks the newest iPhone simulator.
- 2026-11-05 — v1.3: First-run onboarding (allergies, household, skill, loves/avoids, pantry staples, spice rack). **Ask the chef**: offline chat with the on-device model, typed or spoken (on-device dictation), allergen-checked recipes you can save or cook. Freezer: one-tap Freeze/Thaw with freezer shelf life, "Freeze it" on expiring items, 7 PM thaw reminders the night before a planned dinner, planner avoids frozen protein on day 0. Offline nutrition per serving (kcal, protein, carbs, fat) from a ~100-ingredient table, shown on recipes and the week plan. Offline receipt reader knows Stop & Shop/King Kullen weight lines, Costco item codes and discounts, Trader Joe's quantity lines, Walmart/Target UPCs; store detection. New tests for all of it.
- 2026-11-05 — v1.2: New icon (navy + cream chef's-hat G) and matching look: navy/cream colors that flip for dark mode, serif headings, recipe cards, navy launch screen, step animations and haptics. Smarter scanning: 280-entry receipt abbreviation dictionary (used offline and as AI hints), item-specific shelf lives (65 rules, fridge/freezer/pantry/opened), "I just opened it" shortens expirations. Automated tests (`GardeTests/`) for allergens, dates, timers, receipts, shelf life and aisles run before every TestFlight upload. Fixes: allergy filter no longer flags "bass" for shellfish and now catches more (carbonara, burrata, udon, calamari…); dates pick use-by over packed-on; timers read "1 1/2 hours"; expiration reminders no longer cancel cook timers; actor-isolation compile fixes.
- 2026-11-05 — v1.1: Gmail receipt import, live barcode/date scanning, week meal plan, smart shopping list, hands-free cook mode with timers, taste memory from ratings, cost per meal + waste tracking, bar & cellar with pairings, Siri shortcuts + home/lock screen widgets, leftovers tracking and remix. Backup format bumped to `garde/v2` (still imports v1).
- 2026-11-05 — Renamed app to Garde (bundle ID com.michaelkoonmen.garde).
- 2026-11-05 — v1: inventory, scanning, receipts, spices, allergy profile, on-device chef, reminders, JSON export/import.

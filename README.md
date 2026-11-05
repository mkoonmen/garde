# Garde — Michael's personal chef AI (iPhone)

*Garde* is short for **garde-manger**, the kitchen station that keeps the larder: stocked, labeled, nothing wasted.

A private kitchen assistant that runs entirely on the iPhone. Nothing is uploaded; the AI is Apple's on-device model.

## What it does
| Tab | Features |
|---|---|
| **Kitchen** | Inventory by fridge / freezer / pantry / counter, expiration countdowns, "use these first" strip, search, photos per item, swipe to mark used up |
| **Scan** | Photograph a receipt, a grocery haul or fridge shelf, or a label. On-device OCR (Vision) + the on-device model turn it into items you review before saving. Package dates are read when visible; otherwise expiration is estimated from typical shelf life |
| **Chef** | Recipe ideas from what you actually have, soonest-expiring first, by mood and time limit, with "must use" items. Save / favorite recipes, and "I made this" marks the ingredients used |
| **Spices** | Rack tracker with fill level, where it lives, freshness (ground ~2 yrs, whole ~3.5 yrs), restock list, quick-add of 20 common spices |
| **More** | Allergies & tastes profile, receipts with photo + spending by store and month, used-up history, JSON export/import |

Expiration reminders fire at 9 AM, N days before (N set in the profile).

## Allergy safety
Allergies are given to the AI as an absolute rule **and** every recipe is re-checked in plain code by `Services/AllergenGuard.swift` (e.g. "shellfish" expands to shrimp, crab, lobster, scallop…). Any recipe that mentions one is discarded. It's a strong net, not a guarantee — always read real labels.

## Requirements
- iPhone 15 Pro or newer (built for iPhone 17 Pro) on iOS 26, with Apple Intelligence turned on.
- If Apple Intelligence is off, scanning falls back to a simpler line-by-line receipt reader and the Chef tab explains why it's disabled.

## Project layout
```
project.yml                 XcodeGen spec (the .xcodeproj is generated, not committed)
Garde/
  App/GardeApp.swift   entry point, tabs, theme
  Models/Models.swift           SwiftData models: PantryItem, Receipt, Spice, SavedRecipe, KitchenProfile
  Services/
    ChefAI.swift                on-device model: scan parsing + recipes (@Generable structured output)
    AllergenGuard.swift         hard allergen filter
    TextRecognizer.swift        Vision OCR + image labels
    ShelfLife.swift             default shelf lives by category/location
    Notifier.swift              local expiration reminders
    DataExport.swift            plain JSON backup format "garde/v1"
  Views/                        SwiftUI screens
.github/workflows/testflight.yml   builds on GitHub's Mac runners and uploads to TestFlight
```

## Building & installing (TestFlight)
Every push to `main` builds the app on GitHub's macOS runners and uploads it to TestFlight. Repo secrets needed:

| Secret | Where it comes from |
|---|---|
| `APPLE_TEAM_ID` | developer.apple.com → Membership → Team ID |
| `ASC_KEY_ID` | App Store Connect → Users and Access → Integrations → App Store Connect API → key ID |
| `ASC_ISSUER_ID` | same page, Issuer ID |
| `ASC_KEY_P8` | contents of the downloaded `AuthKey_XXXX.p8` file |

One-time: create the app record in App Store Connect with bundle ID `com.michaelkoonmen.garde` (name "Garde", or similar if taken), then add your personal Apple ID as an internal TestFlight tester.

## Not built yet (planned)
- Live deal tracking across local stores and national brands (needs internet; will be a separate, opt-in service)

## Change log
- 2026-11-05 — Renamed app to Garde (bundle ID com.michaelkoonmen.garde).
- 2026-11-05 — v1: inventory, scanning, receipts, spices, allergy profile, on-device chef, reminders, JSON export/import.

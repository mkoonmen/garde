# Garde → Koonmen OS kitchen feed

Garde (iPhone) writes a read-only JSON snapshot to its iCloud Drive container. On the Mac it appears at:

`~/Library/Mobile Documents/iCloud~com~michaelkoonmen~garde/Documents/garde-kitchen.json`

It is rewritten when Garde goes to the background and on every cook-mode step change.

## Format (`garde-kitchen/v1`)
```json
{
  "format": "garde-kitchen/v1",
  "updatedAt": "2026-11-05T19:30:00Z",
  "tonight": { "title": "Lemon garlic chicken", "summary": "...", "minutes": 35, "ingredients": ["..."], "steps": ["..."] },
  "useFirst": [ { "name": "Chicken thighs", "where": "fridge", "days_left": 1 } ],
  "shoppingCount": 7,
  "cooking": { "title": "Lemon garlic chicken", "step": 3, "total": 8, "text": "Sear 4 minutes per side", "timerEndsAt": "2026-11-05T19:41:00Z" }
}
```
`tonight` and `cooking` may be null. `cooking` is non-null only while cook mode is open.

## TV side (not built yet; for whoever owns the bridge/TV apps)
- Bridge: add a read-only `GET /v1/kitchen` that returns this file's contents (same Bearer auth as other routes; 404 if the file is missing; treat data older than ~6 h as stale).
- TVs: a Kitchen tile showing tonight's dinner + "use first"; when `cooking` is non-null, a full-screen step view with the timer countdown.
- Garde never sends commands; nothing on the TV side can change Garde's data.

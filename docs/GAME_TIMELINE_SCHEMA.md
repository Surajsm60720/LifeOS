# Game timeline import — schema v1

LifeOS can create an entire version's worth of game entries from one JSON file:
events, banner phases, and endgame rotations. The file is produced by an LLM from
the timeline image the developers publish at the end of each livestream, then
imported in **Settings → Games → Game Timeline**. Parsing happens entirely
on-device; the app never calls an AI service.

The point is to skip manual entry of names, dates, durations, and event types,
while keeping the result editable like any other entry.

## How to use this with an LLM

1. Open the version timeline image in a chat with Claude, ChatGPT, or Gemini.
2. Paste the prompt below, with the date filled in.
3. Save the reply as a `.json` file (raw JSON, no explanation).
4. In LifeOS: **Settings → Games → Game Timeline**, pick the file, review the
   summary, and tap **Import**.

### Prompt template

```text
Convert the attached game version timeline image into a LifeOS timeline JSON file.

Today is 2026-10-29.

Rules:
1. Output ONE JSON object that matches the schema exactly. No prose, no markdown
   fences, no commentary before or after.
2. One game per file. Put the game name in "game" exactly as one of:
   "Genshin Impact", "Honkai Star Rail", "Wuthering Waves".
3. Copy dates exactly as printed. Never infer, round, or shift a date.
4. Only write a time when the image literally shows one. Write times as
   "YYYY-MM-DD HH:mm" in the game server's local time. Never write "Z" or a
   UTC offset — the app applies the server time zone.
5. A banner with phases becomes one item per phase. Two separate banners in the
   same phase (e.g. character wish + weapon wish) become two items.
6. If a row is ambiguous or partially readable, still emit it, set
   "confidence": "low", and explain what is uncertain in "notes".
7. Give every item a stable "id": lowercase, hyphens, no dates, e.g.
   "genshin-6.1-astral-accord". Re-parsing the same image must produce the same id.
8. Put the exact text you read from the image in "sourceLine".
9. Emit only three kinds: "event", "banner", and "endgame". Skip maintenance,
   pre-install, livestream, battle pass, shop bundles, web events, and the version
   window itself.
10. Genshin Impact ONLY — HARD EXCLUSION: do NOT emit Spiral Abyss or
    Imaginarium Theater under any circumstances, even when the timeline image
    clearly shows them. Do not invent substitute endgame rows for Genshin either.
    Those two modes are fixed monthly rotations (same day, same time every month)
    that LifeOS already tracks as recurring entries; importing them would
    duplicate every cycle. For a Genshin file, "items" must contain only
    "event" and "banner" rows — zero "endgame" rows. Honkai Star Rail and
    Wuthering Waves still need their endgame rows (Memory of Chaos, Pure Fiction,
    Apocalyptic Shadow, Tower of Adversity, Whimpering Wastes, etc.).
11. If the image shows a range that crosses New Year, keep each date in the year
    it is printed in.
```

## Ground rules

- **One game per file.** A file for Genshin never contains Star Rail rows.
- **Dates before times.** The schema is built so an LLM can copy dates and skip
  clock times without breaking anything.
- **Server-local wall clock, never UTC.** `"2026-11-18 17:59"` means 17:59 in the
  game's server time zone. The app converts that to the phone's time zone.
- **The app owns the time zone.** Each game has a server setting (America, Asia,
  Europe, …) with a daily reset time and a banner switch time. The file never has
  to know which server you play on.
- **A date-only `end` is inclusive.** `"start": "2026-10-29", "end": "2026-11-11"`
  means the item is playable through 11 November.
- **Unknown rows are ignored.** Anything that isn't an event, a banner phase, or an
  endgame mode is skipped by the importer, and the preview reports how many rows
  were skipped.
- **Genshin Impact has no endgame rows.** Spiral Abyss and Imaginarium Theater are
  fixed monthly rotations (same calendar day and clock time every month) that the
  app already tracks as recurring entries. The LLM must omit them; the importer
  also filters them for Genshin if they still appear, and reports that it did.

## JSON shape

```json
{
  "format": "lifeos.timeline",
  "version": 1,
  "game": "Genshin Impact",
  "patch": "6.1",
  "serverTimeZone": "Etc/GMT+5",
  "generatedAt": "2026-10-20T12:00:00Z",
  "source": "6.1 livestream timeline",
  "items": [
    {
      "id": "genshin-6.1-astral-accord",
      "kind": "event",
      "group": "Main Events",
      "title": "Astral Accord",
      "start": "2026-10-29",
      "end": "2026-11-11",
      "notes": "Rewards: Primogems, Mora, Hero's Wit",
      "sourceLine": "Astral Accord 10/29 – 11/11",
      "confidence": "high"
    },
    {
      "id": "genshin-6.1-phase-1",
      "kind": "banner",
      "title": "Character Event Wish — Phase 1",
      "start": "2026-10-29 11:00",
      "end": "2026-11-18 17:59",
      "featured": ["Neuvillette", "Wriothesley"],
      "sourceLine": "Phase 1: 10/29 – 11/18",
      "confidence": "high"
    }
  ]
}
```

## Top-level fields

| Field | Type | Required | Notes |
|---|---|---|---|
| `format` | string | yes | Must be exactly `"lifeos.timeline"`. |
| `version` | integer | yes | Must be `1`. |
| `game` | string | yes | `Genshin Impact`, `Honkai Star Rail`, or `Wuthering Waves`. |
| `patch` | string | recommended | `"6.1"`, `"3.7"`, `"2.4"`. Used for grouping and re-import. |
| `serverTimeZone` | string | optional | IANA name of the game's fixed offset, e.g. `"Etc/GMT+5"` (UTC−5), `"Etc/GMT-8"` (UTC+8). Informational: the app uses the server you selected and warns if the offset differs. |
| `generatedAt` | ISO-8601 string | optional | When the LLM produced the file. |
| `source` | string | optional | e.g. `"6.1 livestream timeline"`. |
| `items` | array | yes | 1–500 items. |

## Item fields

| Field | Type | Required | Notes |
|---|---|---|---|
| `id` | string | recommended | Stable slug, unique within the file. Without it the app derives a key from game + patch + title. |
| `kind` | string | yes | See the table below. |
| `title` | string | yes | English name shown on the calendar. |
| `start` | string | yes | `"YYYY-MM-DD"` or `"YYYY-MM-DD HH:mm"`, server-local. |
| `end` | string or null | recommended | Same formats. Date-only is inclusive. `null` = a single-day milestone with no window. |
| `featured` | array of strings | optional | Banner characters, weapons, or resonators. |
| `group` | string | optional | Section of the timeline image, e.g. `"Main Events"`, `"Events"`. |
| `notes` | string | optional | Rewards, requirements, or the LLM's uncertainty note. |
| `sourceLine` | string | optional | Exact text from the image, for traceability. |
| `confidence` | `high` / `medium` / `low` | optional | `low` items are flagged in the import preview. |
| `phase` | integer | optional | `1` or `2` for banners. Helps the app place the phase switch correctly when two phases start on the same printed day. |

## `kind` values and where they land in the app

| `kind` | App event type | Typical rows in the image |
|---|---|---|
| `event` | In-Game Events | Main events, mini events, login events |
| `banner` | Banner Window | Character / weapon / resonator convenes, one per phase |
| `endgame` | Endgame Content | Spiral Abyss, Imaginarium Theater, Memory of Chaos, Pure Fiction, Apocalyptic Shadow, Tower of Adversity, Whimpering Wastes. **Genshin's two modes are never imported** — see below. |

Any other `kind` (patch, maintenance, preinstall, livestream, battlePass, shop,
web, other) is skipped and counted in the preview. Do not invent new kinds; if a
row truly is an in-game event, use `event`.

### Genshin Impact endgame exception (mandatory)

For **Genshin Impact**, never emit `endgame` items. Specifically never emit:

- Spiral Abyss (any spelling: "Spiral Abyss", "Abyss", "螺旋深境", …)
- Imaginarium Theater (any spelling: "Imaginarium Theater", "Theater", "幻想真境剧诗", …)

They rotate on a fixed monthly schedule that LifeOS already auto-fills as
recurring entries, so importing them duplicates every cycle. A valid Genshin
timeline file has **only** `event` and `banner` items. The importer also filters
those two titles out for Genshin if they appear anyway.

Endgame items are still expected for:

- Honkai Star Rail — Memory of Chaos, Pure Fiction, Apocalyptic Shadow
- Wuthering Waves — Tower of Adversity, Whimpering Wastes

## Date and time rules

- `"2026-10-29"` = the whole calendar day in the server's time zone. The app treats
  it as an all-day entry, so no clock time is shown and Ongoing counts whole days.
- `"2026-10-29 10:00"` = an exact wall-clock time in the server's time zone.
- **Never** write `"2026-10-29T10:00:00Z"` or `"+08:00"`. Offsets are the single
  biggest source of wrong imports; the app already knows the server.
- If the image shows `03:59`, `04:59`, `17:59`, or `23:59`, keep it — those are
  real cutoff times. Otherwise omit the time and let the app use the game's defaults.
- A date-only `end` is the **last playable day**, not the cutoff. For example
  `end: "2026-11-11"` stays active through 11 November.
- Ranges that cross a month or year boundary are fine; each date carries its own
  year as printed. The importer corrects a Year that is more than 180 days in the
  past and reports it.

## What the app does with the file

1. Validates `format`, `version`, `game`, item count, and every date.
2. Resolves each item into a start instant and a duration:
   - date-only item → all-day entry covering every printed day, inclusive
   - item with times → timed entry using the exact instants
3. Drops rows the app already owns. For Genshin Impact, Spiral Abyss and
   Imaginarium Theater rows are skipped because they are tracked as recurring
   entries.
4. Builds a normal `Entry` (`category: .game`, the game as sub-category, the
   mapped event type, notes carrying `featured` / `group` / `sourceLine`).
5. Shows a summary before writing: item count by kind, resolved local date range,
   warnings for low-confidence or malformed rows, and how many rows already exist.
6. Upserts by `id`, so importing a corrected file updates dates instead of
   duplicating entries, and leaves completions, locations, and notification rules
   untouched.
7. Tags every created entry with the import source (`Genshin Impact 6.1`) so the
   whole import can be removed later from the same screen.

## Common mistakes

| Mistake | Result | Fix |
|---|---|---|
| UTC timestamps | Entries land hours or a day off | Use server-local wall clock only |
| Splitting phases into one item | Phase 2 shows the Phase 1 window | One item per phase |
| Dropping the end date | Item becomes a single-day milestone | Always include `end` when the image shows a range |
| Inventing a year | Entries land a year away | Copy the year for each printed date |
| One file with three games | Rejected | One game per file |
| Including patch/maintenance/livestream rows | Ignored, counts reported as skipped | Emit only events, banners, and endgame |
| Including Genshin Spiral Abyss / Imaginarium Theater | Skipped for Genshin | Omit every endgame row for Genshin — events and banners only |
| Reusing ids for different rows | Second row overwrites the first | Unique `id` per item |

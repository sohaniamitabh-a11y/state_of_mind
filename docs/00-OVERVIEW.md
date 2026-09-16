# 00 — Overview

## What State of Mind is

A mood-based cross-media recommendation engine. The user picks how they're feeling from a fixed set of five moods, and the engine hands back Movies, TV, Music, and Games that fit that headspace.

There is no sign-up and no live third-party API call at query time. Everything is served out of a locally cached cloud database that scheduled harvesters refresh periodically, so a recommendation request is a single SQL join rather than a fan-out to TMDB, RAWG, and Deezer.

## The core idea

> "A brain shall never be restricted to specific data."

New moods, new genres, and entirely new media domains are added as new **rows**, never as new tables or new columns. `genres.media_type` and `items.media_type` are plain strings, not enums, precisely so that adding a food or makeup domain later requires zero schema migration. This constraint drives most of the design decisions in [08-DECISIONS.md](08-DECISIONS.md).

## The four components

| Component | Status | What it is |
|---|---|---|
| **The Brain** | Done / live | The `mood_genre_mapping` table — a weighted relevance score for every mood-genre pair, derived from human ratings |
| **The Harvester** | Partial | Three standalone Python scripts that pull trending content into the `items` cache, one per media source |
| **The Backend / Engine** | In progress — stage 4 of 7 done, stage 5 underway | Flask API exposing `/get-state?mood=X`, which joins mood → genre → items and returns ranked recommendations |
| **Frontend** | Not started | Flutter app with five fixed mood buttons. Zero code written yet |

## Where the project actually stands right now

**Live database contents:**

- 5 moods
- 64 genres (11 music, including fallback `Other`)
- 51 `mood_genre_mapping` rows (46 original + 5 for music `Other`; a further 74 rows are queued, waiting on the genre-expansion survey ratings to come back)
- 70 items (20 movie, 20 tv, 20 game, 10 music)
- `item_genres` at 119 links from those items
- `feedback` — empty and unused; the table exists but nothing writes to it

**Component detail:**

- **Brain:** done and live. The original 46 mapping rows came from the first round of ratings; five more map music `Other` to every mood at low relevance so unmatched Deezer tracks stay recommendable.
- **Harvester:** all three have run against live Aiven. Movies/TV remain the original 40. Games harvested 20 RAWG titles but warn on missing `action` slug (4 games ended with zero genre links). Music harvested 10 Deezer chart tracks; one fell back to `Other`.
- **Backend:** stage 4 of 7 is complete. The full mood → genre → items join is wired into the live `/get-state` route, but it returns raw duplicated rows. Stage 5 is in progress: the dedupe logic is written and tested inside `test_query.py` but has **not** been merged into `app.py`, and the bucketing into `movies_tv` / `music` / `games` plus the top-5-per-bucket cap hasn't been started.
- **Frontend:** not started.

## Team and division of work

A 3-person college project. One harvester is assigned per teammate and per device, so that no single machine holds more than one API key and a failure on one device can't take the other two harvests down:

- Movies/TV → this device
- Games → the Windows teammate
- Music → the MacBook teammate

Teammates haven't finished onboarding yet, so the current developer is working solo in the meantime. A one-off live harvest has since populated games and music as well as movies/TV.

## Reading order

1. **00-OVERVIEW.md** (this file) — what and where
2. [01-ARCHITECTURE.md](01-ARCHITECTURE.md) — how the pieces fit together
3. [02-DATABASE.md](02-DATABASE.md) — the six tables in detail
4. [03-DATA-PIPELINE.md](03-DATA-PIPELINE.md) — the order things have to be run in
5. [04-HARVESTERS.md](04-HARVESTERS.md) — the three collectors
6. [05-BACKEND.md](05-BACKEND.md) — the Flask API and its seven stages
7. [06-BRAIN-AND-RATINGS.md](06-BRAIN-AND-RATINGS.md) — where relevance scores come from
8. [07-SETUP.md](07-SETUP.md) — getting a device running
9. [08-DECISIONS.md](08-DECISIONS.md) — decisions made and why
10. [09-COMMIT-HISTORY.md](09-COMMIT-HISTORY.md) — what each existing commit actually changed

Contributing and commit conventions are in [CONTRIBUTING.md](../CONTRIBUTING.md).

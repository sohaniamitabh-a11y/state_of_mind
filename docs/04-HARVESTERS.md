# 04 — Harvesters

Three standalone scripts that fill the `items` and `item_genres` cache. Each one talks to exactly one external API and knows nothing about the other two.

## Status at a glance

| Script | Source | Device | Status |
|---|---|---|---|
| `harvest_movies_tv.py` | TMDB | This device | **Tested and working.** Produced the original 40 movie/TV items |
| `harvest_games.py` | RAWG | Windows teammate | **Run against live Aiven.** Inserted 20 games; warns heavily on missing `action` slug (4 games linked to zero genres) |
| `harvest_music.py` | Deezer | MacBook teammate | **Run against live Aiven.** Inserted 10 chart tracks; aliases + `Other` fallback in use (1 track linked to `Other`) |

A one-off live harvest populated all four media types. Scheduled per-device midnight runs are still the intended steady state.

## The shared design

All three scripts follow the same shape, and the similarity is intentional — it means a fix to one translates directly to the others.

- **One API per script, one script per device.** Keeps memory and connection load light on any single student laptop, and means a bad key or an outage on one device can't take the other two harvests down.
- **Run once per invocation, no internal loop.** Scheduling is external: midnight trigger via cron on macOS or Task Scheduler on Windows. There's nothing to keep alive between runs.
- **Upsert, don't insert.** Every script uses `INSERT ... ON DUPLICATE KEY UPDATE` against `items`, refreshing `popularity_score` and stamping `harvested_at`, leaning on `UNIQUE (media_type, external_id)` to detect the collision.
- **Link genres with `INSERT IGNORE`.** Re-linking an existing (item, genre) pair is a silent no-op.
- **Resolve the item ID defensively.** After the upsert, `cursor.lastrowid` gives the new ID on a fresh insert but is falsy on an update, so each script falls back to a `SELECT id FROM items WHERE media_type = ... AND external_id = ...`.
- **Never insert a genre row at harvest time.** An unmatched genre is skipped. The music script is the one exception in linking, not in creating: if none of a track's names match, it links the pre-seeded `Other` row. It does not `INSERT` into `genres`.
- **Store the whole raw response.** `json.dumps(entry)` goes into `items.metadata`, so nothing from the API is lost even though only four fields are promoted to columns.

## `harvest_movies_tv.py` — TMDB

The only harvester with real mileage.

Hits `https://api.themoviedb.org/3/trending/{movie|tv}/day` — TMDB has a genuine trending endpoint, and there's one per media type. The response shape is identical for both, so a single `harvest_trending(connection, media_type)` function handles each in turn and writes `media_type` of `'movie'` or `'tv'` accordingly.

Per-item handling:

- **Title:** `entry.get("title") or entry.get("name")`. TV entries use `name`, movies use `title`.
- **Popularity:** TMDB's own `popularity` float, used directly.
- **Genres:** TMDB returns `genre_ids` as numeric IDs on each entry, which are looked up against `genres.external_id` scoped to the same `media_type`.

The `media_type` scoping on the genre lookup matters: TMDB reuses numeric IDs across movie and TV genres where the genre is shared (`'35'` is Comedy in both) but not where it isn't, so a movie's `'10759'` and a TV show's `'10759'` must not resolve to the same row.

Requires `TMDB_API_KEY` in `.env`, and raises immediately at startup if it's missing.

## `harvest_games.py` — RAWG

**Run against live Aiven** with a working `RAWG_API_KEY`. Raises immediately if the key is absent.

Hits `https://api.rawg.io/api/games` with `ordering=-added` and `page_size=20`.

**RAWG has no "trending today" endpoint** the way TMDB does. `-added` — most recently added to users' libraries — is RAWG's own recommended proxy for currently-popular titles. If a different notion of trending is wanted later (say highest-rated this month), it's a one-line change to the `ordering` parameter.

Per-item handling:

- **Popularity:** RAWG exposes no single 0–100 popularity field. `game["added"]` — how many users have the game in a list — is the closest equivalent and is what fills `popularity_score`. So `popularity_score` is not comparable across media types; it's a raw count here and a TMDB float in the movies branch.
- **Genres:** RAWG puts genre **slugs** directly on each game, and those are the same slugs already used as `external_id` in `genres`. No numeric-ID translation step is needed, unlike the TMDB branch.

When a game arrives with a slug outside the seeded game genres, the script warns and skips the link. The live catalog is **missing `action`** — the first harvest logged 17 warnings for that slug alone, and four games (including GTA V and RDR2) ended with zero `item_genres` rows because `action` was their only (or only unmatched) tag.

RAWG was kept over IGDB earlier despite signup friction — see [08-DECISIONS.md](08-DECISIONS.md). The open gap now is the missing `action` genre row (and Brain mapping), not the API key.

## `harvest_music.py` — Deezer

**Run against live Aiven.** Deezer's public chart and album endpoints require no API key for read-only access, so this script has no key check and connects straight to the database.

Hits `https://api.deezer.com/chart/0/tracks` for the chart, then `https://api.deezer.com/album/{id}` once per track.

Per-item handling:

- **Popularity:** `track["rank"]`, Deezer's own ranking figure.
- **Rate limiting:** a `time.sleep(0.2)` after each track, since the loop makes an extra request per track.

### Genre matching (aliases + Other fallback)

Deezer track objects don't carry genre. Genre lives on the **album**, which forces one extra API call per track just to reach it. `fetch_album_genre_names()` makes that call, returns the album's genre names, and returns an empty list if the album has no genre data or the request fails.

Matching is still **by name** against `genres.name` — there's no Deezer genre ID seeded into `external_id`. The flow in `link_item_genres()` is:

1. **Exact match** on the Deezer name against a music row in `genres`.
2. **Alias map** for known near-misses (`Dance` → `Dance/EDM`, `Rap/Hip Hop` → `Rap/Hip-Hop`, `Jazz` → `Jazz/Acoustic`, `Electro` → `Techno`).
3. **Fallback to `Other`** only when *zero* names on the track linked — so a track that matched Pop but also had an unmatched "Indie Rock" keeps Pop and does not get Other. Individual unmatched names are still silently skipped in that case.

`Other` is the eleventh music genre (see `add_other_music_genre.sql`), mapped to all five moods at relevance `0.25` so unmatched tracks stay recommendable but ranked below curated genres. Apply that SQL via `run_add_other_music_genre.py` before the music harvest runs.

## Cross-cutting notes

**All three harvesters pass SSL the same way as `app.py`.** Each builds a `DB_CONFIG` with `host`, `port`, `user`, `password`, `database=os.getenv("DB_NAME", ...)`, `ssl_ca=os.getenv("DB_SSL_CA")`, and `ssl_verify_cert=True`. That matches `app.py`, `test_query.py`, and the runner scripts, so Aiven connections work from every device without a special case.

**Their setup docstrings list the required `.env` keys**, including `DB_NAME` and `DB_SSL_CA`. Prefer [07-SETUP.md](07-SETUP.md) if anything drifts.

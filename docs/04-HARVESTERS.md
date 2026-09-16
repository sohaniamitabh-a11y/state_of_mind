# 04 — Harvesters

Three standalone scripts that fill the `items` and `item_genres` cache. Each one talks to exactly one external API and knows nothing about the other two.

## Status at a glance

| Script | Source | Device | Status |
|---|---|---|---|
| `harvest_movies_tv.py` | TMDB | This device | **Tested and working.** Produced the 40 items currently in the database |
| `harvest_games.py` | RAWG | Windows teammate | **Written, never run for real.** Blocked on a RAWG API key — rawg.io signup has been unreliable |
| `harvest_music.py` | Deezer | MacBook teammate | **Written, never run for real.** Not blocked on anything — Deezer's public endpoints need no key — simply untested |

Teammates haven't finished onboarding, so in practice only the movies/TV harvester has ever executed against the live database. That's why `items` contains movies and TV only.

## The shared design

All three scripts follow the same shape, and the similarity is intentional — it means a fix to one translates directly to the others.

- **One API per script, one script per device.** Keeps memory and connection load light on any single student laptop, and means a bad key or an outage on one device can't take the other two harvests down.
- **Run once per invocation, no internal loop.** Scheduling is external: midnight trigger via cron on macOS or Task Scheduler on Windows. There's nothing to keep alive between runs.
- **Upsert, don't insert.** Every script uses `INSERT ... ON DUPLICATE KEY UPDATE` against `items`, refreshing `popularity_score` and stamping `harvested_at`, leaning on `UNIQUE (media_type, external_id)` to detect the collision.
- **Link genres with `INSERT IGNORE`.** Re-linking an existing (item, genre) pair is a silent no-op.
- **Resolve the item ID defensively.** After the upsert, `cursor.lastrowid` gives the new ID on a fresh insert but is falsy on an update, so each script falls back to a `SELECT id FROM items WHERE media_type = ... AND external_id = ...`.
- **Never invent a genre.** If an incoming genre can't be matched to a row in `genres`, the script skips that link and moves on. It does not create genre rows on the fly. Two of the three print a warning when this happens.
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

**Blocked: no RAWG API key yet.** The rawg.io signup flow has been unreliable, so this script has never made a real request. The code is complete and raises immediately if `RAWG_API_KEY` is absent.

Hits `https://api.rawg.io/api/games` with `ordering=-added` and `page_size=20`.

**RAWG has no "trending today" endpoint** the way TMDB does. `-added` — most recently added to users' libraries — is RAWG's own recommended proxy for currently-popular titles. If a different notion of trending is wanted later (say highest-rated this month), it's a one-line change to the `ordering` parameter.

Per-item handling:

- **Popularity:** RAWG exposes no single 0–100 popularity field. `game["added"]` — how many users have the game in a list — is the closest equivalent and is what fills `popularity_score`. So `popularity_score` is not comparable across media types; it's a raw count here and a TMDB float in the movies branch.
- **Genres:** RAWG puts genre **slugs** directly on each game, and those are the same slugs already used as `external_id` in `genres`. No numeric-ID translation step is needed, unlike the TMDB branch.

When a game arrives with a slug outside the seeded game genres, the script warns and skips the link.

RAWG's reliability problems were weighed against switching to IGDB and RAWG was kept — see [08-DECISIONS.md](08-DECISIONS.md) for why.

## `harvest_music.py` — Deezer

**Written but never run.** Nothing blocks it: Deezer's public chart and album endpoints require no API key for read-only access, so this script has no key check at all and connects straight to the database. It just hasn't been executed for real yet.

Hits `https://api.deezer.com/chart/0/tracks` for the chart, then `https://api.deezer.com/album/{id}` once per track.

Per-item handling:

- **Popularity:** `track["rank"]`, Deezer's own ranking figure.
- **Rate limiting:** a `time.sleep(0.2)` after each track, since the loop makes an extra request per track.

### The known genre gap

This is the script's real weakness and it's documented in its own header.

Deezer track objects don't carry genre. Genre lives on the **album**, which forces one extra API call per track just to reach it. `fetch_album_genre_names()` makes that call, returns the album's genre names, and returns an empty list if the album has no genre data or the request fails.

Worse, matching is done **by name** against `genres.name` — there's no reliable ID to match on, because automated fetching of Deezer's full genre list was blocked earlier in the project and their genre ID/name list was never independently verified. Deezer's genre vocabulary doesn't line up one-to-one with the ten hand-curated music genre names in the database, so unmatched genres are silently skipped rather than guessed at.

Expect a meaningful number of tracks to land in `items` with zero rows in `item_genres`. **This is a known limitation, not a bug.** The practical consequence is significant: an item with no `item_genres` rows can never be returned by the recommendation join, so those tracks would be dead weight in the cache until the gap is addressed.

## Cross-cutting notes

**The harvesters don't pass SSL parameters.** All three build a `DB_CONFIG` dict with `host`, `port`, `user`, `password`, and a hardcoded `"database": "state_of_mind"`. None of them read `DB_SSL_CA` or set `ssl_verify_cert`, unlike `app.py`, `test_query.py`, and the four runner scripts, which all do. `harvest_movies_tv.py` was nonetheless tested working against the live Aiven instance. This inconsistency is worth reconciling before the games and music harvesters run on teammates' machines, so all six-plus scripts connect the same way.

**Database name is hardcoded in the harvesters** as `"state_of_mind"`, whereas every other script reads `DB_NAME` from the environment.

**Their setup docstrings are slightly out of date** — each lists the four DB variables plus its own API key, but omits `DB_NAME` and `DB_SSL_CA`, which the rest of the project relies on. Follow [07-SETUP.md](07-SETUP.md) rather than the in-file docstrings.

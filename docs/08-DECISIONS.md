# 08 — Decisions and Rationale

Choices that were made deliberately, and why. Recorded so they don't get "fixed" by someone who assumes they were accidents.

---

## Mood is passed as a string, not a numeric ID

`/get-state?mood=Happy/Excitement`, matched against `moods.name` — not `?mood=1` matched against `moods.id`.

**Why:** the frontend offers exactly five fixed mood buttons and never accepts free text. The set of possible values is closed, small, and known at compile time on the client. Nothing on the client side is ever going to construct a mood value dynamically or need to enumerate moods from the API, so the usual argument for surfacing opaque IDs doesn't apply here.

What that buys: URLs and logs that are readable without a lookup, and no client-side dependence on whatever auto-increment IDs a given seed run happened to produce.

**The cost, accepted knowingly:** renaming a mood becomes a breaking API change, and the exact strings — including the slash — are now part of the contract. Those strings are: `Happy/Excitement`, `Calm/Serene`, `Sad/Melancholy`, `Anger/Rage`, `Confusion/Anxiety`.

---

## An invalid or unmatched mood returns 404

Not an empty 200, not a fallback set of generic recommendations.

**Why:** it follows directly from the decision above. Because the client can only ever emit one of five known strings, a mood that doesn't match is not a user searching for something niche — it's a bug, a stale client, or a hand-typed URL. Silently returning an empty list would hide that.

**The contract:** on a 404, the frontend sends the user back to the mood-picker screen. There is no partial or degraded state to render, so there's no point designing an empty-results view.

Not yet implemented — this is stage 6. See [05-BACKEND.md](05-BACKEND.md).

---

## Sort is relevance first, popularity as tiebreaker — never averaged

```sql
ORDER BY mood_genre_mapping.relevance_score DESC, items.popularity_score DESC
```

**Why:** the entire point of the app is mood-fit, not trending. Averaging or otherwise blending the two scores would let a very popular, poorly-fitting item outrank a strong mood match — which is precisely the behaviour the project exists to avoid. If someone in Sad/Melancholy asks for something that fits, handing them this week's biggest action release because its popularity number is large would be a failure of the product, not a ranking nuance.

So relevance strictly dominates. Popularity only breaks ties **within** an identical relevance score, choosing the better-known of two equally good fits.

There's a second, more practical reason not to blend them: `popularity_score` isn't on a shared scale. It holds a TMDB popularity float for movies and TV, a RAWG "added" count for games, and a Deezer rank for tracks. Any arithmetic combining it with a normalised 0–1 relevance score would be meaningless across media types. Keeping it as a pure tiebreaker inside a single bucket sidesteps that entirely.

---

## RAWG kept over IGDB, despite the reliability problems

RAWG has been the weak link — the rawg.io signup flow has been unreliable enough that the API key still hasn't been obtained, which is why `harvest_games.py` has never run for real. IGDB was considered as a replacement.

**Decision: stay on RAWG for now. Deferred, not settled.**

**Why:** RAWG's genre slugs aren't confined to the harvester. They're baked in as `external_id` values across three separate SQL files — the initial seed, the genre expansion, and the mapping inserts that resolve `genre_id` by looking those slugs up. Switching to IGDB would mean remapping every game genre identifier across all three, and any `mood_genre_mapping` row whose subquery no longer resolves would fail to insert. That's a disruptive change to make while the games pipeline hasn't produced a single row yet, and while the rating survey for the expanded genre list is still outstanding.

The trade being accepted: a known-annoying signup process, versus a coordinated three-file migration plus re-verification of the game rows in the Brain. For now, the annoyance is cheaper.

Worth revisiting if the key genuinely can't be obtained — at that point the migration cost stops being avoidable.

---

## Cached database, no live API calls at query time

The read path never touches TMDB, RAWG, or Deezer. Harvesters populate `items` and `item_genres` on a schedule; `/get-state` serves purely from the database.

**Why:** recommendations come back instantly, a request can't fail because a third party is down or rate-limiting, and no API key is ever exposed on the read path. It also means the harvesters can afford to be slow and chatty — `harvest_music.py` makes an extra album call per track with a 0.2s sleep, which would be unacceptable in a request handler and is completely fine at midnight.

**The cost:** the catalog is only as fresh as the last harvest, and content that hasn't been harvested doesn't exist as far as the app is concerned.

---

## New capability arrives as rows, never as columns or tables

> "A brain shall never be restricted to specific data."

`genres.media_type` and `items.media_type` are `VARCHAR(50)`, not enums or lookup FKs. A sixth mood is one INSERT. A whole new domain — food, makeup — is a new `media_type` string plus genre rows plus a new harvester, with no migration to the five existing tables.

`items.metadata` as a `JSON` blob is the same principle applied to per-item shape: an artist name for a track, a cuisine for a food item, goes into the blob rather than becoming a column that's NULL for every other media type.

**The cost, accepted:** the database won't stop anyone from writing `'Movie'` or `'movies'` and quietly producing rows that never join to anything. Nothing enforces the vocabulary; consistency is a convention held by the harvesters. There's also no way to query "all fields of a track" from the schema alone.

---

## One API per script, one script per device

Three harvesters, each hitting exactly one source, each assigned to one teammate's machine: movies/TV on this device, games on the Windows teammate's, music on the MacBook.

**Why:** it keeps memory and connection load light on any single student laptop, and it isolates failures — a bad key or an outage on one device doesn't take the other two harvests down. It also means no single machine holds more than one API key.

**The cost, currently very visible:** the system's completeness is gated on teammate onboarding. Because the other two devices aren't set up yet, `items` contains movies and TV only, and the backend's bucketing work has no real music or games data to test against.

---

## Scheduling lives outside the code

Each harvester runs once per invocation and exits. There's no internal loop, no daemon, no orchestrator. The midnight trigger is cron on macOS or Task Scheduler on Windows, configured per device.

**Why:** nothing has to stay alive between runs, and a crash is just a failed job rather than a dead process that silently stops harvesting. It also fits the one-script-per-device split — each machine schedules only its own job.

**The cost:** scheduling isn't captured anywhere in the repo, so it has to be set up by hand on each device and can't be verified by reading the code.

---

## Idempotent harvests via upsert

`INSERT ... ON DUPLICATE KEY UPDATE` against `items` (leaning on `UNIQUE (media_type, external_id)`), refreshing `popularity_score` and `harvested_at`; `INSERT IGNORE` for `item_genres`.

**Why:** a nightly harvest re-encounters most of yesterday's trending list. Upserting means the cache updates in place rather than growing a duplicate row per night, and it makes a manual re-run harmless — useful when debugging.

---

## Harvesters never create genre rows on the fly

If an incoming genre can't be matched to an existing row in `genres`, the harvester skips the link and continues. It does not insert a new genre.

**Why:** a genre row with no `mood_genre_mapping` score is invisible to the recommendation engine anyway — the join can't reach items tagged with it. Auto-creating genres would grow the catalog with rows that do nothing while making it look like coverage exists. Skipping keeps `genres` aligned with what's actually been rated, and the printed warnings surface the gap honestly.

**Music exception that still obeys the rule:** `harvest_music.py` does not invent genre rows at harvest time. Near-miss Deezer names are remapped through a fixed alias table onto the curated buckets, and when a track matches none of them it links the pre-seeded `Other` genre (added by `add_other_music_genre.sql`, with Brain rows at relevance `0.25` for every mood). Individual unmatched names are still skipped when another name on the same track already matched. See [04-HARVESTERS.md](04-HARVESTERS.md).

---

## Deezer aliases + fallback `Other` over importing the full Deezer genre list

**Decision:** keep the eleven curated music buckets (ten originals + `Other`), alias clear near-misses in code, and fall back to `Other` when nothing matches.

**Why:** importing Deezer's full primary list (27+) would mean hand-curating dozens of new mood scores and diluting the small, rated vocabulary the Brain is built on. Exact-name matching alone was losing a large share of tracks from the recommendation join. Aliases recover the near-misses (`Dance` / `Rap/Hip Hop` / `Jazz` / `Electro`); `Other` at low relevance keeps the rest recommendable without pretending they fit a specific curated bucket.

**The cost accepted:** `Other` is less specific than a real genre, and tracks that land there will surface under every mood at the same low weight. That is preferable to silent disappearance. Revisit if survey ratings later justify expanding the music catalog.

---

## Mapping inserts resolve IDs by subquery, not hardcoded integers

```sql
(SELECT id FROM moods WHERE name = 'Happy/Excitement'),
(SELECT id FROM genres WHERE media_type = 'movie' AND external_id = '35'),
```

**Why:** `mood_genre_mapping_inserts.sql` stays correct regardless of what auto-increment IDs a given seed run produced, so the file can be applied to a freshly rebuilt database without editing. It also makes the file readable as a record of the ratings themselves.

**The cost:** if a subquery finds nothing it yields NULL and the INSERT fails against the NOT NULL column — which is why the music rows carry an in-file instruction to verify exact spellings first. That failure mode is preferable to a hardcoded integer silently attaching a score to the wrong genre.

---

## Runner scripts strip comments before splitting on semicolons

The four `run_*.py` scripts (plus `run_add_other_music_genre.py`) drop every blank line and every line starting with `--`, then split the remainder on `;`.

**Why:** splitting a `.sql` file on semicolons breaks as soon as a comment contains one, or a comment block gets glued to the front of the following statement. Stripping comments first makes the naive split safe. And the split is necessary at all because these files have to be applied to a remote SSL-required Aiven instance rather than opened in a local client.

**The consequence:** the extensive teaching comments in `schema.sql` and the other SQL files never reach MySQL. They exist for human readers only.

---

## `DECIMAL(4,2)` and `DECIMAL(10,2)` always specify scale

**Why:** bare `DECIMAL` in MySQL defaults to **zero** decimal places. A `relevance_score` of `0.90` would be silently rounded to `1`, and every weight in the Brain would collapse to 0 or 1 — destroying the ranking without raising a single error. Explicit scale is not stylistic here.

---

## Foreign keys written as separate clauses, not inline

`FOREIGN KEY (mood_id) REFERENCES moods(id)` as its own table-level clause, rather than `mood_id INT REFERENCES moods(id)` on the column.

**Why:** MySQL parses the inline column-level form and then silently ignores it — the constraint is never created, and you find out much later when orphaned rows appear. Other databases honour the inline form, which makes this an easy trap to walk into. The explicit clause is the one that actually sticks.

---

## The emoji-inference approach was abandoned

`dynamic_data_gathering_schema.sql` sketches five tables (`emojis`, `emoji_mood_weights`, `questions`, `user_sessions`, `session_responses`) for a design in which the app would have shown deliberately generic questions answered by emoji taps, accumulated a confidence "DataScore" over 5–8 questions, and **inferred** the user's mood instead of asking for it.

**This is a dead file.** It was never executed, nothing references it, those tables don't exist in the live database, and it is **not a roadmap item.** It's documented here and in [02-DATABASE.md](02-DATABASE.md) only so that nobody reading the repo mistakes it for planned work.

The shipped design asks the user their mood directly, with five buttons. `schema.sql` alone is the source of truth for the schema.

---

## Open questions, deliberately deferred

Not decisions yet — things consciously left unresolved.

- **Whether to migrate off RAWG.** Deferred above; forced if the key never materialises.
- **Whether `feedback` ever gets wired up.** The table exists and is empty; there's no feedback loop and the Brain doesn't learn.
- **Whether to expand the music catalog beyond aliases + Other** if survey ratings later justify more Deezer-aligned buckets.

---

## Harvesters use the same SSL + `DB_NAME` connect path as `app.py`

All three harvesters read `DB_NAME` and `DB_SSL_CA` and set `ssl_verify_cert=True`, matching `app.py` and the runner scripts.

**Why:** Aiven requires verified SSL. Leaving harvesters on a bare connect (or a hardcoded database name) meant games/music could fail on teammates' machines even when the runners worked, and a non-default `DB_NAME` would silently point the API at one database and the harvesters at another.

**The cost:** every device must have a valid `DB_SSL_CA` path in `.env` (the repo ships `ignore/ca.pem`). That was already true for runners and `app.py`.

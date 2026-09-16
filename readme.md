# State of Mind

A mood-based cross-media recommendation engine. Pick how you're feeling — the engine hands back Movies, TV, Music, and Games that actually fit that headspace.

No sign-up, no live API calls at query time. Everything runs off a cached cloud database, refreshed periodically by scheduled harvesters, so recommendations are instant.

**A 3-person college project, in active development.** The sections below say plainly what works today and what doesn't.

📖 **Full documentation lives in [`/docs`](docs/) — start with [00-OVERVIEW.md](docs/00-OVERVIEW.md).**

## Core idea

> "A brain shall never be restricted to specific data."

New moods, genres, or media domains get added as new **rows**, never new tables or columns. `media_type` is a plain string rather than an enum, so adding a whole new domain later needs no schema migration. The system is built to grow without structural rewrites.

## How it works

Two paths that never touch each other. Nothing on the read path calls a third-party API.

```
WRITE PATH — offline, scheduled at midnight, one device per source
  TMDB   ──▶ harvest_movies_tv.py  ─┐
  RAWG   ──▶ harvest_games.py      ─┼──▶  Aiven MySQL  ──▶  items + item_genres
  Deezer ──▶ harvest_music.py      ─┘

READ PATH — per user request
  Flutter app ──▶ GET /get-state?mood=Happy/Excitement ──▶ Flask
                     ──▶ one join: moods → mood_genre_mapping → item_genres → items
                     ──▶ ranked recommendations
```

Ranking is **`relevance_score` first, `popularity_score` only as a tiebreaker** — never averaged together. Mood-fit is the entire point of the app, so a wildly popular but badly-fitting title must not outrank a strong match. Reasoning in [08-DECISIONS.md](docs/08-DECISIONS.md).

## Status

| Component | Status | Detail |
|---|---|---|
| **The Brain** | Done / live | `mood_genre_mapping` — 46 weighted mood-to-genre rows from team ratings. 74 more queued, awaiting survey results |
| **The Harvester** | Partial | Movies/TV tested and working. Games blocked on a RAWG API key. Music written but never run |
| **The Backend / Engine** | Stage 4 of 7 | Join query live on `/get-state`, returns raw duplicated rows. Stage 5 (dedupe, bucketing, top-5 cap) in progress |
| **Frontend** | Not started | Planned Flutter app — five fixed mood buttons, no free-text input. Zero code yet |

**Live database right now:** 5 moods, 63 genres, 46 Brain rows, 40 items (movies and TV only — no games or music harvested yet), `item_genres` populated from those items, `feedback` empty and unused.

### Backend stages

Built deliberately as a step-by-step learning project rather than from a generic tutorial.

- [x] **Stage 1** — Basic Flask app, run/debug mode
- [x] **Stage 2** — Reading query params (`/get-state?mood=X`) via `request.args`
- [x] **Stage 3** — Live connection to the cloud DB from inside a request
- [x] **Stage 4** — The full mood → genre → items join query, wired into the live route
- [ ] **Stage 5** — Shaping the response: dedupe results, bucket into movies_tv / music / games, cap at top 5 each
- [ ] **Stage 6** — Error handling (404 on invalid/missing mood)
- [ ] **Stage 7** — Testing the API standalone, without the frontend

Stage 5 is partly done: the dedupe works in `test_query.py` but hasn't been merged into `app.py` yet. Bucketing and the cap haven't been started. See [05-BACKEND.md](docs/05-BACKEND.md).

## What's in this repo

Every file, and what it's for. Files are currently flat in the root; nothing has been reorganised yet.

### The application

| File | Purpose |
|---|---|
| `app.py` | The Flask API. Two routes: `/` liveness, and `/get-state?mood=X` which runs the recommendation join |
| `test_query.py` | Standalone runner for the same join with the mood hardcoded, plus the stage-5 dedupe logic that isn't in `app.py` yet |

### Harvesters — one API each, one device each

| File | Source | Status |
|---|---|---|
| `harvest_movies_tv.py` | TMDB trending movies + TV | Tested and working — produced the current 40 items |
| `harvest_games.py` | RAWG games, ordered by `-added` | Written, never run — no RAWG API key yet |
| `harvest_music.py` | Deezer chart tracks | Written, never run — needs no key, just untested |

### Schema and seed data

| File | Purpose |
|---|---|
| `schema.sql` | The six tables. Heavily commented with the reasoning behind each column choice |
| `seed_mood_genre.sql` | The 5 moods and the first 38 genres |
| `expand_genres.sql` | 25 further genres, bringing the catalog to 63 |
| `mood_genre_mapping_inserts.sql` | The Brain — 46 mood-genre relevance scores, one INSERT per pair |

### Runners and checks

Each runner applies exactly one SQL file to the remote SSL-required database, and is safe to re-run — duplicates are skipped rather than raised.

| File | Applies |
|---|---|
| `run_schema.py` | `schema.sql` |
| `run_seed.py` | `seed_mood_genre.sql` |
| `run_expand_genres.py` | `expand_genres.sql` |
| `run_mapping.py` | `mood_genre_mapping_inserts.sql` |
| `check_table.py` | Nothing — prints row counts for `moods` and `genres` as a sanity check |

### Other

| Path | Purpose |
|---|---|
| `docs/` | Full project documentation — architecture, database, decisions |
| `ignore/ca.pem` | Aiven SSL CA certificate, referenced by `DB_SSL_CA` |
| `ignore/gitignore` | A copy of the gitignore rules. Note: the `ignore/` folder is **not** itself git-ignored |
| `dynamic_data_gathering_schema.sql` | **Dead file — abandoned, not a roadmap item.** An emoji-based mood-inference design that was dropped. Never run, nothing references it, its tables don't exist in the live database. Kept only as a historical artifact |

## Tech stack

- **Backend:** Python (Flask), MySQL (Aiven cloud, SSL required)
- **Data sources:** TMDB (movies/TV), RAWG (games), Deezer (music)
- **Frontend (planned):** Flutter
- **Data prep:** Python runner scripts for the schema/seed/mapping SQL; Google Forms for the genre-mood survey ratings

## Quickstart

```bash
pip install requests mysql-connector-python python-dotenv flask
```

Create a `.env` in the project root — never committed:

```
DB_HOST=...
DB_PORT=...
DB_USER=...
DB_PASSWORD=...
DB_NAME=state_of_mind
DB_SSL_CA=...
# plus whichever single API key that device's harvester needs
```

Each device only needs the one key for its own harvester: `TMDB_API_KEY` for movies/TV, `RAWG_API_KEY` for games, none at all for music.

Verify the connection, then run the API:

```bash
python check_table.py     # expect: moods: 5, genres: 63
python app.py             # then try /get-state?mood=Happy/Excitement
```

If you're setting up a fresh database rather than connecting to the shared one, the SQL has to be applied in a specific order — foreign keys enforce it. Full instructions in [07-SETUP.md](docs/07-SETUP.md).

## Documentation

| Doc | Covers |
|---|---|
| [00-OVERVIEW.md](docs/00-OVERVIEW.md) | What the project is and exactly where it stands |
| [01-ARCHITECTURE.md](docs/01-ARCHITECTURE.md) | How the pieces fit together; the join that is the engine |
| [02-DATABASE.md](docs/02-DATABASE.md) | All six tables, column by column, with the genre breakdown |
| [03-DATA-PIPELINE.md](docs/03-DATA-PIPELINE.md) | The mandatory run order and how the runner scripts work |
| [04-HARVESTERS.md](docs/04-HARVESTERS.md) | The three collectors, their status and known limitations |
| [05-BACKEND.md](docs/05-BACKEND.md) | The seven stages, what stage 5 still needs, known rough edges |
| [06-BRAIN-AND-RATINGS.md](docs/06-BRAIN-AND-RATINGS.md) | Where relevance scores come from and how they're calculated |
| [07-SETUP.md](docs/07-SETUP.md) | Per-device setup and teammate onboarding |
| [08-DECISIONS.md](docs/08-DECISIONS.md) | Every significant design decision, its reasoning, and its cost |
| [09-COMMIT-HISTORY.md](docs/09-COMMIT-HISTORY.md) | What each existing commit actually changed |

Contributing conventions — including commit message format — are in [CONTRIBUTING.md](CONTRIBUTING.md).

## Team

A 3-person college mini-project. Each teammate's device runs one harvester against the shared cloud database: movies/TV, games, or music. Teammates are still onboarding, so only the movies/TV harvester has run against real data so far — which is why `items` currently holds movies and TV only.

# 07 — Setup

Getting a device running against the shared database. Note that a device does **not** need every API key — it needs only the key for the one harvester assigned to it.

## Prerequisites

Python 3, and access credentials for the shared Aiven MySQL instance.

## Dependencies

```
pip install requests mysql-connector-python python-dotenv flask
```

| Package | Used by |
|---|---|
| `mysql-connector-python` | Everything — all DB access |
| `python-dotenv` | Everything — loads `.env` |
| `requests` | The three harvesters |
| `flask` | `app.py` |

## The `.env` file

Every device needs its own `.env` in the project root. **It is never committed** — `.gitignore` covers `.env` and `config.properties`.

```
DB_HOST=...
DB_PORT=...
DB_USER=...
DB_PASSWORD=...
DB_NAME=state_of_mind
DB_SSL_CA=...
# plus whichever single API key that device's harvester needs
```

Per-device API key:

| Device / role | Key needed |
|---|---|
| Movies/TV (this device) | `TMDB_API_KEY` |
| Games (Windows teammate) | `RAWG_API_KEY` — obtained; first live harvest completed |
| Music (MacBook teammate) | none — Deezer's public read endpoints need no key |

Nobody needs all three. One API per device is deliberate — see [04-HARVESTERS.md](04-HARVESTERS.md).

### `DB_SSL_CA`

The Aiven instance requires SSL. `DB_SSL_CA` is a path to the CA certificate, which is present in the repo at `ignore/ca.pem`. `app.py`, `test_query.py`, the runner scripts, and all three harvesters pass it as `ssl_ca` alongside `ssl_verify_cert=True`, and will fail to connect without it.

Harvesters also read `DB_NAME` (defaulting to `state_of_mind` if unset), same as the runners and `app.py`.

## First-time database setup

Only needed once per database, not once per device — the three devices share one cloud instance, so if the tables and seed data are already there, skip to "Running things".

Run in this exact order. Foreign keys make the ordering mandatory, not just advisory.

```
python run_schema.py                  # creates the 6 tables
python run_seed.py                    # 5 moods + first 38 genres
python run_expand_genres.py           # +25 genres, total 63
python run_mapping.py                 # the original 46 mood_genre_mapping rows
python run_add_other_music_genre.py   # music Other + 5 Brain rows → 64 genres, 51 mappings
```

All five are safe to re-run. Each catches the relevant "already exists" or "duplicate entry" error, prints a skip message, and continues; anything else raises and stops the run. Details in [03-DATA-PIPELINE.md](03-DATA-PIPELINE.md).

Each runner is hardcoded to exactly one `.sql` file, so there are no arguments to pass.

Verify:

```
python check_table.py
```

Expect `moods: 5` and `genres: 64`. That script only covers those two tables — confirming the other four means querying by hand.

## Running things

**The backend:**

```
python app.py
```

Serves on Flask's development server with `debug=True` (auto-reload, interactive debugger). Development-only.

Try it with `GET /get-state?mood=Happy/Excitement`. Note that the mood must match a `moods.name` value exactly, and that the response today is raw duplicated rows in an f-string rather than JSON — see [05-BACKEND.md](05-BACKEND.md).

**A harvest, manually:**

```
python harvest_movies_tv.py     # tested and working
python harvest_games.py         # needs RAWG_API_KEY; live run done (warns on missing action slug)
python harvest_music.py         # no key needed; live run done (Other fallback available)
```

Each runs once and exits. There's no internal loop.

**A harvest, scheduled:** scheduling lives outside the code, at the OS level on the device that owns that harvester — cron on macOS, Task Scheduler on Windows, midnight trigger. Nothing in the repo configures this; it's set up per machine.

**The standalone query test:**

```
python test_query.py
```

Runs the same join as `/get-state` with the mood hardcoded to `Happy/Excitement`, then applies the stage-5 dedupe logic and prints the result. This is where that dedupe currently lives — it hasn't been merged into `app.py` yet.

## Onboarding a teammate

The current state is that teammates haven't finished onboarding, so the movies/TV device is the only one that has ever run a harvest. For a new device:

1. Install Python and the four packages.
2. Get the shared DB credentials and a copy of `ca.pem`; create the local `.env`.
3. Add the one API key for that device's harvester — or none, for music.
4. Skip the database setup steps; the shared instance is already seeded.
5. Verify connectivity with `python check_table.py`.
6. Run that device's harvester manually once before scheduling it.
7. Set up the midnight OS-level schedule.

## A note on the repo layout

The `ignore/` directory holds `ca.pem` and a copy of the gitignore rules. Despite the directory name, it is **not** git-ignored — `.gitignore` lists `.env` and `config.properties` but not `ignore/`, so both files in there are tracked. That's fine for a CA certificate, which is public by nature, but the naming is misleading enough to be worth knowing before anyone puts a real secret in that folder assuming it's excluded.

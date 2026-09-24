# 03 — Data Pipeline

How data actually gets into the database, in the order it has to happen. Everything before the harvest step is one-time setup; the harvest step is the only part that repeats.

## The full sequence

```
 1. schema.sql            via run_schema.py         → creates the 6 tables
 2. seed_mood_genre.sql   via run_seed.py           → 5 moods + first 38 genres
 3. expand_genres.sql     via run_expand_genres.py  → +25 genres, total 63
 4. Google Forms survey   (outside the repo)        → human relevance ratings
 5. mood_genre_mapping_inserts.sql via run_mapping.py → the original 46 Brain rows
 5b. add_other_music_genre.sql via run_add_other_music_genre.py → music Other + 5 Brain rows (total 64 genres, 51 mappings)
 6. harvest_*.py          scheduled, per device     → items + item_genres
 7. app.py                                          → reads all of the above
```

Steps 1 through 5b are done. Step 6 is done for movies/TV only. Step 7's API is through stage 5 of 7: `/get-state` returns deduped, bucketed, top-5 JSON. Stages 6 (404 on a bad mood) and 7 (standalone API testing) are not started.

The ordering is enforced by foreign keys, not by convention. `mood_genre_mapping` has FKs to both `moods` and `genres`, so step 5 physically cannot run before steps 2 and 3. `item_genres` has an FK to `genres`, so a harvest can't link an item to a genre that was never seeded.

## The runner scripts

`run_schema.py`, `run_seed.py`, `run_expand_genres.py`, `run_mapping.py`, and `run_add_other_music_genre.py` are near-identical scripts. Each one exists because the Aiven database is remote and SSL-required, so applying a `.sql` file isn't as simple as opening it in a local client.

They all do the same four things:

1. Load DB credentials from `.env` via `python-dotenv` and connect with `ssl_ca` plus `ssl_verify_cert=True`.
2. Read their target `.sql` file and strip every line that is blank or starts with `--`.
3. Split the remainder on `;` into individual statements.
4. Execute each statement in turn, printing a truncated preview of each.

Each is hardcoded to exactly one SQL file — `run_seed.py` will only ever apply `seed_mood_genre.sql` — so there is no argument to pass and no way to point one at the wrong file by accident.

### Why the comment stripping matters

The naive way to apply a multi-statement SQL file in Python is to split it on semicolons. That breaks the moment a `--` comment contains a semicolon, or a comment sits between two statements and gets glued onto the front of the next one. Stripping comment lines first is what makes the split-on-`;` approach safe here.

The consequence worth knowing: the extensive teaching comments in `schema.sql` and the others are invisible to the runner. They're for humans reading the file, and they never reach MySQL.

### Idempotency, and how it differs per runner

Each runner catches exactly one MySQL error and treats it as "already done":

| Runner | Tolerated error | Effect of re-running |
|---|---|---|
| `run_schema.py` | `ER_TABLE_EXISTS_ERROR` | Prints "Skipped (already exists)", continues |
| `run_seed.py` | `ER_DUP_ENTRY` | Skips rows already seeded, continues |
| `run_expand_genres.py` | `ER_DUP_ENTRY` | Skips rows already seeded, continues |
| `run_mapping.py` | `ER_DUP_ENTRY` | Skips mapping rows already present, continues |
| `run_add_other_music_genre.py` | `ER_DUP_ENTRY` | Skips mapping rows already present; genre insert uses `WHERE NOT EXISTS` |

Any other error is re-raised and stops the run. So all five are safe to re-run: they'll skip what exists and apply what's new. This is what makes `expand_genres.sql` safe to fire at a database that already has the first 38 genres, and what will make the queued 74 Brain rows safe to add to the existing mappings.

The duplicate-skipping relies on the UNIQUE and PRIMARY KEY constraints in the schema doing the real work — `UNIQUE (media_type, external_id)` on `genres` and the composite `PRIMARY KEY (mood_id, genre_id)` on `mood_genre_mapping`. The runners just decline to panic when those constraints fire.

## `check_table.py`

A small verification script. It connects and prints row counts for `moods` and `genres` — nothing else. It's the quick sanity check after running the seed and expansion steps: expect `moods: 5` and `genres: 64`.

It does not cover `mood_genre_mapping`, `items`, `item_genres`, or `feedback`, so confirming those counts currently means querying by hand.

## The repeating part: harvests

Once steps 1 through 5b are in place, the only recurring pipeline activity is the harvest. Each of the three scripts runs once per invocation with no internal loop, triggered at midnight by the host OS scheduler on its assigned device — cron on the MacBook, Task Scheduler on Windows. There is no orchestrator, no queue, and no coordination between the three.

Because `items` has `UNIQUE (media_type, external_id)` and the harvesters use `INSERT ... ON DUPLICATE KEY UPDATE`, a nightly harvest refreshes `popularity_score` and `harvested_at` on items it has seen before rather than accumulating duplicates. Genre links use `INSERT IGNORE`, so re-linking an existing pair is a no-op.

Full detail per source in [04-HARVESTERS.md](04-HARVESTERS.md).

## The human step in the middle

Step 4 — the ratings survey — is the one link in the chain that isn't code and isn't in this repo. Relevance scores are collected through Google Forms, averaged, and hand-transcribed into `mood_genre_mapping_inserts.sql` as literal decimals. There's no script that reads the form responses and generates the SQL; the INSERT statements were written out by hand from the ratings spreadsheet.

That's the current bottleneck on the queued 74 rows. See [06-BRAIN-AND-RATINGS.md](06-BRAIN-AND-RATINGS.md).

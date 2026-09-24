# 09 — Commit History, Decoded

The commit history on `main` is short but not self-explanatory. Four of the ten commits are titled `Add files via upload`, which is the message GitHub writes automatically when files are drag-dropped into the web interface — it says nothing about what changed or why. A couple of the hand-written messages don't match their contents either.

This document says what each commit actually did, so the log is readable without running `git show` on every entry. Conventions for keeping future commits legible are in [CONTRIBUTING.md](../CONTRIBUTING.md).

The history has **not** been rewritten. Rewriting published history means force-pushing over a branch teammates may already have cloned, and the cost of that outweighs a tidy log on a project this size. The log is left intact and explained instead.

## The ten commits, oldest first

| Commit | Date | Message | What it actually did |
|---|---|---|---|
| `5c49173` | 2026-07-21 | Initial commit | Created `README.md` — the repository stub, no project code |
| `83e0125` | 2026-07-21 | Add files via upload | First real content, all inside a `state_of_mind/` subfolder: `schema.sql`, `mood_genre_mapping_inserts.sql`, `dynamic_data_gathering_schema.sql`, `gitignore`, plus `trending_harvester.py` and `config.example.properties` (both later deleted) |
| `6697f58` | 2026-07-21 | Revise README for clarity and completeness | README expanded from a stub to 138 lines |
| `7934490` | 2026-07-30 | Add files via upload | The three harvesters (`harvest_movies_tv.py`, `harvest_games.py`, `harvest_music.py`) and three runners (`run_schema.py`, `run_seed.py`, `run_mapping.py`) — still under `state_of_mind/` |
| `0ee6efc` | 2026-07-30 | Create CODE_OF_CONDUCT.md | Added a GitHub template code of conduct. Deleted again two commits later; the project has no code of conduct today |
| `7cfd019` | 2026-08-02 | Add files via upload | Added `run_expand_genres.py` |
| `79c1044` | 2026-08-03 | Add files via upload | Added `state_of_mind/expand_genres.sql` — the 25-genre expansion the runner above applies |
| `d6ed725` | 2026-08-08 | Stage 4: backend join query — mood to items via genre mapping; add .gitignore | **The big one.** Flattened everything out of `state_of_mind/` into the repo root, deleted `CODE_OF_CONDUCT.md`, `README.md`, `trending_harvester.py` and `config.example.properties`, and added `app.py`, `test_query.py`, `check_table.py`, `seed_mood_genre.sql`, and `ignore/ca.pem`. Despite the message, it did **not** add `.gitignore` |
| `28c5678` | 2026-08-08 | Add updated README with project overview and progress | Added `readme.md` (lowercase) — a fresh 81-line README, since the uppercase one had been deleted in the previous commit |
| `7cca761` | 2026-08-11 | uncopy logic to remove duplicate tuples | Added the dedupe logic to `test_query.py`, **and** added `.gitignore` — the file the previous-but-one commit's message had claimed |

## What landed after that

The table above stops at the last noisy commit. Later work on `main` uses the message format in [CONTRIBUTING.md](../CONTRIBUTING.md). The pieces that changed the documented state of the project:

| Commit | What it did |
|---|---|
| `d6f8ea4` | Merged the `/docs` set and the rewritten README |
| `a47837d` | Added `docs/architecture-baseline.docx` |
| `92583c7` | Added music genre `Other` and five Brain rows at relevance `0.25` (`add_other_music_genre.sql`, `run_add_other_music_genre.py`) |
| `9bb1e88` | `harvest_music.py` aliases near-miss Deezer names and falls back to `Other` when a track matches nothing |
| `1166f68` | Backend stage 5 in `app.py`: dedupe by item id, bucket into `movies_tv` / `music` / `games`, cap at 5, return JSON |

## What the noise actually costs

Worth being concrete, because these aren't cosmetic complaints:

- **The four `Add files via upload` commits** make it impossible to tell from the log when the harvesters arrived, or that the genre expansion SQL and its runner landed in two separate commits a day apart. Anyone bisecting or reviewing has to open each one.
- **`.gitignore` is credited to the wrong commit.** `d6ed725` says "add .gitignore" but `7cca761` actually added it, three days later. That matters: for a stretch, secrets had no ignore rule protecting them.
- **`7cca761` bundles two unrelated changes** — a `.gitignore` and the dedupe logic — under a message describing only one of them.
- **`README.md` became `readme.md`** across `d6ed725` and `28c5678` (delete, then re-add lowercase). Git records that as an unrelated delete and add rather than a rename, and case-only renames are a known hazard on the case-insensitive filesystems that Windows and macOS use by default.

## Files that exist only in history

Two files were added and later deleted. If you find references to them anywhere, this is why they're gone:

- **`trending_harvester.py`** — a single combined harvester, superseded by the three per-source scripts. Removed in `d6ed725`.
- **`config.example.properties`** — an early configuration approach, replaced by `.env` and `python-dotenv`. Removed in `d6ed725`. `.gitignore` still lists `config.properties`, a leftover from this era.

`CODE_OF_CONDUCT.md` was also added and removed. The project currently has none.

## The `state_of_mind/` subfolder

For the first seven commits, project files lived in a `state_of_mind/` directory inside the repository — so the path was `state_of_mind/state_of_mind/schema.sql` from the repo root's perspective. `d6ed725` flattened it. Git tracked most of these as renames with 100% similarity, so the file histories are continuous and `git log --follow` works across the move.

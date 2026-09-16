# 02 — Database

Cloud-hosted Aiven MySQL, database name `state_of_mind`, SSL required. Defined in `schema.sql`. Six tables, and the design rule is that new moods, genres, media types, or whole domains arrive as rows — never as new columns or tables.

## Live row counts

| Table | Rows right now | Note |
|---|---|---|
| `moods` | 5 | Complete; the five moods are fixed |
| `genres` | 64 | Complete for the four current media types (includes music `Other`) |
| `mood_genre_mapping` | 51 | 46 original + 5 for music `Other`; 74 more rows still queued on genre-expansion ratings |
| `items` | 70 | 20 movie, 20 tv, 20 game, 10 music |
| `item_genres` | 119 | From those 70 items |
| `feedback` | 0 | Schema exists, nothing reads or writes it |

## Table 1 — `moods`

```sql
id    INT AUTO_INCREMENT PRIMARY KEY
name  VARCHAR(100) NOT NULL UNIQUE
```

The five moods live here as rows, not hardcoded anywhere else. Adding a sixth is one INSERT with zero schema change.

Seeded values, exact strings (these are what the API matches on, so spelling matters):

1. `Happy/Excitement`
2. `Calm/Serene`
3. `Sad/Melancholy`
4. `Anger/Rage`
5. `Confusion/Anxiety`

`name` is `VARCHAR(100)` rather than `TEXT` because MySQL won't put a UNIQUE constraint on a TEXT column without a prefix length — the index needs a bounded maximum.

## Table 2 — `genres`

```sql
id           INT AUTO_INCREMENT PRIMARY KEY
media_type   VARCHAR(50) NOT NULL
external_id  VARCHAR(100)          -- nullable
name         VARCHAR(100) NOT NULL
UNIQUE (media_type, external_id)
```

Every genre from every source lives in this one table, tagged by `media_type`. Current values are `'movie'`, `'tv'`, `'game'`, `'music'` — a plain string, not an enum, so a future `'food'` domain needs no migration.

`external_id` is the genre's ID in its source API: TMDB's numeric ID (`'28'` for Action), RAWG's slug (`'shooter'`). It's nullable because the music genres were invented rather than pulled from an API and have no source ID.

The UNIQUE constraint is on the **pair**, not on either column alone, because TMDB's `'16'` and RAWG's `'16'` would otherwise collide even though they're unrelated genres.

### Current 64 genres by media type

| media_type | Count | Matched on | Source |
|---|---|---|---|
| `movie` | 19 | `external_id` = TMDB numeric genre ID | TMDB's full movie genre list |
| `tv` | 16 | `external_id` = TMDB numeric genre ID | TMDB's full TV genre list |
| `game` | 18 | `external_id` = RAWG slug | RAWG's genre slugs |
| `music` | 11 | `name` (external_id is NULL) | Hand-curated buckets, not an API list |

These arrived in three passes. `seed_mood_genre.sql` inserted the initial 38 (11 movie, 7 TV, 10 music, 10 game), `expand_genres.sql` later added the missing 25 (8 movie, 9 TV, 8 game), and `add_other_music_genre.sql` added the eleventh music genre `Other` as a Deezer unmatched-name fallback. Movie and TV are at their full TMDB lists; music stays hand-curated because Deezer has no fixed public taxonomy to complete against.

The eleven music genres are `Pop`, `Dance/EDM`, `Rap/Hip-Hop`, `Jazz/Acoustic`, `Blues`, `Classical`, `Metal`, `Punk`, `Techno`, `Ambient/Soundscape`, `Other`. `Ambient/Soundscape` is entirely invented — no source API offers it — and is the clearest example of why `external_id` had to be nullable. `Other` is the catch-all for Deezer names that don't exact-match or alias onto a curated bucket (see [04-HARVESTERS.md](04-HARVESTERS.md)).

**One inconsistency to be aware of:** a trailing comment in `expand_genres.sql` claims the expansion brings game genres "to the full 19", and `harvest_games.py` refers to an "original 19-slug list". The actual count from the two seed files is 18 game genres (10 + 8), which with music at 11 reconciles with the live total of 64. The comments are off by one, not the data.

## Table 3 — `mood_genre_mapping` (the Brain)

```sql
mood_id          INT NOT NULL
genre_id         INT NOT NULL
relevance_score  DECIMAL(4,2) NOT NULL
PRIMARY KEY (mood_id, genre_id)
FOREIGN KEY (mood_id)  REFERENCES moods(id)
FOREIGN KEY (genre_id) REFERENCES genres(id)
```

The weighted link between a mood and a genre — a score rather than a flat yes/no. This is the entire opinion of the engine, expressed as data.

`DECIMAL(4,2)` specifies both precision and scale on purpose. Bare `DECIMAL` in MySQL defaults to zero decimal places, which would silently round `0.90` to `1` and destroy the weighting.

The composite primary key means a mood can't link to the same genre twice, while a single genre can still belong to several moods with different scores — which is exactly the intent. Action scores `0.47` for Happy/Excitement and `0.80` for Anger/Rage; Racing scores `0.93` for Happy and `1.00` for Anger.

The foreign keys are written as separate `FOREIGN KEY` clauses rather than inline `REFERENCES` on the column, because MySQL parses the inline form but silently ignores it — the constraint would never actually be created.

### The 51 live rows

| Mood | Mapped genres |
|---|---|
| Happy/Excitement | 12 |
| Calm/Serene | 10 |
| Sad/Melancholy | 9 |
| Anger/Rage | 12 |
| Confusion/Anxiety | 8 |

The original 46 rows live in `mood_genre_mapping_inserts.sql`, one INSERT per pair, each resolving `mood_id` and `genre_id` through subqueries rather than hardcoded integers — so the file stays correct regardless of what auto-increment IDs the seed happened to produce on a given run. The extra 5 rows (`Other` × each mood at `0.25`) live in `add_other_music_genre.sql` and use the same subquery pattern.

Note the lookup column differs per media type, which is why the subqueries aren't uniform: movie and TV rows match on `external_id` against TMDB's numeric ID, game rows match on `external_id` against RAWG's slug, and music rows match on `name` because there's no ID to lean on.

One row carries an explicit caveat in the file: War (movie) under Anger/Rage is set to `0.60`, back-solved from the ratings sheet's own average because one rater's cell showed `#REF!`. It's flagged in-file as needing confirmation.

## Table 4 — `items`

```sql
id                INT AUTO_INCREMENT PRIMARY KEY
media_type        VARCHAR(50)  NOT NULL
external_id       VARCHAR(100) NOT NULL
title             VARCHAR(255) NOT NULL
popularity_score  DECIMAL(10,2)
metadata          JSON
harvested_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP
UNIQUE (media_type, external_id)
```

One table for every harvested thing — a film, a show, a game, a track, and later whatever else. `media_type` values written by the harvesters are `'movie'`, `'tv'`, `'game'`, `'music'`.

`popularity_score` is `DECIMAL(10,2)`, wide enough for both small rating values and large raw counts, because each source means something different by "popularity" (see [04-HARVESTERS.md](04-HARVESTERS.md)).

`metadata` is `JSON` and holds the entire raw API response for the item. This is the escape valve that keeps the table generic: an artist name for a track or a cuisine for a future food item goes in the blob rather than becoming a new column. (`JSON`, not `JSONB` — that's Postgres-only.)

`UNIQUE (media_type, external_id)` is what makes the harvesters idempotent. Re-running a harvest tomorrow updates the existing row instead of inserting a duplicate.

Currently 70 rows: 20 `'movie'`, 20 `'tv'`, 20 `'game'`, 10 `'music'`.

## Table 5 — `item_genres`

```sql
item_id   INT NOT NULL
genre_id  INT NOT NULL
PRIMARY KEY (item_id, genre_id)
FOREIGN KEY (item_id)  REFERENCES items(id)
FOREIGN KEY (genre_id) REFERENCES genres(id)
```

A junction table, because one film is genuinely both Action and Comedy at once. This is also the direct cause of the duplicate rows the backend has to dedupe: an item tagged with three genres that all score against the requested mood comes back from the join three times.

Populated from the 70 harvested items (119 links).

## Table 6 — `feedback`

```sql
id          INT AUTO_INCREMENT PRIMARY KEY
mood_id     INT
item_id     INT
feedback    BOOLEAN
created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
FOREIGN KEY (mood_id) REFERENCES moods(id)
FOREIGN KEY (item_id) REFERENCES items(id)
```

Thumbs up / thumbs down on a specific recommendation. The table exists and is empty — nothing in the backend writes to it and nothing reads it. It's forward-looking capacity, not a live feature.

MySQL has no true BOOLEAN type; this is stored as `TINYINT(1)` where 1 is thumbs up and 0 is thumbs down. You can still write `TRUE`/`FALSE` on insert and MySQL converts.

## `dynamic_data_gathering_schema.sql` — dead file

This file is **abandoned**. It is not a roadmap, not a planned feature, and not part of the current design.

It defines five tables — `emojis`, `emoji_mood_weights`, `questions`, `user_sessions`, `session_responses` — for a discarded approach in which the app would have shown the user a series of deliberately generic questions answered with emoji taps, and inferred mood indirectly from the emoji weights instead of asking for it outright. It was never executed against the database, no code in the repo references it, and the five tables do not exist in the live schema.

It's left in the repo as a historical artifact. Treat it as such. Anyone auditing the schema should read `schema.sql` alone as the source of truth.

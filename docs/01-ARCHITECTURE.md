# 01 — Architecture

## Shape of the system

There are two entirely separate paths through this system, and keeping them separate is the central architectural decision. Nothing on the read path talks to a third-party API.

```
WRITE PATH (offline, scheduled, one device per source)
─────────────────────────────────────────────────────
  TMDB   ──▶ harvest_movies_tv.py  ─┐
  RAWG   ──▶ harvest_games.py      ─┼──▶  Aiven MySQL  ──▶  items
  Deezer ──▶ harvest_music.py      ─┘   (state_of_mind)     item_genres

READ PATH (online, per user request)
───────────────────────────────────
  Flutter app ──▶ GET /get-state?mood=Happy/Excitement
                        │
                        ▼
                   Flask (app.py)
                        │
                        ▼
              one SQL join across
      moods → mood_genre_mapping → item_genres → items
                        │
                        ▼
              ranked recommendations
```

## The four components

### 1. The Brain — `mood_genre_mapping`

Not code. A table. It holds one row per (mood, genre) pair with a `relevance_score` between 0 and 1, and it is the only place in the system that encodes any opinion about which content suits which mood.

Because it's data rather than logic, re-tuning the engine's taste means running INSERTs, not editing and redeploying Python. See [06-BRAIN-AND-RATINGS.md](06-BRAIN-AND-RATINGS.md) for how those scores are produced.

Status: done and live, 51 rows.

### 2. The Harvester — three independent scripts

`harvest_movies_tv.py`, `harvest_games.py`, `harvest_music.py`. Each one talks to exactly one external API, writes into the shared `items` and `item_genres` tables, and knows nothing about the other two.

Each script runs once per invocation with no internal loop. Scheduling lives outside the code, at the OS level — cron on the MacBook, Task Scheduler on Windows — with a midnight trigger. This means there is no orchestrator process to keep alive, and no shared state between harvests.

The split is deliberate: one API per device keeps memory and connection load light on any single student laptop, and an outage or a bad key on one device doesn't take the other two harvests down with it.

Status: partial. Details in [04-HARVESTERS.md](04-HARVESTERS.md).

### 3. The Backend / Engine — `app.py`

A Flask app with two routes: `/` (a liveness string) and `/get-state`. `/get-state` reads a `mood` query parameter, opens a MySQL connection inside the request, runs the four-table join, and returns the result.

The engine holds no recommendation logic of its own beyond the join and the sort order. All the judgement is in the Brain table; the backend just reads it.

Status: stage 4 of 7. Details in [05-BACKEND.md](05-BACKEND.md).

### 4. Frontend — planned Flutter app

Five fixed mood buttons, no free-text input. This constraint is load-bearing: because the UI can only ever emit one of five exact strings, the API takes the mood as a name rather than a numeric ID, and any unmatched mood is a genuine error rather than a search miss. See [08-DECISIONS.md](08-DECISIONS.md).

Status: not started, zero code.

## The join that is the engine

This is the heart of the read path. It appears in both `test_query.py` and `app.py`:

```29:36:app.py
        SELECT items.title, items.media_type, items.popularity_score, mood_genre_mapping.relevance_score
        FROM moods
        JOIN mood_genre_mapping ON moods.id = mood_genre_mapping.mood_id
        JOIN item_genres ON mood_genre_mapping.genre_id = item_genres.genre_id
        JOIN items ON item_genres.item_id = items.id
        WHERE moods.name = %s
        ORDER BY mood_genre_mapping.relevance_score DESC, items.popularity_score DESC
    """, (mood,))
```

Read it left to right: start from the requested mood, walk out to every genre that mood scores against, walk out again to every item tagged with those genres, and sort the result relevance-first with popularity only as a tiebreaker.

The join is a chain of many-to-many hops, which is why the raw result contains duplicates — a single film tagged both Action and Thriller comes back once per matching genre. Collapsing that is stage 5's job.

## Storage

A single cloud-hosted Aiven MySQL database named `state_of_mind`, SSL required. All three devices and the backend point at the same instance; there is no local database and no replication. The CA certificate lives in the repo at `ignore/ca.pem` and is referenced through the `DB_SSL_CA` environment variable.

## Deliberately not part of the architecture

`dynamic_data_gathering_schema.sql` is a **dead, abandoned file**. It sketches five extra tables (`emojis`, `emoji_mood_weights`, `questions`, `user_sessions`, `session_responses`) for an adaptive emoji-question flow that would have inferred mood indirectly instead of asking for it. It was never run, nothing references it, and it is not a roadmap item. It is documented here only so nobody mistakes it for planned work — see [02-DATABASE.md](02-DATABASE.md).

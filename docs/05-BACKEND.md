# 05 — Backend

A Flask app in `app.py`, being built deliberately as a seven-stage learning exercise rather than copied from a generic tutorial. Each stage adds one capability and is confirmed working before the next begins.

## Stage progress

| Stage | What it covers | Status |
|---|---|---|
| 1 | Basic Flask app, run/debug mode | Done |
| 2 | Reading query params — `/get-state?mood=X` via `request.args` | Done |
| 3 | Live connection to the cloud DB from inside a request | Done |
| 4 | The full mood → genre → items join, wired into the live route | Done |
| 5 | Shaping the response: dedupe, bucket into movies_tv / music / games, cap at top 5 each | Done |
| 6 | Error handling — 404 on invalid or missing mood | Not started |
| 7 | Testing the API standalone, without the frontend | Not started |

## What exists today

Two routes.

`GET /` returns `{"message": "State of Mind backend is running"}`.

`GET /get-state?mood=<name>` reads the mood, opens a MySQL connection inside a `try`/`finally` (the cursor and connection always close), runs the join, then shapes the rows and returns a dict. Flask serialises that dict as JSON.

The SELECT pulls `items.id` first, then title, media type, popularity, and relevance. The mood is a **string** (`?mood=Happy/Excitement`), matched against `moods.name`, not a numeric ID. That's a deliberate decision tied to the fixed five-button frontend — see [08-DECISIONS.md](08-DECISIONS.md).

The sort is `relevance_score DESC, popularity_score DESC`. Relevance-first, with popularity only as a tiebreaker; the two are never averaged. Also in [08-DECISIONS.md](08-DECISIONS.md).

The query is parameterised with `%s` and a tuple, so the mood string is never concatenated into SQL.

The join still produces one row per matching genre. Shaping happens in Python after `fetchall()`:

1. `remove_duplicates(rows)` keys on `items.id` and keeps the occurrence with the higher `relevance_score`. Decimal values from MySQL are converted to `float` so they compare cleanly and serialise to JSON.
2. `group_items_by_media()` puts `'movie'` and `'tv'` into `movies_tv`, `'music'` into `music`, and `'game'` into `games`. Any other `media_type` is skipped. All three keys exist even when a bucket is empty.
3. `cap_each_bucket()` slices each list to `MAX_ITEMS_PER_BUCKET` (5). Nothing re-sorts after the SQL `ORDER BY`, so the first five in a bucket are the best five.

```json
{
  "mood": "Happy/Excitement",
  "movies_tv": [
    {
      "id": 1,
      "title": "Example",
      "media_type": "movie",
      "popularity_score": 120.5,
      "relevance_score": 0.93
    }
  ],
  "music": [],
  "games": []
}
```

`music` and `games` are empty until those harvesters have run. With the current 40 movie/TV items, only `movies_tv` has rows.

`test_query.py` is the earlier prototype of the dedupe. It still keys on **title** and prints a dict; it is not what `/get-state` runs. The live function keys on item id, which avoids collapsing a film and a track that happen to share a title.

## Stage 6 — error handling, not started

The intended behaviour is a **404** for an invalid, unrecognised, or missing mood, on which the frontend sends the user back to the mood-picker screen. See [08-DECISIONS.md](08-DECISIONS.md) for the reasoning.

Nothing is implemented yet. Today, `request.args.get("mood")` returns `None` when the parameter is absent, the join matches nothing, and the route returns HTTP 200 with three empty buckets and `"mood": null`. A misspelt mood does the same, with the bad string echoed back in `"mood"`.

## Stage 7 — standalone testing, not started

The API is to be exercised on its own, without waiting on the Flutter app — which matters, given the frontend has zero code and the mood-picker UI doesn't exist to click.

## Running it

```
python app.py
```

Starts with `debug=True`, so Flask's development server with auto-reload and the interactive debugger. Development-only; not a production configuration.

Requires a populated `.env` — see [07-SETUP.md](07-SETUP.md).

## Known rough edges, for later

Recorded so they're not rediscovered as surprises. None of these block stage 6.

- **A fresh MySQL connection is opened and closed on every request**, with no pooling. Fine against 40 items; the first thing to revisit if latency ever matters.
- **The connection is created before the `try`.** `cursor.close()` and `connection.close()` run in `finally`, so a failed query does not leak them. A failure inside `connect()` itself still has nothing to close.
- **`items.metadata` and `harvested_at` are not selected.** Each returned item has `id`, `title`, `media_type`, `popularity_score`, and `relevance_score`. A real UI will want poster paths and artist names out of the metadata blob.
- **`popularity_score` isn't comparable across media types** — a TMDB float, a RAWG "added" count, and a Deezer rank all live in the same column. Within a single bucket the tiebreak is sound; across buckets it isn't meaningful. Bucketing keeps those comparisons inside one source.

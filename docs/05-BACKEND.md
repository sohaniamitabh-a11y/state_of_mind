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

`GET /` returns a JSON liveness object `{"message": "State of Mind backend is running"}`.

`GET /get-state?mood=<name>` reads the mood parameter, opens a MySQL connection, runs the join, processes the results, closes the connection, and returns JSON buckets:

```14:41:app.py
@app.route("/get-state")
def get_state():
    mood = request.args.get("mood")
    conn = mysql.connector.connect(
        host=os.getenv("DB_HOST"),
        port=int(os.getenv("DB_PORT")),
        user=os.getenv("DB_USER"),
        password=os.getenv("DB_PASSWORD"),
        database=os.getenv("DB_NAME"),
        ssl_ca=os.getenv("DB_SSL_CA"),
        ssl_verify_cert=True
    )

    cursor = conn.cursor()
    cursor.execute("""
        SELECT items.title, items.media_type, items.popularity_score, mood_genre_mapping.relevance_score
        FROM moods
        JOIN mood_genre_mapping ON moods.id = mood_genre_mapping.mood_id
        JOIN item_genres ON mood_genre_mapping.genre_id = item_genres.genre_id
        JOIN items ON item_genres.item_id = items.id
        WHERE moods.name = %s
        ORDER BY mood_genre_mapping.relevance_score DESC, items.popularity_score DESC
    """, (mood,))
    rows = cursor.fetchall()
    cursor.close()
    conn.close()

    return f"you asked for mood: {mood}, matches: {rows}"
```

Two things to be clear about regarding the current response. It is **raw duplicated rows** — an item tagged with three genres that all score against the requested mood appears three times, because `item_genres` is a many-to-many join. And it is a Python tuple list interpolated into an f-string, not JSON. Both are stage 5's problem, not oversights.

The mood is passed as a **string** (`?mood=Happy/Excitement`), matched against `moods.name`, not as a numeric ID. That's a deliberate decision tied to the fixed five-button frontend — see [08-DECISIONS.md](08-DECISIONS.md).

The sort order is `relevance_score DESC, popularity_score DESC`. Relevance-first, with popularity purely as a tiebreaker; the two are never averaged or blended. Also a deliberate decision, also in [08-DECISIONS.md](08-DECISIONS.md).

The query is parameterised with `%s` and a tuple, so the mood string is never string-concatenated into SQL.

## Stage 5 in detail — shaping the response

Stage 5 ensures the frontend gets clean, display-ready data:

1. **Deduplication:** A many-to-many `item_genres` join returns an item multiple times if several of its genres match the mood. The backend preserves only the occurrence with the highest `relevance_score` using `remove_duplicates()`.
2. **Bucketing:** Recommendations are split into `"movies_tv"`, `"music"`, and `"games"` categories via `group_items_by_media()`.
3. **Capping:** Each bucket is sliced to `[:5]` by `cap_each_bucket()`. The SQL `ORDER BY` is preserved throughout, so the five kept are the best available.

Because these tasks run as isolated functions inside `app.py`, the main `/get-state` route stays focused on handling the request and talking to MySQL.

```json
{
  "mood": "Happy/Excitement",
  "movies_tv": [...],
  "music": [...],
  "games": [...]
}
```

## Stage 6 — error handling, not started

The intended behaviour is a **404** for an invalid, unrecognised, or missing mood, on which the frontend sends the user back to the mood-picker screen. See [08-DECISIONS.md](08-DECISIONS.md) for the reasoning.

Nothing is implemented yet. Today, `request.args.get("mood")` returns `None` when the parameter is absent, the join matches nothing, and the route returns an empty list with a 200 status. Same for a misspelt mood.

## Stage 7 — standalone testing, not started

The API is to be exercised on its own, without waiting on the Flutter app — which matters, given the frontend has zero code and the mood-picker UI doesn't exist to click.

## Running it

```
python app.py
```

Starts with `debug=True`, so Flask's development server with auto-reload and the interactive debugger. Development-only; not a production configuration.

Requires a populated `.env` — see [07-SETUP.md](07-SETUP.md).

## Known rough edges, for later

Recorded so they're not rediscovered as surprises. None of these are stage 5 or 6 blockers.

- **A fresh MySQL connection is opened and closed on every request**, with no pooling. Fine for a college project against 40 items; the first thing to revisit if latency ever matters.
- **No try/finally around the connection.** If the query raises, `conn.close()` is skipped and the connection leaks. The harvesters do use `try/finally`; `app.py` doesn't.
- **The response isn't JSON.** An f-string containing a repr of Python tuples is not something a Flutter client can parse. Stage 5 will need `jsonify`.
- **`items.metadata`, `items.id`, and `harvested_at` aren't selected.** The four columns currently returned are enough to rank and display a title, but a real UI will want poster paths and artist names out of the metadata blob.
- **`popularity_score` isn't comparable across media types** — a TMDB float, a RAWG "added" count, and a Deezer rank all live in the same column. Within a single bucket the tiebreak is sound; across buckets it isn't meaningful. Bucketing conveniently sidesteps this.

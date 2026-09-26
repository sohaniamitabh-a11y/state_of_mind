# 06 — The Brain and the Ratings Pipeline

The Brain is the `mood_genre_mapping` table: one row per (mood, genre) pair carrying a `relevance_score`. It is the only place in the system that holds an opinion about which content suits which mood. Everything else — harvesters, join query, sort order — is plumbing around it.

Status: done and live. 51 rows in the database (46 from the first ratings round, plus 5 that map music `Other` to every mood at `0.25`). 74 more are queued on the genre-expansion survey.

## Why it's a table and not code

The whole engine's taste is expressed as data. Re-tuning what "Calm/Serene" means is a matter of running INSERTs, not editing Python and redeploying. And because the score is a weight between 0 and 1 rather than a boolean tag, the join can rank results by mood-fit instead of just filtering by it.

This is the same principle as the string `media_type` columns: growth happens through rows.

## Where the scores come from

Not from an algorithm and not from an existing dataset. From humans, through a Google Forms survey. **None of this pipeline lives in the repo** — the survey is external, and the resulting numbers were transcribed into SQL by hand.

The setup:

- **Five separate forms**, one per mood.
- **Within each form, every genre is its own question**, answered on a **0–5 linear scale** — how well does this genre suit this mood.
- **Target sample: roughly 50 respondents.**
- **Three existing raters' scores are already seeded** as baseline rows in each form's response sheet, so the sheet isn't starting from empty and the averages remain computable while responses trickle in.

Splitting the survey into five forms rather than one is what keeps it answerable. A single form covering every genre against every mood would be 63 × 5 questions.

## The scoring formula

```
relevance_score = (average of all respondents' 0–5 ratings) ÷ 5
```

Dividing by 5 normalises the raw scale into the 0.00–1.00 range that `mood_genre_mapping.relevance_score` expects, which is why `DECIMAL(4,2)` with an explicit scale matters — bare `DECIMAL` in MySQL would round every one of these to an integer and flatten the weighting entirely.

The 46 live scores are all multiples of ¹⁄₁₅ (`0.13`, `0.20`, `0.27`, `0.33`, `0.40`, `0.47`, `0.53`, `0.60`, `0.67`, `0.73`, `0.80`, `0.87`, `0.93`, `1.00`), which is exactly what you'd expect from three raters — the sum of three 0–5 ratings over 15. As the survey fills toward ~50 respondents, the scores will land on a much finer grain and the current values will be superseded.

So treat every score in the database right now as a **three-person baseline, not a finished measurement.**

## How scores become rows

Averages were read off the ratings spreadsheet (referenced in the SQL file's own header as `state_of_mind_ratings.xlsx`, which is not in this repo) and written out as literal decimals in `mood_genre_mapping_inserts.sql` — one INSERT per pair.

Each INSERT resolves its foreign keys through subqueries rather than hardcoded integers:

```26:32:mood_genre_mapping_inserts.sql
INSERT INTO mood_genre_mapping (mood_id, genre_id, relevance_score) 
VALUES
(
    (SELECT id FROM moods WHERE name = 'Happy/Excitement'),
    (SELECT id FROM genres WHERE media_type = 'movie' AND external_id = '35'),
    0.60
);
```

This is why the file stays correct no matter what auto-increment IDs a given seed run produced. It also means the file is readable as a record of the ratings themselves, since each INSERT is preceded by a comment naming the genre.

There is **no script that reads form responses and generates this SQL.** The transcription is manual, and it's the step that will need repeating when the survey completes.

### The lookup column differs per media type

The subqueries aren't uniform, and the reason is in the source data:

| Media type | Matched on | Why |
|---|---|---|
| movie, tv | `genres.external_id` = TMDB numeric genre ID | Verified against TMDB's own list |
| game | `genres.external_id` = RAWG slug | Verified against RAWG's own list |
| music | `genres.name` | No numeric ID to lean on — these buckets were invented, not fetched |

The music rows carry an explicit warning in the file: confirm exact spelling with `SELECT id, name, external_id FROM genres WHERE media_type = 'music'` before running them, because a name mismatch would make the subquery return NULL and the INSERT fail rather than silently misfile the row.

## The 46 rated rows

| Mood | Genres mapped | Highest-scoring |
|---|---|---|
| Happy/Excitement | 11 | Dance/EDM, Rap/Hip-Hop, Racing (game) — all 0.93 |
| Calm/Serene | 9 | Fantasy (movie), Role-Playing Games — both 0.93 |
| Sad/Melancholy | 8 | Drama (movie) 0.93 |
| Anger/Rage | 11 | Action & Adventure (TV), Racing (game) — both 1.00 |
| Confusion/Anxiety | 7 | Mystery (movie), Mystery (TV) — both 0.93 |

Total: 46.

A genre can and does appear under several moods with different weights, which is the point of the composite primary key. Action scores 0.47 for Happy/Excitement but 0.80 for Anger/Rage. Racing scores 0.93 for Happy and a full 1.00 for Anger. Drama scores 0.93 for Sad/Melancholy but 0.47 for Confusion/Anxiety.

### Two caveats recorded in the file itself

**War (movie) under Anger/Rage, scored 0.60.** One rater's cell in the spreadsheet showed `#REF!`. The 0.60 was back-solved from the sheet's own average and score cells, which implies that rater had originally given it a 3. It's flagged in-file as needing confirmation with them, and it's the one score in the table that wasn't read directly off a live value.

**Two genres are acknowledged proxies rather than real matches.** Adventure (game) under Sad/Melancholy at 0.47, and Puzzle (game) under Confusion/Anxiety at 0.47, are both commented as "closest proxy, no clean genre match." RAWG's taxonomy has no genre that genuinely corresponds to those moods, and the choice was to record the nearest thing and label it rather than leave the mood with no game coverage at all.

## The `Other` music rows

These five are not survey scores. `add_other_music_genre.sql` inserts the music genre `Other` and maps it to all five moods at relevance `0.25`, so a Deezer track that matches no curated bucket can still come back from the join, ranked below the rated genres. `harvest_music.py` only links `Other` when none of that track's album genre names matched. See [04-HARVESTERS.md](04-HARVESTERS.md).

That brings the live Brain to 51 rows and music genres to 11 (64 genres in total).

## The 74 queued rows

The 46 rated rows only cover the genres that existed at the time of the first ratings round — the 38 seeded by `seed_mood_genre.sql`. `expand_genres.sql` later added 25 genres (Horror, Romance, Crime, Animation, Platformer, Indie, and the rest). None of those have been rated against any mood yet. `Other` is a separate fallback, not one of those 25.

**74 further `mood_genre_mapping` rows are queued, waiting on the genre-expansion ratings to come back from the survey.** Until they land, the newly added genres exist in the catalog but are invisible to the recommendation engine: with no `mood_genre_mapping` row, the join simply never reaches items tagged with them.

Applying them will be safe and non-destructive. `run_mapping.py` swallows duplicate-key errors, and the composite `PRIMARY KEY (mood_id, genre_id)` means the existing 46 rows can't be doubled. See [03-DATA-PIPELINE.md](03-DATA-PIPELINE.md).

## What the Brain does not do

- It doesn't learn. There is no feedback loop; `feedback` is empty and nothing writes to it.
- It doesn't blend relevance with popularity. The two stay separate, with popularity used only as a tiebreaker — a deliberate choice covered in [08-DECISIONS.md](08-DECISIONS.md).
- It doesn't score item-to-mood, only genre-to-mood. An individual film's mood fit is entirely inherited from its genre tags.

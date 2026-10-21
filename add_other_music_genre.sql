-- add_other_music_genre.sql
-- Adds the fallback music genre "Other" plus Brain rows mapping it
-- to all five moods at low relevance (0.25).
-- Run via run_add_other_music_genre.py — same pattern as the other
-- runners; duplicate-entry errors are skipped, so this is safe to re-run.
--
-- WHY: Deezer's genre vocabulary doesn't line up 1:1 with the ten
-- curated music buckets. harvest_music.py aliases the near-misses and
-- falls back to "Other" when a track matches none of them, so tracks
-- stay recommendable (just deprioritized) instead of vanishing from
-- the mood → genre → item join.

-- Fallback music genre (matched by name, no external_id — same pattern
-- as the other music buckets in seed_mood_genre.sql).
-- WHERE NOT EXISTS keeps this idempotent: UNIQUE (media_type, external_id)
-- does not catch duplicate music rows because external_id is NULL, and
-- MySQL allows multiple NULLs in a unique index.
INSERT INTO genres (media_type, external_id, name)
SELECT 'music', NULL, 'Other'
WHERE NOT EXISTS (
    SELECT 1 FROM genres WHERE media_type = 'music' AND name = 'Other'
);

-- ==================== OTHER × ALL FIVE MOODS ====================
-- Low relevance on every mood so unmatched tracks still surface
-- through the recommendation join, ranked below curated genres.

-- Other → Happy/Excitement
INSERT INTO mood_genre_mapping (mood_id, genre_id, relevance_score)
VALUES
(
    (SELECT id FROM moods WHERE name = 'Happy/Excitement'),
    (SELECT id FROM genres WHERE media_type = 'music' AND name = 'Other'),
    0.25
);

-- Other → Calm/Serene
INSERT INTO mood_genre_mapping (mood_id, genre_id, relevance_score)
VALUES
(
    (SELECT id FROM moods WHERE name = 'Calm/Serene'),
    (SELECT id FROM genres WHERE media_type = 'music' AND name = 'Other'),
    0.25
);

-- Other → Sad/Melancholy
INSERT INTO mood_genre_mapping (mood_id, genre_id, relevance_score)
VALUES
(
    (SELECT id FROM moods WHERE name = 'Sad/Melancholy'),
    (SELECT id FROM genres WHERE media_type = 'music' AND name = 'Other'),
    0.25
);

-- Other → Anger/Rage
INSERT INTO mood_genre_mapping (mood_id, genre_id, relevance_score)
VALUES
(
    (SELECT id FROM moods WHERE name = 'Anger/Rage'),
    (SELECT id FROM genres WHERE media_type = 'music' AND name = 'Other'),
    0.25
);

-- Other → Confusion/Anxiety
INSERT INTO mood_genre_mapping (mood_id, genre_id, relevance_score)
VALUES
(
    (SELECT id FROM moods WHERE name = 'Confusion/Anxiety'),
    (SELECT id FROM genres WHERE media_type = 'music' AND name = 'Other'),
    0.25
);

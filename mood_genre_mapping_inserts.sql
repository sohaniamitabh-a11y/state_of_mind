-- ================================================================
-- mood_genre_mapping — 46 rows, built from state_of_mind_ratings.xlsx
-- Run these one at a time (or as one batch, since none of these
-- depend on each other) in your DB Notebook.
--
-- HOW GENRE LOOKUP WORKS PER MEDIA TYPE (so you know why each
-- subquery is shaped the way it is):
--   movie/TV genres -> matched on genres.external_id = TMDB's own
--                      numeric genre id (verified, already loaded)
--   game genres      -> matched on genres.external_id = RAWG's slug
--                      (verified, already loaded)
--   music genres      -> matched on genres.name (TMDB/RAWG had no
--                      numeric id to lean on here — RUN THE
--                      VERIFICATION SELECT BELOW FIRST)
--
-- BEFORE RUNNING THE MUSIC ROWS, confirm exact spelling:
--   SELECT id, name, external_id FROM genres WHERE media_type = 'music' ORDER BY id;
-- If any name below doesn't match what that query returns, edit the
-- string in the matching INSERT before running it.
-- ================================================================


-- ==================== HAPPY / EXCITEMENT (11) ====================

-- Comedy (movie)
INSERT INTO mood_genre_mapping (mood_id, genre_id, relevance_score) 
VALUES
(
    (SELECT id FROM moods WHERE name = 'Happy/Excitement'),
    (SELECT id FROM genres WHERE media_type = 'movie' AND external_id = '35'),
    0.60
);

-- Adventure (movie)
INSERT INTO mood_genre_mapping (mood_id, genre_id, relevance_score)
VALUES
(
    (SELECT id FROM moods WHERE name = 'Happy/Excitement'),
    (SELECT id FROM genres WHERE media_type = 'movie' AND external_id = '12'),
    0.87
);

-- Action (movie)
INSERT INTO mood_genre_mapping (mood_id, genre_id, relevance_score)
VALUES 
(
    (SELECT id FROM moods WHERE name = 'Happy/Excitement'),
    (SELECT id FROM genres WHERE media_type = 'movie' AND external_id = '28'),
    0.47
);

-- Comedy (TV)
INSERT INTO mood_genre_mapping (mood_id, genre_id, relevance_score) 
VALUES 
(
    (SELECT id FROM moods WHERE name = 'Happy/Excitement'),
    (SELECT id FROM genres WHERE media_type = 'tv' AND external_id = '35'),
    0.33
);

-- Action & Adventure (TV)
INSERT INTO mood_genre_mapping (mood_id, genre_id, relevance_score) 
VALUES 
(
    (SELECT id FROM moods WHERE name = 'Happy/Excitement'),
    (SELECT id FROM genres WHERE media_type = 'tv' AND external_id = '10759'),
    0.67
);

-- Pop
INSERT INTO mood_genre_mapping (mood_id, genre_id, relevance_score) VALUES (
    (SELECT id FROM moods WHERE name = 'Happy/Excitement'),
    (SELECT id FROM genres WHERE media_type = 'music' AND name = 'Pop'),
    0.60
);

-- Dance/EDM
INSERT INTO mood_genre_mapping (mood_id, genre_id, relevance_score) 
VALUES 
(
    (SELECT id FROM moods WHERE name = 'Happy/Excitement'),
    (SELECT id FROM genres WHERE media_type = 'music' AND name = 'Dance/EDM'),
    0.93
);

-- Rap/Hip-Hop
INSERT INTO mood_genre_mapping (mood_id, genre_id, relevance_score) 
VALUES 
(
    (SELECT id FROM moods WHERE name = 'Happy/Excitement'),
    (SELECT id FROM genres WHERE media_type = 'music' AND name = 'Rap/Hip-Hop'),
    0.93
);

-- Racing (game)
INSERT INTO mood_genre_mapping (mood_id, genre_id, relevance_score) 
VALUES 
(
    (SELECT id FROM moods WHERE name = 'Happy/Excitement'),
    (SELECT id FROM genres WHERE media_type = 'game' AND external_id = 'racing'),
    0.93
);

-- Sports (game)
INSERT INTO mood_genre_mapping (mood_id, genre_id, relevance_score) 
VALUES 
(
    (SELECT id FROM moods WHERE name = 'Happy/Excitement'),
    (SELECT id FROM genres WHERE media_type = 'game' AND external_id = 'sports'),
    0.27
);

-- Arcade (game)
INSERT INTO mood_genre_mapping (mood_id, genre_id, relevance_score) 
VALUES 
(
    (SELECT id FROM moods WHERE name = 'Happy/Excitement'),
    (SELECT id FROM genres WHERE media_type = 'game' AND external_id = 'arcade'),
    0.67
);


-- ==================== CALM / SERENE (9) ====================

-- Documentary (movie)
INSERT INTO mood_genre_mapping (mood_id, genre_id, relevance_score) 
VALUES 
(
    (SELECT id FROM moods WHERE name = 'Calm/Serene'),
    (SELECT id FROM genres WHERE media_type = 'movie' AND external_id = '99'),
    0.67
);

-- Fantasy (movie)
INSERT INTO mood_genre_mapping (mood_id, genre_id, relevance_score) 
VALUES 
(
    (SELECT id FROM moods WHERE name = 'Calm/Serene'),
    (SELECT id FROM genres WHERE media_type = 'movie' AND external_id = '14'),
    0.93
);

-- Science Fiction (movie)
INSERT INTO mood_genre_mapping (mood_id, genre_id, relevance_score) 
VALUES 
(
    (SELECT id FROM moods WHERE name = 'Calm/Serene'),
    (SELECT id FROM genres WHERE media_type = 'movie' AND external_id = '878'),
    0.87
);

-- Documentary (TV)
INSERT INTO mood_genre_mapping (mood_id, genre_id, relevance_score) 
VALUES 
(
    (SELECT id FROM moods WHERE name = 'Calm/Serene'),
    (SELECT id FROM genres WHERE media_type = 'tv' AND external_id = '99'),
    0.53
);

-- Sci-Fi & Fantasy (TV)
INSERT INTO mood_genre_mapping (mood_id, genre_id, relevance_score)
VALUES 
(
    (SELECT id FROM moods WHERE name = 'Calm/Serene'),
    (SELECT id FROM genres WHERE media_type = 'tv' AND external_id = '10765'),
    0.67
);

-- Jazz/Acoustic
INSERT INTO mood_genre_mapping (mood_id, genre_id, relevance_score) 
VALUES 
(
    (SELECT id FROM moods WHERE name = 'Calm/Serene'),
    (SELECT id FROM genres WHERE media_type = 'music' AND name = 'Jazz/Acoustic'),
    0.40
);

-- Simulation (game)
INSERT INTO mood_genre_mapping (mood_id, genre_id, relevance_score)  
VALUES 
(
    (SELECT id FROM moods WHERE name = 'Calm/Serene'),
    (SELECT id FROM genres WHERE media_type = 'game' AND external_id = 'simulation'),
    0.67
);

-- Strategy (game)
INSERT INTO mood_genre_mapping (mood_id, genre_id, relevance_score) 
VALUES 
(
    (SELECT id FROM moods WHERE name = 'Calm/Serene'),
    (SELECT id FROM genres WHERE media_type = 'game' AND external_id = 'strategy'),
    0.80
);

-- Role-Playing Games (game)
INSERT INTO mood_genre_mapping (mood_id, genre_id, relevance_score) 
VALUES 
(
    (SELECT id FROM moods WHERE name = 'Calm/Serene'),
    (SELECT id FROM genres WHERE media_type = 'game' AND external_id = 'role-playing-games-rpg'),
    0.93
);


-- ==================== SAD / MELANCHOLY (8) ====================

-- Drama (movie)
INSERT INTO mood_genre_mapping (mood_id, genre_id, relevance_score) 
VALUES 
(
    (SELECT id FROM moods WHERE name = 'Sad/Melancholy'),
    (SELECT id FROM genres WHERE media_type = 'movie' AND external_id = '18'),
    0.93
);

-- War (movie)
INSERT INTO mood_genre_mapping (mood_id, genre_id, relevance_score) 
VALUES 
(
    (SELECT id FROM moods WHERE name = 'Sad/Melancholy'),
    (SELECT id FROM genres WHERE media_type = 'movie' AND external_id = '10752'),
    0.27
);

-- History (movie)
INSERT INTO mood_genre_mapping (mood_id, genre_id, relevance_score) 
VALUES 
(
    (SELECT id FROM moods WHERE name = 'Sad/Melancholy'),
    (SELECT id FROM genres WHERE media_type = 'movie' AND external_id = '36'),
    0.53
);

-- Drama (TV)
INSERT INTO mood_genre_mapping (mood_id, genre_id, relevance_score) 
VALUES 
(
    (SELECT id FROM moods WHERE name = 'Sad/Melancholy'),
    (SELECT id FROM genres WHERE media_type = 'tv' AND external_id = '18'),
    0.80
);

-- War & Politics (TV)
INSERT INTO mood_genre_mapping (mood_id, genre_id, relevance_score)   
VALUES 
(
    (SELECT id FROM moods WHERE name = 'Sad/Melancholy'),
    (SELECT id FROM genres WHERE media_type = 'tv' AND external_id = '10768'),
    0.20
);

-- Blues
INSERT INTO mood_genre_mapping (mood_id, genre_id, relevance_score) 
VALUES 
(
    (SELECT id FROM moods WHERE name = 'Sad/Melancholy'),
    (SELECT id FROM genres WHERE media_type = 'music' AND name = 'Blues'),
    0.87
);

-- Classical
INSERT INTO mood_genre_mapping (mood_id, genre_id, relevance_score) 
VALUES 
(
    (SELECT id FROM moods WHERE name = 'Sad/Melancholy'),
    (SELECT id FROM genres WHERE media_type = 'music' AND name = 'Classical'),
    0.47
);

-- Adventure (game) — closest proxy, no clean genre match (per your notes)
INSERT INTO mood_genre_mapping (mood_id, genre_id, relevance_score) 
VALUES 
(
    (SELECT id FROM moods WHERE name = 'Sad/Melancholy'),
    (SELECT id FROM genres WHERE media_type = 'game' AND external_id = 'adventure'),
    0.47
);


-- ==================== ANGER / RAGE (11) ====================

-- Action (movie)
INSERT INTO mood_genre_mapping (mood_id, genre_id, relevance_score) 
VALUES 
(
    (SELECT id FROM moods WHERE name = 'Anger/Rage'),
    (SELECT id FROM genres WHERE media_type = 'movie' AND external_id = '28'),
    0.80
);

-- War (movie) — NOTE: Friend A's cell showed #REF! in the sheet;
-- 0.60 is back-solved from the sheet's own Average/Score cells
-- (implies Friend A originally rated this a 3). Confirm with them.
INSERT INTO mood_genre_mapping (mood_id, genre_id, relevance_score) 
VALUES 
(
    (SELECT id FROM moods WHERE name = 'Anger/Rage'),
    (SELECT id FROM genres WHERE media_type = 'movie' AND external_id = '10752'),
    0.60
);

-- Thriller (movie)
INSERT INTO mood_genre_mapping (mood_id, genre_id, relevance_score) 
VALUES 
(
    (SELECT id FROM moods WHERE name = 'Anger/Rage'),
    (SELECT id FROM genres WHERE media_type = 'movie' AND external_id = '53'),
    0.73
);

-- Action & Adventure (TV)
INSERT INTO mood_genre_mapping (mood_id, genre_id, relevance_score) 
VALUES 
(
    (SELECT id FROM moods WHERE name = 'Anger/Rage'),
    (SELECT id FROM genres WHERE media_type = 'tv' AND external_id = '10759'),
    1.00
);

-- War & Politics (TV)
INSERT INTO mood_genre_mapping (mood_id, genre_id, relevance_score) 
VALUES 
(
    (SELECT id FROM moods WHERE name = 'Anger/Rage'),
    (SELECT id FROM genres WHERE media_type = 'tv' AND external_id = '10768'),
    0.13
);

-- Metal
INSERT INTO mood_genre_mapping (mood_id, genre_id, relevance_score) 
VALUES 
(
    (SELECT id FROM moods WHERE name = 'Anger/Rage'),
    (SELECT id FROM genres WHERE media_type = 'music' AND name = 'Metal'),
    0.60
);

-- Punk
INSERT INTO mood_genre_mapping (mood_id, genre_id, relevance_score) 
VALUES 
(
    (SELECT id FROM moods WHERE name = 'Anger/Rage'),
    (SELECT id FROM genres WHERE media_type = 'music' AND name = 'Punk'),
    0.53
);

-- Techno
INSERT INTO mood_genre_mapping (mood_id, genre_id, relevance_score) 
VALUES 
(
    (SELECT id FROM moods WHERE name = 'Anger/Rage'),
    (SELECT id FROM genres WHERE media_type = 'music' AND name = 'Techno'),
    0.60
);

-- Shooter (game)
INSERT INTO mood_genre_mapping (mood_id, genre_id, relevance_score) 
VALUES 
(
    (SELECT id FROM moods WHERE name = 'Anger/Rage'),
    (SELECT id FROM genres WHERE media_type = 'game' AND external_id = 'shooter'),
    0.87
);

-- Fighting (game)
INSERT INTO mood_genre_mapping (mood_id, genre_id, relevance_score) 
VALUES 
(
    (SELECT id FROM moods WHERE name = 'Anger/Rage'),
    (SELECT id FROM genres WHERE media_type = 'game' AND external_id = 'fighting'),
    0.93
);

-- Racing (game)
INSERT INTO mood_genre_mapping (mood_id, genre_id, relevance_score) 
VALUES 
(
    (SELECT id FROM moods WHERE name = 'Anger/Rage'),
    (SELECT id FROM genres WHERE media_type = 'game' AND external_id = 'racing'),
    1.00
);


-- ==================== CONFUSION / ANXIETY (7) ====================

-- Mystery (movie)
INSERT INTO mood_genre_mapping (mood_id, genre_id, relevance_score) 
VALUES 
(
    (SELECT id FROM moods WHERE name = 'Confusion/Anxiety'),
    (SELECT id FROM genres WHERE media_type = 'movie' AND external_id = '9648'),
    0.93
);

-- Thriller (movie)
INSERT INTO mood_genre_mapping (mood_id, genre_id, relevance_score) 
VALUES 
(
    (SELECT id FROM moods WHERE name = 'Confusion/Anxiety'),
    (SELECT id FROM genres WHERE media_type = 'movie' AND external_id = '53'),
    0.80
);

-- Drama (movie)
INSERT INTO mood_genre_mapping (mood_id, genre_id, relevance_score) 
VALUES 
(
    (SELECT id FROM moods WHERE name = 'Confusion/Anxiety'),
    (SELECT id FROM genres WHERE media_type = 'movie' AND external_id = '18'),
    0.47
);

-- Mystery (TV)
INSERT INTO mood_genre_mapping (mood_id, genre_id, relevance_score) 
VALUES 
(
    (SELECT id FROM moods WHERE name = 'Confusion/Anxiety'),
    (SELECT id FROM genres WHERE media_type = 'tv' AND external_id = '9648'),
    0.93
);

-- Drama (TV)
INSERT INTO mood_genre_mapping (mood_id, genre_id, relevance_score) 
VALUES 
(
    (SELECT id FROM moods WHERE name = 'Confusion/Anxiety'),
    (SELECT id FROM genres WHERE media_type = 'tv' AND external_id = '18'),
    0.33
);

-- Ambient/Soundscape
INSERT INTO mood_genre_mapping (mood_id, genre_id, relevance_score) 
VALUES 
(
    (SELECT id FROM moods WHERE name = 'Confusion/Anxiety'),
    (SELECT id FROM genres WHERE media_type = 'music' AND name = 'Ambient/Soundscape'),
    0.53
);

-- Puzzle (game) — closest proxy, no clean genre match (per your notes)
INSERT INTO mood_genre_mapping (mood_id, genre_id, relevance_score) VALUES (
    (SELECT id FROM moods WHERE name = 'Confusion/Anxiety'),
    (SELECT id FROM genres WHERE media_type = 'game' AND external_id = 'puzzle'),
    0.47
);

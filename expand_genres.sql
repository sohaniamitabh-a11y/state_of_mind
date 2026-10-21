-- expand_genres.sql
-- Adds the genres missing from the current partial 38-row seed.
-- Run via run_seed.py (or your existing runner) same as seed_mood_genre.sql --
-- it already skips duplicate-entry errors, so this is safe to re-run.

-- NOTE: media_type values below are assumed to match your existing rows
-- ('movie', 'tv', 'game', 'music'). Check one existing row in `genres`
-- (e.g. SELECT DISTINCT media_type FROM genres;) before running --
-- if your seed_mood_genre.sql used different casing/plurals, edit these first.

-- 8 missing TMDB movie genres
INSERT INTO genres (media_type, external_id, name) VALUES
('movie', '16',    'Animation'),
('movie', '80',    'Crime'),
('movie', '10751', 'Family'),
('movie', '27',    'Horror'),
('movie', '10402', 'Music'),
('movie', '10749', 'Romance'),
('movie', '10770', 'TV Movie'),
('movie', '37',    'Western');

-- 9 missing TMDB TV genres
INSERT INTO genres (media_type, external_id, name) VALUES
('tv', '16',    'Animation'),
('tv', '80',    'Crime'),
('tv', '10751', 'Family'),
('tv', '10762', 'Kids'),
('tv', '10763', 'News'),
('tv', '10764', 'Reality'),
('tv', '10766', 'Soap'),
('tv', '10767', 'Talk'),
('tv', '37',    'Western');

-- 8 missing RAWG game genre slugs
INSERT INTO genres (media_type, external_id, name) VALUES
('game', 'casual',              'Casual'),
('game', 'platformer',          'Platformer'),
('game', 'massively-multiplayer','Massively Multiplayer'),
('game', 'family',              'Family'),
('game', 'board-games',         'Board Games'),
('game', 'educational',         'Educational'),
('game', 'card',                'Card'),
('game', 'indie',               'Indie');

-- This brings movie genres to the full 19, TV genres to the full 16,
-- and RAWG game genres to the full 19. Music genres are left as-is
-- (Deezer has no fixed taxonomy like TMDB/RAWG, so those 10 name-only
-- buckets were invented, not pulled from an API list).

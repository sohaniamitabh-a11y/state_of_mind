USE state_of_mind;

-- 5 moods
INSERT INTO moods (name) VALUES
('Happy/Excitement'),
('Calm/Serene'),
('Sad/Melancholy'),
('Anger/Rage'),
('Confusion/Anxiety');

-- Movie genres (TMDB numeric IDs)
INSERT INTO genres (media_type, external_id, name) VALUES
('movie', '35', 'Comedy'),
('movie', '12', 'Adventure'),
('movie', '28', 'Action'),
('movie', '99', 'Documentary'),
('movie', '14', 'Fantasy'),
('movie', '878', 'Science Fiction'),
('movie', '18', 'Drama'),
('movie', '10752', 'War'),
('movie', '36', 'History'),
('movie', '53', 'Thriller'),
('movie', '9648', 'Mystery');

-- TV genres (TMDB numeric IDs)
INSERT INTO genres (media_type, external_id, name) VALUES
('tv', '35', 'Comedy'),
('tv', '10759', 'Action & Adventure'),
('tv', '99', 'Documentary'),
('tv', '10765', 'Sci-Fi & Fantasy'),
('tv', '18', 'Drama'),
('tv', '10768', 'War & Politics'),
('tv', '9648', 'Mystery');

-- Music genres (matched by name, no external_id)
INSERT INTO genres (media_type, external_id, name) VALUES
('music', NULL, 'Pop'),
('music', NULL, 'Dance/EDM'),
('music', NULL, 'Rap/Hip-Hop'),
('music', NULL, 'Jazz/Acoustic'),
('music', NULL, 'Blues'),
('music', NULL, 'Classical'),
('music', NULL, 'Metal'),
('music', NULL, 'Punk'),
('music', NULL, 'Techno'),
('music', NULL, 'Ambient/Soundscape');

-- Game genres (RAWG slugs)
INSERT INTO genres (media_type, external_id, name) VALUES
('game', 'racing', 'Racing'),
('game', 'sports', 'Sports'),
('game', 'arcade', 'Arcade'),
('game', 'simulation', 'Simulation'),
('game', 'strategy', 'Strategy'),
('game', 'role-playing-games-rpg', 'Role-Playing Games (RPG)'),
('game', 'adventure', 'Adventure'),
('game', 'shooter', 'Shooter'),
('game', 'fighting', 'Fighting'),
('game', 'puzzle', 'Puzzle');
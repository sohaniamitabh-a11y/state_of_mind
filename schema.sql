-- =========================================================

-- STATE OF MIND — DATABASE SCHEMA (Stage 2)
-- MySQL syntax — for your local root connection (XAMPP / MySQL
-- Workbench), run via VS Code with Ctrl+Enter.
-- =========================================================


-- Run this first so these tables live in their own database,
-- separate from your student-details ones:
CREATE DATABASE IF NOT EXISTS state_of_mind;
USE state_of_mind;
-- USE tells MySQL "everything below happens inside this database."
-- Skip this and your CREATE TABLEs land wherever your connection
-- was last pointed — usually not what you want.


-- ---------------------------------------------------------
-- TABLE 1: moods
-- Your 5 moods live here as ROWS, not hardcoded anywhere else.
-- Adding a 6th mood later = one INSERT, zero schema changes.
-- ---------------------------------------------------------
CREATE TABLE moods (
    id   INT AUTO_INCREMENT PRIMARY KEY,
    -- AUTO_INCREMENT = MySQL fills this in for you (1, 2, 3...)
    -- on every INSERT. You never type it yourself.
    -- (Postgres calls the same idea SERIAL — different word,
    -- same behaviour.)

    name VARCHAR(100) NOT NULL UNIQUE
    -- VARCHAR(100), not TEXT — MySQL won't let you put a UNIQUE
    -- constraint directly on a TEXT column without extra work
    -- (it needs a fixed max length to build the index on). 100
    -- characters is more than enough for a mood name.
);


-- ---------------------------------------------------------
-- TABLE 2: genres
-- Every genre from every source (TMDB, RAWG, Deezer, plus
-- invented ones like your ambient-soundscape bucket) lives here,
-- tagged with which media_type it belongs to.
-- ---------------------------------------------------------
CREATE TABLE genres (
    id          INT AUTO_INCREMENT PRIMARY KEY,

    media_type  VARCHAR(50) NOT NULL,
    -- 'movie', 'tv', 'game', 'track' today — 'food', 'makeup',
    -- whatever else later. Plain string, not a fixed list — that's
    -- what lets you add new domains without touching the schema.

    external_id VARCHAR(100),
    -- The genre ID from the real API — TMDB's '28', RAWG's
    -- 'shooter'. Nullable, because invented buckets (ambient
    -- soundscape) don't come from any API and have no external_id.

    name        VARCHAR(100) NOT NULL,

    UNIQUE (media_type, external_id)
    -- A UNIQUE constraint across TWO columns together: the PAIR
    -- must be unique, not each column alone. Needed because a
    -- genre id from one source shouldn't collide with an
    -- unrelated id that happens to match from another source.
);


-- ---------------------------------------------------------
-- TABLE 3: mood_genre_mapping — this is "the Brain"
-- Links moods to genres with a WEIGHT instead of a flat yes/no.
-- ---------------------------------------------------------
CREATE TABLE mood_genre_mapping (
    mood_id         INT NOT NULL,
    genre_id        INT NOT NULL,

    relevance_score DECIMAL(4,2) NOT NULL,
    -- DECIMAL(4,2) = up to 4 total digits, 2 of them after the
    -- decimal point (e.g. 0.90, 12.50). This matters: plain
    -- DECIMAL with no numbers in parentheses defaults to ZERO
    -- decimal places in MySQL, which would silently round 0.9
    -- down to 1 and wreck your weighting. Always specify both
    -- numbers.

    PRIMARY KEY (mood_id, genre_id),
    -- A composite key: the PAIR (mood_id, genre_id) must be
    -- unique — one mood can't link to the same genre twice —
    -- but a genre CAN belong to multiple moods with different
    -- scores, which is exactly what you want.

    FOREIGN KEY (mood_id) REFERENCES moods(id),
    FOREIGN KEY (genre_id) REFERENCES genres(id)
    -- FOREIGN KEY, written this way, is required in MySQL. Some
    -- other databases let you write "mood_id INT REFERENCES
    -- moods(id)" inline and it just works — MySQL parses that
    -- but quietly ignores it, so the constraint never actually
    -- gets created. This explicit form is the one that sticks.
);


-- ---------------------------------------------------------
-- TABLE 4: items
-- Every actual thing you harvest — a movie, a game, a track, and
-- later maybe a food or a makeup product. ONE table for all of it.
-- ---------------------------------------------------------
CREATE TABLE items (
    id               INT AUTO_INCREMENT PRIMARY KEY,
    media_type       VARCHAR(50) NOT NULL,
    external_id      VARCHAR(100) NOT NULL,
    title            VARCHAR(255) NOT NULL,

    popularity_score DECIMAL(10,2),
    -- 10 total digits, 2 decimal places — comfortably covers
    -- both small ratings and big popularity numbers from
    -- whichever API this came from.

    metadata         JSON,
    -- JSON (not JSONB — that's a Postgres-only variant). Same
    -- idea: a flexible blob for whatever's unique to this item —
    -- {"artist": "..."} for a track, {"cuisine": "..."} for a
    -- future food item — without adding new columns each time.

    harvested_at     TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    -- If you don't supply a value on insert, MySQL stamps the
    -- current date/time automatically.

    UNIQUE (media_type, external_id)
    -- Stops the Harvester from inserting the same movie/game/
    -- track twice if it runs again tomorrow.
);


-- ---------------------------------------------------------
-- TABLE 5: item_genres
-- A single movie can be BOTH Action and Comedy at once, so one
-- item needs to link to MULTIPLE genres. This junction table
-- makes that possible.
-- ---------------------------------------------------------
CREATE TABLE item_genres (
    item_id  INT NOT NULL,
    genre_id INT NOT NULL,
    PRIMARY KEY (item_id, genre_id),
    FOREIGN KEY (item_id) REFERENCES items(id),
    FOREIGN KEY (genre_id) REFERENCES genres(id)
);


-- ---------------------------------------------------------
-- TABLE 6: feedback
-- Thumbs up / down on a specific recommendation.
-- ---------------------------------------------------------
CREATE TABLE feedback (
    id         INT AUTO_INCREMENT PRIMARY KEY,
    mood_id    INT,
    item_id    INT,

    feedback   BOOLEAN,
    -- MySQL doesn't have a real separate BOOLEAN type — this is
    -- silently stored as TINYINT(1), where 1 = true (thumbs up)
    -- and 0 = false (thumbs down). You can still write TRUE/FALSE
    -- when inserting; MySQL converts it for you.

    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (mood_id) REFERENCES moods(id),
    FOREIGN KEY (item_id) REFERENCES items(id)
);

-- =========================================================
-- END OF SCHEMA. Once this runs clean with no errors, insert a
-- few rows by hand into moods, genres, mood_genre_mapping, items,
-- and item_genres, then try the JOIN query from earlier to see
-- your own data come back out. That's the real test.
-- =========================================================

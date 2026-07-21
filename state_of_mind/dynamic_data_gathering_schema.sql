-- ================================================================
-- DYNAMIC DATA GATHERING — new tables for State of Mind
-- Extends the existing schema (moods, genres, mood_genre_mapping,
-- items, item_genres, feedback). Run these ONE AT A TIME in your
-- DB Notebook (per your golden rule — never re-run a statement
-- that already succeeded).
-- ================================================================


-- 1. emojis
-- The fixed set of emoji buttons users tap to answer questions.
-- Kept as its own table (rather than typing the character straight
-- into every response row) so the same emoji is reused across every
-- question without re-storing it each time, and so you can add or
-- remove emoji options later without touching any other table.
CREATE TABLE emojis (
    id INT AUTO_INCREMENT PRIMARY KEY,
    emoji_char VARCHAR(10) NOT NULL UNIQUE,  -- VARCHAR, not TEXT: TEXT can't carry a UNIQUE constraint in MySQL
    label VARCHAR(100) NOT NULL              -- human-readable name, e.g. "grinning_face" — for your own sanity reading raw rows
);


-- 2. emoji_mood_weights
-- The "psychology key": how strongly picking a given emoji, in
-- response to a GENERIC question, signals each mood. Composite
-- primary key (emoji_id, mood_id) means every emoji has exactly
-- ONE weight per mood — same shape as mood_genre_mapping's
-- (mood_id, genre_id) composite key.
CREATE TABLE emoji_mood_weights (
    emoji_id INT NOT NULL,
    mood_id INT NOT NULL,
    weight DECIMAL(4,2) NOT NULL,  -- explicit precision/scale — same reasoning as relevance_score, MySQL silently rounds to 0 decimals otherwise
    PRIMARY KEY (emoji_id, mood_id),
    FOREIGN KEY (emoji_id) REFERENCES emojis(id),
    FOREIGN KEY (mood_id) REFERENCES moods(id)
);


-- 3. questions
-- The generic/decoy prompts themselves — deliberately mood-agnostic
-- ("is this tool helpful?" works identically whether it's shown to
-- someone in Rage or someone in Calm). The mood context comes from
-- emoji_mood_weights, not from the question text.
CREATE TABLE questions (
    id INT AUTO_INCREMENT PRIMARY KEY,
    question_text VARCHAR(255) NOT NULL
);


-- 4. user_sessions
-- One row per "mood pick -> question loop" a single user goes
-- through. Tracks the running DataScore and how many questions
-- they've faced so far, so the adaptive loop knows when to stop
-- (threshold hit, or the 8-question cap reached).
CREATE TABLE user_sessions (
    id INT AUTO_INCREMENT PRIMARY KEY,
    mood_id INT NOT NULL,                                -- the mood the user originally selected
    data_score DECIMAL(4,2) NOT NULL DEFAULT 0.00,       -- running confidence score, updates as responses come in
    questions_asked INT NOT NULL DEFAULT 0,               -- counter against your 5 (ideal) / 8 (max) cap
    status VARCHAR(20) NOT NULL DEFAULT 'in_progress',    -- 'in_progress' or 'completed'
    started_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (mood_id) REFERENCES moods(id)
);


-- 5. session_responses
-- The raw log: every (question, emoji) a user actually picked
-- during one session. This is the table you keep for future
-- model training — a session's data_score is DERIVED from these
-- rows, but this table preserves each individual answer, not just
-- the final number, so nothing is lost once the session ends.
CREATE TABLE session_responses (
    id INT AUTO_INCREMENT PRIMARY KEY,
    session_id INT NOT NULL,
    question_id INT NOT NULL,
    emoji_id INT NOT NULL,
    responded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (session_id) REFERENCES user_sessions(id),
    FOREIGN KEY (question_id) REFERENCES questions(id),
    FOREIGN KEY (emoji_id) REFERENCES emojis(id)
);

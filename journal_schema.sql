-- ================================================================
-- STATE OF MIND — USER JOURNAL & COLLECTIONS SCHEMA
-- Extension tables for the "My Journal" personal scrapbook and
-- custom collections feature in MySQL.
-- Compatible with anonymous browser identity isolation.
-- ================================================================

USE state_of_mind;

-- 1. user_journal
-- Stores personal logs, ratings, notes, moods, and wishlists.
CREATE TABLE IF NOT EXISTS user_journal (
    id INT AUTO_INCREMENT PRIMARY KEY,

    -- Anonymous browser / client UUID for user isolation without login
    user_id VARCHAR(64) NOT NULL DEFAULT 'anonymous_user',

    -- Optional link to the existing `items` table if the entry was
    -- saved from the State of Mind recommendation engine. Nullable so
    -- users can freely log custom entries not in the cache.
    item_id INT NULL,

    title VARCHAR(255) NOT NULL,

    -- 'movie', 'tv', 'music', 'game' (matching the genres/items media_type)
    media_type VARCHAR(50) NOT NULL,

    -- Link to the 5 core moods in `moods` table (Nullable for wishlist items)
    mood_id INT NULL,

    -- Rating out of 5 stars (e.g. 4.5, 5.0)
    rating DECIMAL(2,1) NULL,

    -- The date the user watched, listened to, or played this item
    date_experienced DATE NULL,

    -- Personal thoughts, review notes, or memory snippets
    notes TEXT NULL,

    -- Favorite flag (TINYINT(1) / boolean)
    is_favorite BOOLEAN DEFAULT FALSE,

    -- 'experienced' (completed history) or 'wishlist' (want to explore later)
    status VARCHAR(20) NOT NULL DEFAULT 'experienced',

    -- Flexible JSON metadata for poster URLs, creators, genres, tags
    metadata JSON NULL,

    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    INDEX idx_user_journal_user (user_id),
    INDEX idx_user_journal_status (user_id, status),
    INDEX idx_user_journal_fav (user_id, is_favorite),
    FOREIGN KEY (item_id) REFERENCES items(id) ON DELETE SET NULL,
    FOREIGN KEY (mood_id) REFERENCES moods(id) ON DELETE SET NULL
);

-- 2. user_collections
-- Allows users to organize movies, TV shows, music, and games into
-- arbitrary custom lists (e.g., "Weekend Chill", "Top RPGs").
CREATE TABLE IF NOT EXISTS user_collections (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id VARCHAR(64) NOT NULL DEFAULT 'anonymous_user',
    name VARCHAR(150) NOT NULL,
    description TEXT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    INDEX idx_user_collections_user (user_id),
    UNIQUE (user_id, name)
);

-- 3. user_collection_items
-- Many-to-many link between user_collections and user_journal entries.
CREATE TABLE IF NOT EXISTS user_collection_items (
    collection_id INT NOT NULL,
    journal_id INT NOT NULL,
    added_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (collection_id, journal_id),
    FOREIGN KEY (collection_id) REFERENCES user_collections(id) ON DELETE CASCADE,
    FOREIGN KEY (journal_id) REFERENCES user_journal(id) ON DELETE CASCADE
);

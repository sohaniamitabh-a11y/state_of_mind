"""
harvest_games.py
------------------
DEVICE 2's job in the 3-device midnight harvest: RAWG only (games).

IMPORTANT HONEST NOTE: RAWG has no dedicated "trending today" endpoint
the way TMDB does. This script approximates it by asking for games
ordered by -added (most added to users' libraries recently), which is
RAWG's own recommended way to surface currently-popular titles. If you
want a different notion of "trending" later (e.g. highest-rated this
month), that's a one-line change to the `ordering` param below.

SETUP:
    pip install requests mysql-connector-python python-dotenv
    Create a .env file next to this script:
        RAWG_API_KEY=your_real_key_here
        DB_HOST=your_cloud_db_host
        DB_PORT=3306
        DB_USER=your_cloud_db_user
        DB_PASSWORD=your_cloud_db_password
        DB_NAME=state_of_mind
        DB_SSL_CA=./ignore/ca.pem
"""

import os
import json
import requests
import mysql.connector
from dotenv import load_dotenv
load_dotenv()

RAWG_API_KEY = os.getenv("RAWG_API_KEY")

DB_CONFIG = {
    "host": os.getenv("DB_HOST", "localhost"),
    "port": int(os.getenv("DB_PORT", "3306")),
    "user": os.getenv("DB_USER", "root"),
    "password": os.getenv("DB_PASSWORD", ""),
    "database": os.getenv("DB_NAME", "state_of_mind"),
    "ssl_ca": os.getenv("DB_SSL_CA"),
    "ssl_verify_cert": True,
}


def main():
    if not RAWG_API_KEY:
        raise RuntimeError("RAWG_API_KEY is not set in .env")

    connection = mysql.connector.connect(**DB_CONFIG)
    try:
        print("[games] Connected to shared state_of_mind database.")
        harvest_games(connection)
        print("[games] Harvest run complete.")
    finally:
        connection.close()


def harvest_games(connection):
    url = "https://api.rawg.io/api/games"
    response = requests.get(url, params={
        "key": RAWG_API_KEY,
        "ordering": "-added",  # proxy for "trending" -- see note at top of file
        "page_size": 20,
    })
    response.raise_for_status()

    games = response.json()["results"]
    print(f"[games] RAWG returned {len(games)} games.")

    for game in games:
        rawg_id = game["id"]
        title = game["name"]
        # RAWG doesn't expose a single 0-100 "popularity" field the way
        # TMDB does -- "added" (how many users have this in a list) is
        # the closest equivalent, so that's what fills popularity_score.
        popularity = game.get("added", 0)
        metadata_json = json.dumps(game)

        internal_item_id = upsert_item(connection, rawg_id, title, popularity, metadata_json)

        # RAWG conveniently gives genre SLUGS directly on each game --
        # the same slugs you already used as external_id when you
        # populated the genres table, so no numeric-id translation
        # step is needed here (unlike the TMDB movies/TV branch).
        genre_slugs = [g["slug"] for g in game.get("genres", [])]
        link_item_genres(connection, internal_item_id, genre_slugs)


def upsert_item(connection, rawg_id, title, popularity, metadata_json):
    sql = """
        INSERT INTO items (media_type, external_id, title, popularity_score, metadata)
        VALUES (%s, %s, %s, %s, %s)
        ON DUPLICATE KEY UPDATE
            popularity_score = VALUES(popularity_score),
            harvested_at = CURRENT_TIMESTAMP
    """
    cursor = connection.cursor()
    cursor.execute(sql, ("game", str(rawg_id), title, popularity, metadata_json))
    connection.commit()

    if cursor.lastrowid:
        item_id = cursor.lastrowid
    else:
        cursor.execute(
            "SELECT id FROM items WHERE media_type = 'game' AND external_id = %s",
            (str(rawg_id),),
        )
        item_id = cursor.fetchone()[0]

    cursor.close()
    return item_id


def link_item_genres(connection, internal_item_id, genre_slugs):
    cursor = connection.cursor()
    for slug in genre_slugs:
        cursor.execute(
            "SELECT id FROM genres WHERE media_type = 'game' AND external_id = %s",
            (slug,),
        )
        row = cursor.fetchone()
        if row is None:
            print(f"[games] Warning: no matching genre row for RAWG slug '{slug}' "
                  f"(this game may use a genre outside your original 19-slug list)")
            continue

        cursor.execute(
            "INSERT IGNORE INTO item_genres (item_id, genre_id) VALUES (%s, %s)",
            (internal_item_id, row[0]),
        )
    connection.commit()
    cursor.close()


if __name__ == "__main__":
    main()

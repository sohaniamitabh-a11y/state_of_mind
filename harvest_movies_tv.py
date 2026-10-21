"""
harvest_movies_tv.py
---------------------
DEVICE 1's job in the 3-device midnight harvest: TMDB only (movies + TV).
This script does NOT touch RAWG or Deezer -- keeping each device to one
API keeps memory/connection load light on any single machine, and if one
device's harvest fails, it doesn't take the other two down with it.

Run once per invocation, no internal loop. Scheduling (cron / Windows
Task Scheduler, midnight trigger) happens OUTSIDE this file, at the OS
level on this device.

SETUP:
    pip install requests mysql-connector-python python-dotenv
    Create a .env file next to this script:
        TMDB_API_KEY=your_real_key_here
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

TMDB_API_KEY = os.getenv("TMDB_API_KEY")

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
    if not TMDB_API_KEY:
        raise RuntimeError("TMDB_API_KEY is not set in .env")

    connection = mysql.connector.connect(**DB_CONFIG)
    try:
        print("[movies_tv] Connected to shared state_of_mind database.")
        harvest_trending(connection, "movie")
        harvest_trending(connection, "tv")
        print("[movies_tv] Harvest run complete.")
    finally:
        connection.close()


def harvest_trending(connection, media_type):
    """
    media_type is either 'movie' or 'tv' -- TMDB exposes a separate
    trending endpoint for each, but the response shape and the logic to
    store it are identical, so one function handles both.
    """
    url = f"https://api.themoviedb.org/3/trending/{media_type}/day"
    response = requests.get(url, params={"api_key": TMDB_API_KEY})
    response.raise_for_status()

    results = response.json()["results"]
    print(f"[movies_tv] TMDB returned {len(results)} trending {media_type} entries.")

    for entry in results:
        # TV entries use "name" for the title field; movies use "title".
        title = entry.get("title") or entry.get("name")
        tmdb_id = entry["id"]
        popularity = entry["popularity"]
        genre_ids = entry["genre_ids"]
        metadata_json = json.dumps(entry)

        internal_item_id = upsert_item(connection, media_type, tmdb_id, title, popularity, metadata_json)
        link_item_genres(connection, media_type, internal_item_id, genre_ids)


def upsert_item(connection, media_type, tmdb_id, title, popularity, metadata_json):
    sql = """
        INSERT INTO items (media_type, external_id, title, popularity_score, metadata)
        VALUES (%s, %s, %s, %s, %s)
        ON DUPLICATE KEY UPDATE
            popularity_score = VALUES(popularity_score),
            harvested_at = CURRENT_TIMESTAMP
    """
    cursor = connection.cursor()
    cursor.execute(sql, (media_type, str(tmdb_id), title, popularity, metadata_json))
    connection.commit()

    if cursor.lastrowid:
        item_id = cursor.lastrowid
    else:
        cursor.execute(
            "SELECT id FROM items WHERE media_type = %s AND external_id = %s",
            (media_type, str(tmdb_id)),
        )
        item_id = cursor.fetchone()[0]

    cursor.close()
    return item_id


def link_item_genres(connection, media_type, internal_item_id, tmdb_genre_ids):
    cursor = connection.cursor()
    for tmdb_genre_id in tmdb_genre_ids:
        cursor.execute(
            "SELECT id FROM genres WHERE media_type = %s AND external_id = %s",
            (media_type, str(tmdb_genre_id)),
        )
        row = cursor.fetchone()
        if row is None:
            print(f"[movies_tv] Warning: no matching genre row for {media_type} TMDB id {tmdb_genre_id}")
            continue

        cursor.execute(
            "INSERT IGNORE INTO item_genres (item_id, genre_id) VALUES (%s, %s)",
            (internal_item_id, row[0]),
        )
    connection.commit()
    cursor.close()


if __name__ == "__main__":
    main()

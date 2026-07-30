"""
harvest_music.py
------------------
DEVICE 3's job in the 3-device midnight harvest: Deezer only (music).

IMPORTANT HONEST FLAG, carried over from earlier project notes: Deezer's
track objects don't include genre directly -- genre lives on the ALBUM,
which means one extra API call per track (fetching /album/{id}) to get
at it. This script does that extra call, but Deezer's genre id/name
list was never independently verified as reliable in this project
(automated fetching of their full genre list was blocked earlier), so
genre-matching here is done by NAME against your genres table and will
silently skip a track's genre link if no name match is found, rather
than guessing. Expect some tracks to land in `items` with zero rows in
item_genres until this gap gets revisited -- that's a known limitation,
not a bug in this script.

SETUP:
    pip install requests mysql-connector-python python-dotenv
    Create a .env file next to this script:
        DB_HOST=your_cloud_db_host
        DB_PORT=3306
        DB_USER=your_cloud_db_user
        DB_PASSWORD=your_cloud_db_password
    (Deezer's public chart/album endpoints don't require an API key for
    read-only access at the time this was written -- if that's changed,
    you'll see a 401/403 from requests.raise_for_status() below and
    you'll need to add key-based auth at that point.)
"""

import os
import json
import time
import requests
import mysql.connector
from dotenv import load_dotenv

load_dotenv()

DB_CONFIG = {
    "host": os.getenv("DB_HOST", "localhost"),
    "port": int(os.getenv("DB_PORT", "3306")),
    "user": os.getenv("DB_USER", "root"),
    "password": os.getenv("DB_PASSWORD", ""),
    "database": "state_of_mind",
}


def main():
    connection = mysql.connector.connect(**DB_CONFIG)
    try:
        print("[music] Connected to shared state_of_mind database.")
        harvest_chart(connection)
        print("[music] Harvest run complete.")
    finally:
        connection.close()


def harvest_chart(connection):
    response = requests.get("https://api.deezer.com/chart/0/tracks")
    response.raise_for_status()

    tracks = response.json()["data"]
    print(f"[music] Deezer returned {len(tracks)} chart tracks.")

    for track in tracks:
        deezer_id = track["id"]
        title = track["title"]
        popularity = track.get("rank", 0)
        metadata_json = json.dumps(track)

        internal_item_id = upsert_item(connection, deezer_id, title, popularity, metadata_json)

        genre_names = fetch_album_genre_names(track)
        link_item_genres(connection, internal_item_id, genre_names)

        # Small delay to stay polite to Deezer's API since this loop
        # makes one extra request per track (fetching the album).
        time.sleep(0.2)


def fetch_album_genre_names(track):
    """
    Deezer tracks reference an album, and genre data lives on the album,
    not the track. This makes one extra call per track to get it.
    Returns a list of genre name strings (e.g. ["Pop", "Rap/Hip-Hop"]),
    or an empty list if the album has no genre data / the call fails.
    """
    album_id = track.get("album", {}).get("id")
    if not album_id:
        return []

    try:
        response = requests.get(f"https://api.deezer.com/album/{album_id}")
        response.raise_for_status()
        album = response.json()
        genre_list = album.get("genres", {}).get("data", [])
        return [g["name"] for g in genre_list]
    except requests.RequestException as e:
        print(f"[music] Warning: could not fetch album {album_id} genres ({e})")
        return []


def upsert_item(connection, deezer_id, title, popularity, metadata_json):
    sql = """
        INSERT INTO items (media_type, external_id, title, popularity_score, metadata)
        VALUES (%s, %s, %s, %s, %s)
        ON DUPLICATE KEY UPDATE
            popularity_score = VALUES(popularity_score),
            harvested_at = CURRENT_TIMESTAMP
    """
    cursor = connection.cursor()
    cursor.execute(sql, ("music", str(deezer_id), title, popularity, metadata_json))
    connection.commit()

    if cursor.lastrowid:
        item_id = cursor.lastrowid
    else:
        cursor.execute(
            "SELECT id FROM items WHERE media_type = 'music' AND external_id = %s",
            (str(deezer_id),),
        )
        item_id = cursor.fetchone()[0]

    cursor.close()
    return item_id


def link_item_genres(connection, internal_item_id, genre_names):
    cursor = connection.cursor()
    for name in genre_names:
        cursor.execute(
            "SELECT id FROM genres WHERE media_type = 'music' AND name = %s",
            (name,),
        )
        row = cursor.fetchone()
        if row is None:
            # Expected to happen often right now -- Deezer's genre
            # vocabulary doesn't line up 1:1 with your 10 curated music
            # genre names. Skipping rather than guessing a match.
            continue

        cursor.execute(
            "INSERT IGNORE INTO item_genres (item_id, genre_id) VALUES (%s, %s)",
            (internal_item_id, row[0]),
        )
    connection.commit()
    cursor.close()


if __name__ == "__main__":
    main()

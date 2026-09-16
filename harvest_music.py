"""
harvest_music.py
------------------
DEVICE 3's job in the 3-device midnight harvest: Deezer only (music).

IMPORTANT HONEST FLAG: Deezer's track objects don't include genre
directly -- genre lives on the ALBUM, which means one extra API call
per track (fetching /album/{id}) to get at it. This script does that
extra call. Genre matching is still by NAME against the music rows in
`genres` (Deezer has no fixed ID taxonomy we seed against), but near-
miss Deezer names are remapped through GENRE_ALIASES first, and if a
track ends up with zero linked genres it falls back to the curated
"Other" bucket so the mood → genre → item join can still reach it.
Individual unmatched names are still silently skipped when at least
one other name on the same track matched -- we only invent the Other
link when nothing matched at all.

Requires `add_other_music_genre.sql` to have been applied (via
`run_add_other_music_genre.py`) so the Other genre and its Brain rows
exist before this harvester runs.

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

# Deezer name (normalized) → curated genres.name. Exact matches are
# tried first; this only covers clear near-misses from Deezer's list.
GENRE_ALIASES = {
    "dance": "Dance/EDM",
    "rap/hip hop": "Rap/Hip-Hop",
    "jazz": "Jazz/Acoustic",
    "electro": "Techno",
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


def normalize_genre_name(name):
    """Lowercase, strip, collapse internal whitespace for alias lookup."""
    return " ".join(name.lower().strip().split())


def link_item_genres(connection, internal_item_id, genre_names):
    cursor = connection.cursor()
    matched_any = False

    for name in genre_names:
        cursor.execute(
            "SELECT id FROM genres WHERE media_type = 'music' AND name = %s",
            (name,),
        )
        row = cursor.fetchone()

        if row is None:
            aliased = GENRE_ALIASES.get(normalize_genre_name(name))
            if aliased is not None:
                cursor.execute(
                    "SELECT id FROM genres WHERE media_type = 'music' AND name = %s",
                    (aliased,),
                )
                row = cursor.fetchone()

        if row is None:
            # Unmatched individual name -- skip silently when another
            # name on this track already matched (or will). Only the
            # zero-match case below falls back to Other.
            continue

        cursor.execute(
            "INSERT IGNORE INTO item_genres (item_id, genre_id) VALUES (%s, %s)",
            (internal_item_id, row[0]),
        )
        matched_any = True

    # Fallback: track had genre names but none mapped to a curated
    # bucket -- link Other so it stays reachable from the Brain join.
    if not matched_any and genre_names:
        cursor.execute(
            "SELECT id FROM genres WHERE media_type = 'music' AND name = %s",
            ("Other",),
        )
        other_row = cursor.fetchone()
        if other_row is None:
            print(
                "[music] Warning: no 'Other' music genre row -- "
                "run add_other_music_genre.sql before harvesting"
            )
        else:
            cursor.execute(
                "INSERT IGNORE INTO item_genres (item_id, genre_id) VALUES (%s, %s)",
                (internal_item_id, other_row[0]),
            )

    connection.commit()
    cursor.close()


if __name__ == "__main__":
    main()

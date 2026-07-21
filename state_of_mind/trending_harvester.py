"""
trending_harvester.py
----------------------
This is "The Harvester" component of the State of Mind project, in Python.

WHAT IT DOES, IN PLAIN TERMS:
    1. Calls TMDB's "trending movies" endpoint (a live API on the internet)
    2. Reads the JSON it sends back
    3. Writes each movie into your existing `items` table (MySQL)
    4. Maps TMDB's genre numbers to YOUR OWN genre ids (from your `genres`
       table) and writes those links into `item_genres`

This script does NOT loop or schedule itself. You run it once
(`python trending_harvester.py`), it does its work, and exits. Making it
"run every day" is the job of an OS scheduler (Windows Task Scheduler, or
cron on Linux/Mac) -- NOT something coded inside this file. Point the
scheduler at this script the same way you'd point it at any program.

DEPENDENCIES YOU NEED TO INSTALL (this script doesn't work standalone):
    pip install requests mysql-connector-python

    - requests               -> makes the HTTP call to TMDB
    - mysql-connector-python -> lets Python talk to MySQL
    JSON parsing needs no extra library -- Python's built-in `json` module
    (and requests' own .json() helper) handles it.
"""

import json
import requests
import mysql.connector


# ---- CONFIG -------------------------------------------------------------
# Hardcoding these here for clarity/learning purposes. In a real deployment
# you'd load these from a config file or environment variables instead of
# typing them directly into the source code (especially the API key --
# never commit a real key to GitHub).
TMDB_API_KEY = "YOUR_TMDB_API_KEY_HERE"

DB_CONFIG = {
    "host": "localhost",
    "user": "root",
    "password": "",   # XAMPP's default root password is blank
    "database": "state_of_mind",
}


def main():
    # mysql.connector.connect() opens the connection. Using a plain
    # try/finally (instead of Java's try-with-resources) to guarantee the
    # connection gets closed even if something below throws an error --
    # Python's equivalent idiom here is a `with` block, which
    # mysql-connector's connection object also supports.
    connection = mysql.connector.connect(**DB_CONFIG)
    try:
        print("Connected to state_of_mind database.")
        harvest_trending_movies(connection)
        print("Harvest run complete.")
    finally:
        connection.close()


def harvest_trending_movies(connection):
    """
    Pulls TMDB's "trending movies, today" list and writes it into
    items + item_genres.
    """

    # --- STEP 1: Make the HTTP request to TMDB ---------------------------
    # requests.get() does the HTTP call in one line. .json() parses the
    # response body (which is JSON text) straight into a Python dict/list,
    # no manual string parsing needed.
    url = "https://api.themoviedb.org/3/trending/movie/day"
    response = requests.get(url, params={"api_key": TMDB_API_KEY})
    response.raise_for_status()  # throws an error here if TMDB returned a failure status (4xx/5xx)

    trending_movies = response.json()["results"]  # a list of dicts, one per movie
    print(f"TMDB returned {len(trending_movies)} trending movies.")

    # --- STEP 2: Loop over every movie in the response -------------------
    for movie in trending_movies:
        tmdb_id = movie["id"]
        title = movie["title"]
        popularity = movie["popularity"]
        genre_ids = movie["genre_ids"]  # TMDB's own genre numbers, e.g. [28, 12]

        # Save the whole raw movie dict into the `metadata` JSON column
        # too, in case you need extra fields later (poster path, overview,
        # etc.) without re-fetching from TMDB.
        metadata_json = json.dumps(movie)

        internal_item_id = upsert_item(connection, tmdb_id, title, popularity, metadata_json)
        link_item_genres(connection, internal_item_id, genre_ids)


def upsert_item(connection, tmdb_id, title, popularity, metadata_json):
    """
    Inserts a movie into `items`, or updates it if it's already there
    (same media_type + external_id = already harvested before).

    Returns YOUR internal items.id (the AUTO_INCREMENT primary key),
    which item_genres needs -- NOT TMDB's id.
    """

    # ON DUPLICATE KEY UPDATE: this is MySQL's built-in "upsert". Because
    # items has UNIQUE(media_type, external_id), inserting the same movie
    # twice would normally throw an error. This clause tells MySQL: "if
    # that happens, just update these columns on the existing row instead
    # of erroring out."
    sql = """
        INSERT INTO items (media_type, external_id, title, popularity_score, metadata)
        VALUES (%s, %s, %s, %s, %s)
        ON DUPLICATE KEY UPDATE
            popularity_score = VALUES(popularity_score),
            harvested_at = CURRENT_TIMESTAMP
    """

    # cursor is your "pen" for talking to the DB -- every query goes
    # through one. The %s placeholders get filled in safely from the
    # tuple below (mysql-connector's parameter style, not Python's own
    # %-formatting) -- this avoids SQL injection. Never build the query
    # string by concatenating raw values into it directly.
    cursor = connection.cursor()
    cursor.execute(sql, ("movie", str(tmdb_id), title, popularity, metadata_json))
    connection.commit()  # writes the change to disk immediately

    # cursor.lastrowid is Python's equivalent of Java's getGeneratedKeys()
    # / MySQL's LAST_INSERT_ID(). GOTCHA: if this INSERT actually became
    # an UPDATE (because the movie already existed), lastrowid can come
    # back as 0 instead of the real id -- so we fall back to looking the
    # row up directly whenever that happens.
    if cursor.lastrowid:
        item_id = cursor.lastrowid
    else:
        cursor.execute(
            "SELECT id FROM items WHERE media_type = %s AND external_id = %s",
            ("movie", str(tmdb_id)),
        )
        item_id = cursor.fetchone()[0]

    cursor.close()
    return item_id


def link_item_genres(connection, internal_item_id, tmdb_genre_ids):
    """
    For one item, maps each of TMDB's genre_ids to YOUR internal
    genres.id, then writes the (item_id, genre_id) pair into
    item_genres.

    WHY THE LOOKUP IS NEEDED: your genres.external_id column stores
    TMDB's genre numbers as TEXT (e.g. "28" for Action), but your
    item_genres table links to genres.id (your own AUTO_INCREMENT
    number), not TMDB's. So every genre_id coming from the API has to be
    translated first.
    """

    cursor = connection.cursor()

    for tmdb_genre_id in tmdb_genre_ids:
        cursor.execute(
            "SELECT id FROM genres WHERE media_type = 'movie' AND external_id = %s",
            (str(tmdb_genre_id),),
        )
        row = cursor.fetchone()

        if row is None:
            # This TMDB genre id doesn't exist in your genres table --
            # skip it rather than crash the whole harvest run over one
            # bad mapping.
            print(f"Warning: no matching genre row for TMDB id {tmdb_genre_id}")
            continue

        internal_genre_id = row[0]

        # INSERT IGNORE: if this exact (item_id, genre_id) pair already
        # exists (e.g. from a previous harvest run), silently skip it
        # instead of throwing a duplicate-key error.
        cursor.execute(
            "INSERT IGNORE INTO item_genres (item_id, genre_id) VALUES (%s, %s)",
            (internal_item_id, internal_genre_id),
        )

    connection.commit()
    cursor.close()


# Standard Python entry-point guard: only run main() if this file is
# executed directly (`python trending_harvester.py`), not if it's ever
# imported as a module from somewhere else.
if __name__ == "__main__":
    main()

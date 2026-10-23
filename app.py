import json
import os

import mysql.connector
from dotenv import load_dotenv
from flask import Flask, abort, request, send_from_directory
from flask_cors import CORS

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
load_dotenv(os.path.join(BASE_DIR, ".env"))

# Create the Flask backend application.
app = Flask(__name__)
CORS(app)

# Maximum number of recommendations returned per category.
MAX_ITEMS_PER_BUCKET = 5
ALLOWED_MOODS = {
    "Happy/Excitement",
    "Calm/Serene",
    "Sad/Melancholy",
    "Anger/Rage",
    "Confusion/Anxiety",
}


@app.route("/")
def home():
    """Confirm that the backend server is running, or serve frontend if opened in browser."""
    if "text/html" in request.headers.get("Accept", ""):
        frontend_dir = os.path.join(BASE_DIR, "frontend")
        return send_from_directory(frontend_dir, "index.html")
    return {
        "message": "State of Mind backend is running"
    }


@app.route("/frontend/<path:filename>")
def serve_frontend(filename):
    """Serve frontend static files and pages."""
    frontend_dir = os.path.join(BASE_DIR, "frontend")
    return send_from_directory(frontend_dir, filename)


@app.route("/app")
def serve_app():
    """Shortcut to view the frontend application."""
    frontend_dir = os.path.join(BASE_DIR, "frontend")
    return send_from_directory(frontend_dir, "index.html")


@app.route("/<path:filename>")
def serve_root_static(filename):
    """Serve static files requested from root (e.g. style.css, script.js, assets/...)."""
    frontend_dir = os.path.join(BASE_DIR, "frontend")
    target_path = os.path.join(frontend_dir, filename)
    if os.path.isfile(target_path):
        return send_from_directory(frontend_dir, filename)
    abort(404)


def generate_direct_link(media_type, external_id, metadata):
    """
    Generate a direct destination link, action label, and artist details.

    - Movies & TV: canonical page on The Movie Database (TMDB).
    - Music: direct song link on Deezer (with artist attribution).
    - Games: canonical game page on RAWG.
    """
    meta = {}
    if metadata:
        if isinstance(metadata, str):
            try:
                meta = json.loads(metadata)
            except Exception:
                meta = {}
        elif isinstance(metadata, dict):
            meta = metadata

    link = None
    action_label = "View"
    artist = None

    if media_type == "movie":
        action_label = "View"
        if external_id:
            link = f"https://www.themoviedb.org/movie/{external_id}"
    elif media_type == "tv":
        action_label = "View"
        if external_id:
            link = f"https://www.themoviedb.org/tv/{external_id}"
    elif media_type == "music":
        action_label = "Listen"
        link = meta.get("link")
        if not link and external_id:
            link = f"https://www.deezer.com/track/{external_id}"
        artist_data = meta.get("artist")
        if isinstance(artist_data, dict):
            artist = artist_data.get("name")
        elif isinstance(artist_data, str):
            artist = artist_data
    elif media_type == "game":
        action_label = "View"
        slug = meta.get("slug")
        if slug:
            link = f"https://rawg.io/games/{slug}"
        elif external_id:
            link = f"https://rawg.io/games/{external_id}"

    return link, action_label, artist


def remove_duplicates(rows):
    """
    Remove duplicate items produced by the SQL genre joins.

    One item can belong to several genres. Therefore, the SQL query can
    return the same item multiple times with different relevance scores.

    We use the unique database item ID as the dictionary key and preserve
    only the occurrence with the highest relevance score.
    """

    # Key: item ID
    # Value: the best version of that item
    unique_items = {}

    for row in rows:
        item_id = row[0]
        title = row[1]
        media_type = row[2]
        popularity = float(row[3])
        relevance = float(row[4])
        external_id = str(row[5]) if len(row) > 5 and row[5] is not None else ""
        metadata = row[6] if len(row) > 6 else None

        # Return None if this item has not previously been stored.
        existing_item = unique_items.get(item_id)

        # Store the item when:
        # 1. it has not been seen before, or
        # 2. this row has a better relevance score.
        if (
            existing_item is None
            or relevance > existing_item["relevance_score"]
        ):
            link, action_label, artist = generate_direct_link(media_type, external_id, metadata)
            unique_items[item_id] = {
                "id": item_id,
                "title": title,
                "media_type": media_type,
                "popularity_score": popularity,
                "relevance_score": relevance,
                "link": link,
                "action_label": action_label,
                "artist": artist,
            }

    # The API needs a list, not a dictionary indexed by ID.
    return list(unique_items.values())


def group_items_by_media(unique_items):
    """
    Split unique items into the three categories the frontend renders.

    Movies and TV share one bucket because the app shows them together.
    """

    # All three keys are created up front so the response shape stays
    # constant even when a category has no matches.
    grouped_items = {
        "movies_tv": [],
        "music": [],
        "games": [],
    }

    for item in unique_items:
        media_type = item["media_type"]

        if media_type == "movie" or media_type == "tv":
            grouped_items["movies_tv"].append(item)
        elif media_type == "music":
            grouped_items["music"].append(item)
        elif media_type == "game":
            grouped_items["games"].append(item)
        else:
            # Unknown future media types are skipped rather than being
            # forced into a bucket where they do not belong.
            continue

    return grouped_items


def cap_each_bucket(grouped_items, limit=MAX_ITEMS_PER_BUCKET):
    """
    Keep only the strongest `limit` recommendations in each category.

    The SQL query already orders rows by relevance and then popularity,
    and neither earlier step reorders them, so the first entries in each
    bucket are already the best ones.
    """

    capped_items = {}

    for bucket_name, items in grouped_items.items():
        # Slicing never raises when the bucket holds fewer than `limit`
        # items -- it simply returns everything available.
        capped_items[bucket_name] = items[:limit]

    return capped_items


@app.route("/get-state")
def get_state():
    """Return ranked, deduplicated, bucketed recommendations for a mood."""

    # Example URL:
    # /get-state?mood=Happy/Excitement
    mood = request.args.get("mood")
    if mood not in ALLOWED_MOODS:
        abort(404, description="Invalid mood")

    db_host = os.getenv("DB_HOST")
    db_port = os.getenv("DB_PORT")
    if not db_host or not db_port:
        abort(500, description="Database configuration missing. Please ensure .env contains DB_HOST and DB_PORT.")

    db_name = os.getenv("DB_NAME", "defaultdb")
    ssl_ca = os.getenv("DB_SSL_CA", "ignore/ca.pem")
    if ssl_ca and not os.path.isabs(ssl_ca):
        ssl_ca = os.path.join(BASE_DIR, ssl_ca)

    try:
        # Connect securely to the Aiven MySQL database.
        connection = mysql.connector.connect(
            host=db_host,
            port=int(db_port),
            user=os.getenv("DB_USER"),
            password=os.getenv("DB_PASSWORD"),
            database=db_name,
            ssl_ca=ssl_ca,
            ssl_verify_cert=False,
        )
    except Exception as err:
        print(f"\n[ERROR] Failed to connect to MySQL database: {err}\n")
        return {"error": f"Database connection error: {err}"}, 500

    cursor = connection.cursor()

    # Ensure we use the database containing the tables (defaultdb or state_of_mind)
    try:
        cursor.execute("SELECT 1 FROM moods LIMIT 1")
    except Exception:
        alt_db = "state_of_mind" if db_name == "defaultdb" else "defaultdb"
        try:
            cursor.execute(f"USE {alt_db}")
        except Exception:
            pass

    try:
        # items.id is selected first because remove_duplicates() expects
        # item_id to be the first value in each row.
        cursor.execute(
            """
            SELECT
                items.id,
                items.title,
                items.media_type,
                items.popularity_score,
                mood_genre_mapping.relevance_score,
                items.external_id,
                items.metadata
            FROM moods
            JOIN mood_genre_mapping
                ON moods.id = mood_genre_mapping.mood_id
            JOIN item_genres
                ON mood_genre_mapping.genre_id = item_genres.genre_id
            JOIN items
                ON item_genres.item_id = items.id
            WHERE moods.name = %s
            ORDER BY
                mood_genre_mapping.relevance_score DESC,
                items.popularity_score DESC
            """,
            (mood,),
        )

        # Collect every row returned by MySQL.
        rows = cursor.fetchall()

        # Remove repeated items and preserve their best relevance.
        unique_items = remove_duplicates(rows)
        grouped_items = group_items_by_media(unique_items)
        capped_items = cap_each_bucket(grouped_items)

        # Flask automatically converts this dictionary into JSON.
        return {
            "movies_tv": capped_items["movies_tv"],
            "music": capped_items["music"],
            "games": capped_items["games"],
        }

    except Exception as err:
        print(f"\n[ERROR] Database query error: {err}\n")
        return {"error": f"Database query error: {err}"}, 500

    finally:
        # Always release database resources.
        cursor.close()
        connection.close()



# Start Flask when executed directly.
if __name__ == "__main__":
    app.run(debug=True)
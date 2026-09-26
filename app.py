import os

import mysql.connector
from dotenv import load_dotenv
from flask import Flask, abort, request

# Read database settings from the .env file.
load_dotenv()

# Create the Flask backend application.
app = Flask(__name__)

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
    """Confirm that the backend server is running."""
    return {
        "message": "State of Mind backend is running"
    }


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

    for item_id, title, media_type, popularity, relevance in rows:
        # MySQL returns DECIMAL columns as Decimal objects.
        # Floats can be compared easily and converted into JSON.
        popularity = float(popularity)
        relevance = float(relevance)

        # Return None if this item has not previously been stored.
        existing_item = unique_items.get(item_id)

        # Store the item when:
        # 1. it has not been seen before, or
        # 2. this row has a better relevance score.
        if (
            existing_item is None
            or relevance > existing_item["relevance_score"]
        ):
            unique_items[item_id] = {
                "id": item_id,
                "title": title,
                "media_type": media_type,
                "popularity_score": popularity,
                "relevance_score": relevance,
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

    # Connect securely to the Aiven MySQL database.
    connection = mysql.connector.connect(
        host=os.getenv("DB_HOST"),
        port=int(os.getenv("DB_PORT")),
        user=os.getenv("DB_USER"),
        password=os.getenv("DB_PASSWORD"),
        database=os.getenv("DB_NAME"),
        ssl_ca=os.getenv("DB_SSL_CA"),
        ssl_verify_cert=True,
    )

    cursor = connection.cursor()

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
                mood_genre_mapping.relevance_score
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
            "mood": mood,
            "movies_tv": capped_items["movies_tv"],
            "music": capped_items["music"],
            "games": capped_items["games"],
        }

    finally:
        # Always release database resources.
        cursor.close()
        connection.close()


# Start Flask when executed directly.
if __name__ == "__main__":
    app.run(debug=True)
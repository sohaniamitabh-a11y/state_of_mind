"""
state_of_mind/server.py
-----------------------
Minimal Flask REST API for the State of Mind "My Journal" (Library)
and Custom Collections feature.

Persists user library entries and collections in MySQL, isolated by
anonymous browser identity (X-User-ID header).

Follows existing repository configuration conventions (from trending_harvester.py).

SECURITY NOTE
-------------
X-User-ID is NOT a secure authentication mechanism.  It is a best-effort
anonymous-browser isolation header.  Never use it for privileged operations
or assume it cannot be spoofed.
"""

import os
import json
from datetime import date, datetime
from flask import Flask, request, jsonify, make_response
import mysql.connector
from mysql.connector import errorcode

app = Flask(__name__)

# --- CONFIGURATION -----------------------------------------------------------
# Default configuration matches trending_harvester.py, with environment overrides.
DB_CONFIG = {
    "host": os.environ.get("DB_HOST", "localhost"),
    "port": int(os.environ.get("DB_PORT", 3306)),
    "user": os.environ.get("DB_USER", "root"),
    "password": os.environ.get("DB_PASSWORD", ""),  # default XAMPP/local password is blank
    "database": os.environ.get("DB_NAME", "state_of_mind"),
}

VALID_MEDIA_TYPES = {"movie", "tv", "music", "game"}
VALID_STATUSES = {"experienced", "wishlist"}

# Maximum length we accept for the X-User-ID header value.
MAX_USER_ID_LEN = 128


# --- DATABASE CONNECTION HELPER ----------------------------------------------
def get_db_connection():
    """Opens and returns a connection to MySQL."""
    return mysql.connector.connect(**DB_CONFIG)


# --- CORS HANDLING -----------------------------------------------------------
@app.after_request
def add_cors_headers(response):
    response.headers["Access-Control-Allow-Origin"] = "*"
    response.headers["Access-Control-Allow-Methods"] = "GET, POST, PUT, DELETE, OPTIONS"
    response.headers["Access-Control-Allow-Headers"] = "Content-Type, X-User-ID"
    return response


@app.route("/", defaults={"path": ""}, methods=["OPTIONS"])
@app.route("/<path:path>", methods=["OPTIONS"])
def handle_options(path):
    response = make_response()
    return response, 204


# --- HELPER FUNCTIONS --------------------------------------------------------
def get_request_user_id():
    """Returns the caller's anonymous identifier or ``None`` if absent.

    Reads from the ``X-User-ID`` request header first, then falls back to
    the ``user_id`` query parameter.  Returns ``None`` — never a shared
    fallback string — so callers can enforce presence explicitly.
    """
    uid = (request.headers.get("X-User-ID") or request.args.get("user_id") or "").strip()
    if not uid:
        return None
    if len(uid) > MAX_USER_ID_LEN:
        return None
    return uid


def require_user_id():
    """Validates and returns the ``X-User-ID`` for the current request.

    Returns a ``(response, status_code)`` tuple when validation fails so that
    view functions can do::

        uid = require_user_id()
        if isinstance(uid, tuple):
            return uid
    """
    uid = get_request_user_id()
    if not uid:
        return (
            jsonify({"error": "A valid X-User-ID header (1–128 characters) is required."}),
            400,
        )
    return uid


def format_row(row, cursor_description):
    """Converts a database tuple into a dictionary with serializable types."""
    columns = [col[0] for col in cursor_description]
    item = dict(zip(columns, row))

    for key, val in item.items():
        if isinstance(val, (date, datetime)):
            item[key] = val.isoformat()
        elif key == "is_favorite":
            item[key] = bool(val)
        elif key == "metadata" and isinstance(val, str):
            try:
                item[key] = json.loads(val)
            except Exception:
                pass
    return item


# --- HEALTH CHECK ------------------------------------------------------------
@app.route("/api/health", methods=["GET"])
def health():
    db_status = "connected"
    try:
        conn = get_db_connection()
        conn.close()
    except Exception as e:
        db_status = f"unavailable: {str(e)}"
    return jsonify({"status": "ok", "database": db_status})


# --- MOODS ENDPOINT ----------------------------------------------------------
@app.route("/api/moods", methods=["GET"])
def get_moods():
    """Returns the 5 core mood categories from the moods table.
    Public endpoint — no X-User-ID required.
    """
    conn = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        cursor.execute("SELECT id, name FROM moods ORDER BY id")
        rows = cursor.fetchall()
        cursor.close()
        return jsonify(rows)
    except mysql.connector.Error as err:
        return jsonify({"error": "Database error while fetching moods."}), 500
    finally:
        if conn and conn.is_connected():
            conn.close()


# --- LIBRARY ENTRIES (MY LIST / FAVORITES / HISTORY) -------------------------
@app.route("/api/library", methods=["GET"])
def list_library():
    """
    Returns library entries for the user.
    Supports filtering by status ('experienced', 'wishlist'), media_type,
    mood_id, is_favorite, collection_id, and keyword search.
    """
    uid = require_user_id()
    if isinstance(uid, tuple):
        return uid
    user_id = uid

    status_filter = request.args.get("status")
    media_filter = request.args.get("media_type")
    mood_filter = request.args.get("mood_id")
    fav_filter = request.args.get("is_favorite")
    collection_filter = request.args.get("collection_id")
    search_query = request.args.get("search", "").strip().lower()

    conn = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        query = """
            SELECT 
                j.id, j.user_id, j.item_id, j.title, j.media_type,
                j.mood_id, m.name AS mood_name, j.rating, j.date_experienced,
                j.notes, j.is_favorite, j.status, j.metadata,
                j.created_at, j.updated_at
            FROM user_journal j
            LEFT JOIN moods m ON j.mood_id = m.id
        """
        params = []
        conditions = ["j.user_id = %s"]
        params.append(user_id)

        if collection_filter:
            query += " INNER JOIN user_collection_items uci ON j.id = uci.journal_id"
            conditions.append("uci.collection_id = %s")
            params.append(collection_filter)

        if status_filter and status_filter in VALID_STATUSES:
            conditions.append("j.status = %s")
            params.append(status_filter)

        if media_filter and media_filter in VALID_MEDIA_TYPES:
            conditions.append("j.media_type = %s")
            params.append(media_filter)

        if mood_filter:
            conditions.append("j.mood_id = %s")
            params.append(mood_filter)

        if fav_filter is not None:
            is_fav_val = 1 if fav_filter.lower() in ("true", "1") else 0
            conditions.append("j.is_favorite = %s")
            params.append(is_fav_val)

        if search_query:
            conditions.append("(LOWER(j.title) LIKE %s OR LOWER(j.notes) LIKE %s)")
            params.extend([f"%{search_query}%", f"%{search_query}%"])

        query += " WHERE " + " AND ".join(conditions)
        query += " ORDER BY j.created_at DESC"

        cursor.execute(query, tuple(params))
        rows = cursor.fetchall()
        entries = [format_row(row, cursor.description) for row in rows]
        cursor.close()

        return jsonify(entries)
    except mysql.connector.Error as err:
        return jsonify({"error": "Database error while fetching library."}), 500
    finally:
        if conn and conn.is_connected():
            conn.close()


@app.route("/api/library", methods=["POST"])
def create_library_entry():
    """
    Creates a new journal / library entry.
    Compatible with saving from a recommendation card (by passing item_id)
    or manually logging an experience.
    """
    uid = require_user_id()
    if isinstance(uid, tuple):
        return uid
    user_id = uid

    data = request.get_json(silent=True) or {}

    title = (data.get("title") or "").strip()
    media_type = (data.get("media_type") or "").strip().lower()
    item_id = data.get("item_id")
    mood_id = data.get("mood_id")
    rating = data.get("rating")
    date_exp = data.get("date_experienced")
    notes = data.get("notes", "")
    is_favorite = 1 if data.get("is_favorite") else 0
    status = (data.get("status") or "experienced").strip().lower()
    metadata = data.get("metadata")

    if not title:
        return jsonify({"error": "Title is required."}), 400
    if media_type not in VALID_MEDIA_TYPES:
        return jsonify({"error": f"media_type must be one of {sorted(VALID_MEDIA_TYPES)}."}), 400
    if status not in VALID_STATUSES:
        status = "experienced"

    # Validate rating
    if rating is not None:
        try:
            rating = float(rating)
            if not (0 <= rating <= 5):
                return jsonify({"error": "rating must be between 0 and 5."}), 400
        except (ValueError, TypeError):
            return jsonify({"error": "rating must be a number."}), 400

    metadata_json = json.dumps(metadata) if isinstance(metadata, (dict, list)) else metadata

    conn = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        sql = """
            INSERT INTO user_journal (
                user_id, item_id, title, media_type, mood_id,
                rating, date_experienced, notes, is_favorite,
                status, metadata
            ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
        """
        cursor.execute(
            sql,
            (
                user_id,
                item_id,
                title,
                media_type,
                mood_id,
                rating,
                date_exp,
                notes,
                is_favorite,
                status,
                metadata_json,
            ),
        )
        conn.commit()
        new_id = cursor.lastrowid
        cursor.close()

        return jsonify({"success": True, "id": new_id, "message": "Entry created."}), 201
    except mysql.connector.Error as err:
        return jsonify({"error": "Database error while creating entry."}), 500
    finally:
        if conn and conn.is_connected():
            conn.close()


@app.route("/api/library/<int:entry_id>", methods=["GET"])
def get_library_entry(entry_id):
    """Retrieves a single entry by ID (scoped to requesting user)."""
    uid = require_user_id()
    if isinstance(uid, tuple):
        return uid
    user_id = uid

    conn = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT 
                j.id, j.user_id, j.item_id, j.title, j.media_type,
                j.mood_id, m.name AS mood_name, j.rating, j.date_experienced,
                j.notes, j.is_favorite, j.status, j.metadata,
                j.created_at, j.updated_at
            FROM user_journal j
            LEFT JOIN moods m ON j.mood_id = m.id
            WHERE j.id = %s AND j.user_id = %s
            """,
            (entry_id, user_id),
        )
        row = cursor.fetchone()
        if not row:
            cursor.close()
            return jsonify({"error": "Entry not found."}), 404

        item = format_row(row, cursor.description)
        cursor.close()
        return jsonify(item)
    except mysql.connector.Error as err:
        return jsonify({"error": "Database error while fetching entry."}), 500
    finally:
        if conn and conn.is_connected():
            conn.close()


@app.route("/api/library/<int:entry_id>", methods=["PUT"])
def update_library_entry(entry_id):
    """Updates fields on an existing entry (scoped to requesting user)."""
    uid = require_user_id()
    if isinstance(uid, tuple):
        return uid
    user_id = uid

    data = request.get_json(silent=True) or {}

    fields_to_update = []
    params = []

    if "title" in data and data["title"]:
        fields_to_update.append("title = %s")
        params.append(data["title"].strip())

    if "media_type" in data and data["media_type"] in VALID_MEDIA_TYPES:
        fields_to_update.append("media_type = %s")
        params.append(data["media_type"])

    if "mood_id" in data:
        fields_to_update.append("mood_id = %s")
        params.append(data["mood_id"])

    if "rating" in data:
        r = data["rating"]
        if r is not None:
            try:
                r = float(r)
                if not (0 <= r <= 5):
                    return jsonify({"error": "rating must be between 0 and 5."}), 400
            except (ValueError, TypeError):
                return jsonify({"error": "rating must be a number."}), 400
        fields_to_update.append("rating = %s")
        params.append(r)

    if "date_experienced" in data:
        fields_to_update.append("date_experienced = %s")
        params.append(data["date_experienced"])

    if "notes" in data:
        fields_to_update.append("notes = %s")
        params.append(data["notes"])

    if "is_favorite" in data:
        fields_to_update.append("is_favorite = %s")
        params.append(1 if data["is_favorite"] else 0)

    if "status" in data and data["status"] in VALID_STATUSES:
        fields_to_update.append("status = %s")
        params.append(data["status"])

    if "metadata" in data:
        fields_to_update.append("metadata = %s")
        params.append(
            json.dumps(data["metadata"])
            if isinstance(data["metadata"], (dict, list))
            else data["metadata"]
        )

    if not fields_to_update:
        return jsonify({"error": "No valid fields provided for update."}), 400

    params.extend([entry_id, user_id])

    conn = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        sql = f"UPDATE user_journal SET {', '.join(fields_to_update)} WHERE id = %s AND user_id = %s"
        cursor.execute(sql, tuple(params))
        conn.commit()
        affected = cursor.rowcount
        cursor.close()

        if affected == 0:
            return jsonify({"error": "Entry not found or unauthorized."}), 404

        return jsonify({"success": True, "message": "Entry updated."})
    except mysql.connector.Error as err:
        return jsonify({"error": "Database error while updating entry."}), 500
    finally:
        if conn and conn.is_connected():
            conn.close()


@app.route("/api/library/<int:entry_id>", methods=["DELETE"])
def delete_library_entry(entry_id):
    """Deletes an entry from user_journal (scoped to requesting user)."""
    uid = require_user_id()
    if isinstance(uid, tuple):
        return uid
    user_id = uid

    conn = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute(
            "DELETE FROM user_journal WHERE id = %s AND user_id = %s",
            (entry_id, user_id),
        )
        conn.commit()
        affected = cursor.rowcount
        cursor.close()

        if affected == 0:
            return jsonify({"error": "Entry not found or unauthorized."}), 404

        return jsonify({"success": True, "message": "Entry deleted."})
    except mysql.connector.Error as err:
        return jsonify({"error": "Database error while deleting entry."}), 500
    finally:
        if conn and conn.is_connected():
            conn.close()


@app.route("/api/library/<int:entry_id>/favorite", methods=["POST"])
def toggle_favorite(entry_id):
    """Toggles the favorite status of an entry (scoped to requesting user)."""
    uid = require_user_id()
    if isinstance(uid, tuple):
        return uid
    user_id = uid

    conn = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute(
            "UPDATE user_journal SET is_favorite = NOT is_favorite WHERE id = %s AND user_id = %s",
            (entry_id, user_id),
        )
        conn.commit()
        affected = cursor.rowcount
        cursor.close()

        if affected == 0:
            return jsonify({"error": "Entry not found or unauthorized."}), 404

        return jsonify({"success": True, "message": "Favorite toggled."})
    except mysql.connector.Error as err:
        return jsonify({"error": "Database error while toggling favorite."}), 500
    finally:
        if conn and conn.is_connected():
            conn.close()


@app.route("/api/library/<int:entry_id>/status", methods=["POST"])
def toggle_status(entry_id):
    """Toggles status between wishlist and experienced (scoped to requesting user)."""
    uid = require_user_id()
    if isinstance(uid, tuple):
        return uid
    user_id = uid

    conn = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute(
            """
            UPDATE user_journal 
            SET status = CASE WHEN status = 'wishlist' THEN 'experienced' ELSE 'wishlist' END,
                date_experienced = CASE WHEN status = 'wishlist' AND date_experienced IS NULL THEN CURRENT_DATE ELSE date_experienced END
            WHERE id = %s AND user_id = %s
            """,
            (entry_id, user_id),
        )
        conn.commit()
        affected = cursor.rowcount
        cursor.close()

        if affected == 0:
            return jsonify({"error": "Entry not found or unauthorized."}), 404

        return jsonify({"success": True, "message": "Status toggled."})
    except mysql.connector.Error as err:
        return jsonify({"error": "Database error while toggling status."}), 500
    finally:
        if conn and conn.is_connected():
            conn.close()


# --- CUSTOM COLLECTIONS ENDPOINTS --------------------------------------------
@app.route("/api/collections", methods=["GET"])
def list_collections():
    """Returns all custom collections for the user with member entry IDs."""
    uid = require_user_id()
    if isinstance(uid, tuple):
        return uid
    user_id = uid

    conn = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        # Fetch collections
        cursor.execute(
            """
            SELECT id, user_id, name, description, created_at, updated_at
            FROM user_collections
            WHERE user_id = %s
            ORDER BY name ASC
            """,
            (user_id,),
        )
        collections = [format_row(row, cursor.description) for row in cursor.fetchall()]

        # Attach item IDs for each collection
        for col in collections:
            cursor.execute(
                "SELECT journal_id FROM user_collection_items WHERE collection_id = %s",
                (col["id"],),
            )
            col["item_ids"] = [r[0] for r in cursor.fetchall()]

        cursor.close()
        return jsonify(collections)
    except mysql.connector.Error as err:
        return jsonify({"error": "Database error while fetching collections."}), 500
    finally:
        if conn and conn.is_connected():
            conn.close()


@app.route("/api/collections", methods=["POST"])
def create_collection():
    """Creates a new custom collection."""
    uid = require_user_id()
    if isinstance(uid, tuple):
        return uid
    user_id = uid

    data = request.get_json(silent=True) or {}
    name = (data.get("name") or "").strip()
    description = (data.get("description") or "").strip()

    if not name:
        return jsonify({"error": "Collection name is required."}), 400

    conn = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute(
            "INSERT INTO user_collections (user_id, name, description) VALUES (%s, %s, %s)",
            (user_id, name, description),
        )
        conn.commit()
        new_id = cursor.lastrowid
        cursor.close()
        return jsonify({"success": True, "id": new_id, "name": name}), 201
    except mysql.connector.Error as err:
        if err.errno == errorcode.ER_DUP_ENTRY:
            return jsonify({"error": f"A collection named '{name}' already exists."}), 409
        return jsonify({"error": "Database error while creating collection."}), 500
    finally:
        if conn and conn.is_connected():
            conn.close()


@app.route("/api/collections/<int:collection_id>", methods=["PUT"])
def update_collection(collection_id):
    """Updates collection name or description (scoped to requesting user)."""
    uid = require_user_id()
    if isinstance(uid, tuple):
        return uid
    user_id = uid

    data = request.get_json(silent=True) or {}
    name = (data.get("name") or "").strip()
    description = data.get("description")

    if not name:
        return jsonify({"error": "Collection name is required."}), 400

    conn = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute(
            "UPDATE user_collections SET name = %s, description = %s WHERE id = %s AND user_id = %s",
            (name, description, collection_id, user_id),
        )
        conn.commit()
        affected = cursor.rowcount
        cursor.close()

        if affected == 0:
            return jsonify({"error": "Collection not found or unauthorized."}), 404

        return jsonify({"success": True, "message": "Collection updated."})
    except mysql.connector.Error as err:
        if err.errno == errorcode.ER_DUP_ENTRY:
            return jsonify({"error": f"A collection named '{name}' already exists."}), 409
        return jsonify({"error": "Database error while updating collection."}), 500
    finally:
        if conn and conn.is_connected():
            conn.close()


@app.route("/api/collections/<int:collection_id>", methods=["DELETE"])
def delete_collection(collection_id):
    """Deletes a collection (does NOT delete member journal entries)."""
    uid = require_user_id()
    if isinstance(uid, tuple):
        return uid
    user_id = uid

    conn = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute(
            "DELETE FROM user_collections WHERE id = %s AND user_id = %s",
            (collection_id, user_id),
        )
        conn.commit()
        affected = cursor.rowcount
        cursor.close()

        if affected == 0:
            return jsonify({"error": "Collection not found or unauthorized."}), 404

        return jsonify({"success": True, "message": "Collection deleted."})
    except mysql.connector.Error as err:
        return jsonify({"error": "Database error while deleting collection."}), 500
    finally:
        if conn and conn.is_connected():
            conn.close()


@app.route("/api/collections/<int:collection_id>/items", methods=["POST"])
def add_item_to_collection(collection_id):
    """Adds a journal entry to a collection.

    Security: verifies that BOTH the collection and the journal entry belong
    to the requesting ``X-User-ID`` before modifying membership.
    Returns 403 if either resource belongs to a different user.
    """
    uid = require_user_id()
    if isinstance(uid, tuple):
        return uid
    user_id = uid

    data = request.get_json(silent=True) or {}
    journal_id = data.get("journal_id")

    if not journal_id:
        return jsonify({"error": "journal_id is required."}), 400

    conn = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        # Verify collection ownership
        cursor.execute(
            "SELECT user_id FROM user_collections WHERE id = %s",
            (collection_id,),
        )
        col_row = cursor.fetchone()
        if not col_row:
            return jsonify({"error": "Collection not found or unauthorized."}), 403
        if col_row[0] != user_id:
            return jsonify({"error": "Collection not found or unauthorized."}), 403

        # Verify journal entry ownership
        cursor.execute(
            "SELECT user_id FROM user_journal WHERE id = %s",
            (journal_id,),
        )
        entry_row = cursor.fetchone()
        if not entry_row:
            return jsonify({"error": "Journal entry not found or unauthorized."}), 403
        if entry_row[0] != user_id:
            return jsonify({"error": "Journal entry not found or unauthorized."}), 403

        # INSERT IGNORE avoids errors if item is already in collection
        cursor.execute(
            "INSERT IGNORE INTO user_collection_items (collection_id, journal_id) VALUES (%s, %s)",
            (collection_id, journal_id),
        )
        conn.commit()
        cursor.close()
        return jsonify({"success": True, "message": "Item added to collection."})
    except mysql.connector.Error as err:
        return jsonify({"error": "Database error while adding item to collection."}), 500
    finally:
        if conn and conn.is_connected():
            conn.close()


@app.route("/api/collections/<int:collection_id>/items/<int:journal_id>", methods=["DELETE"])
def remove_item_from_collection(collection_id, journal_id):
    """Removes a journal entry from a collection.

    Security: verifies that BOTH the collection and the journal entry belong
    to the requesting ``X-User-ID``.  Returns 403 on any mismatch.
    """
    uid = require_user_id()
    if isinstance(uid, tuple):
        return uid
    user_id = uid

    conn = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        # Verify collection ownership
        cursor.execute(
            "SELECT user_id FROM user_collections WHERE id = %s",
            (collection_id,),
        )
        col_row = cursor.fetchone()
        if not col_row:
            return jsonify({"error": "Collection not found or unauthorized."}), 403
        if col_row[0] != user_id:
            return jsonify({"error": "Collection not found or unauthorized."}), 403

        # Verify journal entry ownership
        cursor.execute(
            "SELECT user_id FROM user_journal WHERE id = %s",
            (journal_id,),
        )
        entry_row = cursor.fetchone()
        if not entry_row:
            return jsonify({"error": "Journal entry not found or unauthorized."}), 403
        if entry_row[0] != user_id:
            return jsonify({"error": "Journal entry not found or unauthorized."}), 403

        cursor.execute(
            "DELETE FROM user_collection_items WHERE collection_id = %s AND journal_id = %s",
            (collection_id, journal_id),
        )
        conn.commit()
        cursor.close()
        return jsonify({"success": True, "message": "Item removed from collection."})
    except mysql.connector.Error as err:
        return jsonify({"error": "Database error while removing item from collection."}), 500
    finally:
        if conn and conn.is_connected():
            conn.close()


# --- ENTRYPOINT --------------------------------------------------------------
if __name__ == "__main__":
    port = int(os.environ.get("PORT", 5001))
    print(f"State of Mind API running on http://127.0.0.1:{port}")
    app.run(host="0.0.0.0", port=port, debug=False)

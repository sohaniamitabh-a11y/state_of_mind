"""
tests/test_server.py
--------------------
Unit tests for the Flask REST API in state_of_mind/server.py.
Verifies routes, validation, user isolation, collection-membership security,
and correct HTTP status codes using Flask's built-in test client and mocked
MySQL connections.

NOTE: All tests use mock DB connections; a real MySQL instance is NOT required
to run the test suite.  Real-database integration must be verified manually
(see journal/JOURNAL_GUIDE.md).
"""

import unittest
from unittest.mock import MagicMock, patch, call
import json
import sys
import os

# Add repository root and state_of_mind directories to sys.path so "from server import app" works.
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "state_of_mind")))

from server import app


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _make_cursor(rows=None, description=None, rowcount=1, lastrowid=None):
    """Returns a MagicMock cursor pre-configured with the supplied data."""
    cursor = MagicMock()
    cursor.fetchall.return_value = rows or []
    cursor.fetchone.return_value = rows[0] if rows else None
    cursor.description = description or []
    cursor.rowcount = rowcount
    if lastrowid is not None:
        cursor.lastrowid = lastrowid
    return cursor


def _make_conn(cursor):
    conn = MagicMock()
    conn.is_connected.return_value = True
    conn.cursor.return_value = cursor
    return conn


# Standard library entry column descriptions used across multiple tests
LIBRARY_DESCRIPTION = [
    ("id",), ("user_id",), ("item_id",), ("title",), ("media_type",),
    ("mood_id",), ("mood_name",), ("rating",), ("date_experienced",),
    ("notes",), ("is_favorite",), ("status",), ("metadata",),
    ("created_at",), ("updated_at",)
]

LIBRARY_ROW = (
    1, "user_a", None, "Spirited Away", "movie",
    2, "Calm/Serene", 5.0, None, "Peaceful", 1, "experienced",
    None, None, None
)

COLLECTION_DESCRIPTION = [
    ("id",), ("user_id",), ("name",), ("description",),
    ("created_at",), ("updated_at",)
]

COLLECTION_ROW = (10, "user_a", "Weekend Chill", "Relaxing media", None, None)


# ===========================================================================
class TestHealthAndPublicEndpoints(unittest.TestCase):
    def setUp(self):
        self.client = app.test_client()
        app.testing = True

    # ------------------------------------------------------------------
    @patch("server.get_db_connection")
    def test_health_db_connected(self, mock_get_conn):
        mock_get_conn.return_value = MagicMock()
        resp = self.client.get("/api/health")
        self.assertEqual(resp.status_code, 200)
        data = resp.get_json()
        self.assertEqual(data["status"], "ok")
        self.assertEqual(data["database"], "connected")

    @patch("server.get_db_connection")
    def test_health_db_unavailable(self, mock_get_conn):
        mock_get_conn.side_effect = Exception("connection refused")
        resp = self.client.get("/api/health")
        self.assertEqual(resp.status_code, 200)
        data = resp.get_json()
        self.assertEqual(data["status"], "ok")
        self.assertIn("unavailable", data["database"])

    @patch("server.get_db_connection")
    def test_get_moods_no_auth_required(self, mock_get_conn):
        """GET /api/moods is public — no X-User-ID should be needed."""
        cursor = MagicMock()
        cursor.fetchall.return_value = [
            {"id": 1, "name": "Happy/Excitement"},
            {"id": 2, "name": "Calm/Serene"},
        ]
        conn = _make_conn(cursor)
        mock_get_conn.return_value = conn

        resp = self.client.get("/api/moods")
        self.assertEqual(resp.status_code, 200)
        data = resp.get_json()
        self.assertEqual(len(data), 2)
        self.assertEqual(data[0]["name"], "Happy/Excitement")


# ===========================================================================
class TestRequireUserID(unittest.TestCase):
    """Every personal endpoint must reject requests missing X-User-ID."""

    def setUp(self):
        self.client = app.test_client()
        app.testing = True

    def _assert_requires_user_id(self, method, path, json_body=None):
        fn = getattr(self.client, method)
        kwargs = {}
        if json_body is not None:
            kwargs["json"] = json_body
        resp = fn(path, **kwargs)
        self.assertEqual(
            resp.status_code, 400,
            f"{method.upper()} {path} should return 400 without X-User-ID, got {resp.status_code}"
        )
        self.assertIn("X-User-ID", resp.get_json().get("error", ""))

    def test_list_library_no_uid(self):
        self._assert_requires_user_id("get", "/api/library")

    def test_create_library_no_uid(self):
        self._assert_requires_user_id("post", "/api/library", {"title": "x", "media_type": "movie"})

    def test_get_entry_no_uid(self):
        self._assert_requires_user_id("get", "/api/library/1")

    def test_update_entry_no_uid(self):
        self._assert_requires_user_id("put", "/api/library/1", {"title": "x"})

    def test_delete_entry_no_uid(self):
        self._assert_requires_user_id("delete", "/api/library/1")

    def test_toggle_favorite_no_uid(self):
        self._assert_requires_user_id("post", "/api/library/1/favorite")

    def test_toggle_status_no_uid(self):
        self._assert_requires_user_id("post", "/api/library/1/status")

    def test_list_collections_no_uid(self):
        self._assert_requires_user_id("get", "/api/collections")

    def test_create_collection_no_uid(self):
        self._assert_requires_user_id("post", "/api/collections", {"name": "My List"})

    def test_update_collection_no_uid(self):
        self._assert_requires_user_id("put", "/api/collections/1", {"name": "My List"})

    def test_delete_collection_no_uid(self):
        self._assert_requires_user_id("delete", "/api/collections/1")

    def test_add_item_to_collection_no_uid(self):
        self._assert_requires_user_id("post", "/api/collections/1/items", {"journal_id": 1})

    def test_remove_item_from_collection_no_uid(self):
        self._assert_requires_user_id("delete", "/api/collections/1/items/1")


# ===========================================================================
class TestLibraryCRUD(unittest.TestCase):
    def setUp(self):
        self.client = app.test_client()
        app.testing = True
        self.headers = {"X-User-ID": "user_a"}

    @patch("server.get_db_connection")
    def test_create_entry_success(self, mock_get_conn):
        cursor = _make_cursor(lastrowid=101)
        mock_get_conn.return_value = _make_conn(cursor)

        resp = self.client.post(
            "/api/library",
            headers=self.headers,
            json={
                "title": "Spirited Away",
                "media_type": "movie",
                "rating": 5,
                "status": "experienced",
                "notes": "Beautiful",
                "is_favorite": True,
            },
        )
        self.assertEqual(resp.status_code, 201)
        data = resp.get_json()
        self.assertTrue(data["success"])
        self.assertEqual(data["id"], 101)

    def test_create_entry_missing_title(self):
        resp = self.client.post(
            "/api/library",
            headers=self.headers,
            json={"media_type": "movie"},
        )
        self.assertEqual(resp.status_code, 400)
        self.assertIn("Title", resp.get_json()["error"])

    def test_create_entry_invalid_media_type(self):
        resp = self.client.post(
            "/api/library",
            headers=self.headers,
            json={"title": "X", "media_type": "podcast"},
        )
        self.assertEqual(resp.status_code, 400)
        self.assertIn("media_type", resp.get_json()["error"])

    def test_create_entry_invalid_rating(self):
        resp = self.client.post(
            "/api/library",
            headers=self.headers,
            json={"title": "X", "media_type": "movie", "rating": 99},
        )
        self.assertEqual(resp.status_code, 400)
        self.assertIn("rating", resp.get_json()["error"])

    @patch("server.get_db_connection")
    def test_list_library_returns_entries(self, mock_get_conn):
        cursor = _make_cursor(rows=[LIBRARY_ROW], description=LIBRARY_DESCRIPTION)
        mock_get_conn.return_value = _make_conn(cursor)

        resp = self.client.get("/api/library", headers=self.headers)
        self.assertEqual(resp.status_code, 200)
        data = resp.get_json()
        self.assertEqual(len(data), 1)
        self.assertEqual(data[0]["title"], "Spirited Away")
        self.assertTrue(data[0]["is_favorite"])

    @patch("server.get_db_connection")
    def test_get_single_entry_success(self, mock_get_conn):
        cursor = _make_cursor(rows=[LIBRARY_ROW], description=LIBRARY_DESCRIPTION)
        mock_get_conn.return_value = _make_conn(cursor)

        resp = self.client.get("/api/library/1", headers=self.headers)
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.get_json()["title"], "Spirited Away")

    @patch("server.get_db_connection")
    def test_get_single_entry_not_found(self, mock_get_conn):
        cursor = _make_cursor(rows=[])
        mock_get_conn.return_value = _make_conn(cursor)

        resp = self.client.get("/api/library/999", headers=self.headers)
        self.assertEqual(resp.status_code, 404)

    @patch("server.get_db_connection")
    def test_update_entry_success(self, mock_get_conn):
        cursor = _make_cursor(rowcount=1)
        mock_get_conn.return_value = _make_conn(cursor)

        resp = self.client.put(
            "/api/library/1",
            headers=self.headers,
            json={"notes": "Updated notes"},
        )
        self.assertEqual(resp.status_code, 200)
        self.assertTrue(resp.get_json()["success"])

    @patch("server.get_db_connection")
    def test_update_entry_not_owned(self, mock_get_conn):
        cursor = _make_cursor(rowcount=0)
        mock_get_conn.return_value = _make_conn(cursor)

        resp = self.client.put(
            "/api/library/1",
            headers=self.headers,
            json={"notes": "Hack"},
        )
        self.assertEqual(resp.status_code, 404)

    def test_update_entry_no_valid_fields(self):
        resp = self.client.put(
            "/api/library/1",
            headers=self.headers,
            json={"garbage_field": "xyz"},
        )
        self.assertEqual(resp.status_code, 400)

    @patch("server.get_db_connection")
    def test_delete_entry_success(self, mock_get_conn):
        cursor = _make_cursor(rowcount=1)
        mock_get_conn.return_value = _make_conn(cursor)

        resp = self.client.delete("/api/library/1", headers=self.headers)
        self.assertEqual(resp.status_code, 200)
        self.assertTrue(resp.get_json()["success"])

    @patch("server.get_db_connection")
    def test_delete_entry_not_owned(self, mock_get_conn):
        cursor = _make_cursor(rowcount=0)
        mock_get_conn.return_value = _make_conn(cursor)

        resp = self.client.delete("/api/library/1", headers=self.headers)
        self.assertEqual(resp.status_code, 404)


# ===========================================================================
class TestFavoriteAndStatus(unittest.TestCase):
    def setUp(self):
        self.client = app.test_client()
        app.testing = True
        self.headers = {"X-User-ID": "user_a"}

    @patch("server.get_db_connection")
    def test_toggle_favorite_success(self, mock_get_conn):
        cursor = _make_cursor(rowcount=1)
        mock_get_conn.return_value = _make_conn(cursor)

        resp = self.client.post("/api/library/1/favorite", headers=self.headers)
        self.assertEqual(resp.status_code, 200)
        self.assertTrue(resp.get_json()["success"])

    @patch("server.get_db_connection")
    def test_toggle_favorite_not_owned(self, mock_get_conn):
        cursor = _make_cursor(rowcount=0)
        mock_get_conn.return_value = _make_conn(cursor)

        resp = self.client.post("/api/library/1/favorite", headers=self.headers)
        self.assertEqual(resp.status_code, 404)

    @patch("server.get_db_connection")
    def test_toggle_status_success(self, mock_get_conn):
        cursor = _make_cursor(rowcount=1)
        mock_get_conn.return_value = _make_conn(cursor)

        resp = self.client.post("/api/library/1/status", headers=self.headers)
        self.assertEqual(resp.status_code, 200)
        self.assertTrue(resp.get_json()["success"])

    @patch("server.get_db_connection")
    def test_toggle_status_not_owned(self, mock_get_conn):
        cursor = _make_cursor(rowcount=0)
        mock_get_conn.return_value = _make_conn(cursor)

        resp = self.client.post("/api/library/1/status", headers=self.headers)
        self.assertEqual(resp.status_code, 404)


# ===========================================================================
class TestCollectionCRUD(unittest.TestCase):
    def setUp(self):
        self.client = app.test_client()
        app.testing = True
        self.headers = {"X-User-ID": "user_a"}

    @patch("server.get_db_connection")
    def test_create_collection_success(self, mock_get_conn):
        cursor = _make_cursor(lastrowid=10)
        mock_get_conn.return_value = _make_conn(cursor)

        resp = self.client.post(
            "/api/collections",
            headers=self.headers,
            json={"name": "Weekend Chill", "description": "Relaxing media"},
        )
        self.assertEqual(resp.status_code, 201)
        data = resp.get_json()
        self.assertEqual(data["id"], 10)
        self.assertEqual(data["name"], "Weekend Chill")

    def test_create_collection_missing_name(self):
        resp = self.client.post(
            "/api/collections",
            headers=self.headers,
            json={"description": "No name"},
        )
        self.assertEqual(resp.status_code, 400)
        self.assertIn("name", resp.get_json()["error"])

    @patch("server.get_db_connection")
    def test_list_collections(self, mock_get_conn):
        # fetchall called twice: first for collections, then for item_ids
        cursor = MagicMock()
        cursor.is_connected = MagicMock(return_value=True)
        cursor.description = COLLECTION_DESCRIPTION
        cursor.fetchall.side_effect = [
            [COLLECTION_ROW],  # collections list
            [(1,), (2,)],      # item_ids for collection 10
        ]
        conn = _make_conn(cursor)
        mock_get_conn.return_value = conn

        resp = self.client.get("/api/collections", headers=self.headers)
        self.assertEqual(resp.status_code, 200)
        data = resp.get_json()
        self.assertEqual(len(data), 1)
        self.assertEqual(data[0]["name"], "Weekend Chill")
        self.assertEqual(data[0]["item_ids"], [1, 2])

    @patch("server.get_db_connection")
    def test_update_collection_success(self, mock_get_conn):
        cursor = _make_cursor(rowcount=1)
        mock_get_conn.return_value = _make_conn(cursor)

        resp = self.client.put(
            "/api/collections/10",
            headers=self.headers,
            json={"name": "Updated Name"},
        )
        self.assertEqual(resp.status_code, 200)
        self.assertTrue(resp.get_json()["success"])

    @patch("server.get_db_connection")
    def test_update_collection_not_owned(self, mock_get_conn):
        cursor = _make_cursor(rowcount=0)
        mock_get_conn.return_value = _make_conn(cursor)

        resp = self.client.put(
            "/api/collections/10",
            headers=self.headers,
            json={"name": "Hijack"},
        )
        self.assertEqual(resp.status_code, 404)

    @patch("server.get_db_connection")
    def test_delete_collection_success(self, mock_get_conn):
        cursor = _make_cursor(rowcount=1)
        mock_get_conn.return_value = _make_conn(cursor)

        resp = self.client.delete("/api/collections/10", headers=self.headers)
        self.assertEqual(resp.status_code, 200)
        self.assertTrue(resp.get_json()["success"])

    @patch("server.get_db_connection")
    def test_delete_collection_not_owned(self, mock_get_conn):
        cursor = _make_cursor(rowcount=0)
        mock_get_conn.return_value = _make_conn(cursor)

        resp = self.client.delete("/api/collections/10", headers=self.headers)
        self.assertEqual(resp.status_code, 404)


# ===========================================================================
class TestCollectionItemSecurity(unittest.TestCase):
    """
    Regression tests proving that cross-user access to collection items
    is rejected before any mutation occurs.
    """

    def setUp(self):
        self.client = app.test_client()
        app.testing = True

    # ------------------------------------------------------------------
    # Helper: build a cursor whose fetchone returns different rows on
    # successive calls (first for collection ownership, second for entry).
    # ------------------------------------------------------------------
    def _mock_sequential(self, col_owner, entry_owner):
        """
        Returns a mock cursor whose fetchone() yields:
          1st call → (col_owner,)  [collection user_id]
          2nd call → (entry_owner,)  [journal user_id]
        """
        cursor = MagicMock()
        cursor.fetchone.side_effect = [(col_owner,), (entry_owner,)]
        cursor.rowcount = 1
        return cursor

    # ------------------------------------------------------------------
    # ADD ITEM
    # ------------------------------------------------------------------
    @patch("server.get_db_connection")
    def test_add_item_success_same_user(self, mock_get_conn):
        cursor = self._mock_sequential("user_a", "user_a")
        mock_get_conn.return_value = _make_conn(cursor)

        resp = self.client.post(
            "/api/collections/10/items",
            headers={"X-User-ID": "user_a"},
            json={"journal_id": 1},
        )
        self.assertEqual(resp.status_code, 200)
        self.assertTrue(resp.get_json()["success"])

    @patch("server.get_db_connection")
    def test_add_item_collection_belongs_to_other_user(self, mock_get_conn):
        """Collection owned by user_b; requester is user_a → 403."""
        cursor = self._mock_sequential("user_b", "user_a")
        mock_get_conn.return_value = _make_conn(cursor)

        resp = self.client.post(
            "/api/collections/10/items",
            headers={"X-User-ID": "user_a"},
            json={"journal_id": 1},
        )
        self.assertEqual(resp.status_code, 403)
        self.assertIn("unauthorized", resp.get_json()["error"].lower())

    @patch("server.get_db_connection")
    def test_add_item_entry_belongs_to_other_user(self, mock_get_conn):
        """Collection is mine, but the journal entry belongs to user_b → 403."""
        cursor = self._mock_sequential("user_a", "user_b")
        mock_get_conn.return_value = _make_conn(cursor)

        resp = self.client.post(
            "/api/collections/10/items",
            headers={"X-User-ID": "user_a"},
            json={"journal_id": 99},
        )
        self.assertEqual(resp.status_code, 403)
        self.assertIn("unauthorized", resp.get_json()["error"].lower())

    @patch("server.get_db_connection")
    def test_add_item_collection_not_found(self, mock_get_conn):
        """Collection ID doesn't exist at all → 403."""
        cursor = MagicMock()
        cursor.fetchone.return_value = None
        mock_get_conn.return_value = _make_conn(cursor)

        resp = self.client.post(
            "/api/collections/999/items",
            headers={"X-User-ID": "user_a"},
            json={"journal_id": 1},
        )
        self.assertEqual(resp.status_code, 403)

    def test_add_item_missing_journal_id(self):
        resp = self.client.post(
            "/api/collections/10/items",
            headers={"X-User-ID": "user_a"},
            json={},
        )
        self.assertEqual(resp.status_code, 400)
        self.assertIn("journal_id", resp.get_json()["error"])

    # ------------------------------------------------------------------
    # REMOVE ITEM
    # ------------------------------------------------------------------
    @patch("server.get_db_connection")
    def test_remove_item_success_same_user(self, mock_get_conn):
        cursor = self._mock_sequential("user_a", "user_a")
        mock_get_conn.return_value = _make_conn(cursor)

        resp = self.client.delete(
            "/api/collections/10/items/1",
            headers={"X-User-ID": "user_a"},
        )
        self.assertEqual(resp.status_code, 200)
        self.assertTrue(resp.get_json()["success"])

    @patch("server.get_db_connection")
    def test_remove_item_collection_belongs_to_other_user(self, mock_get_conn):
        """Collection owned by user_b → requester user_a gets 403."""
        cursor = self._mock_sequential("user_b", "user_a")
        mock_get_conn.return_value = _make_conn(cursor)

        resp = self.client.delete(
            "/api/collections/10/items/1",
            headers={"X-User-ID": "user_a"},
        )
        self.assertEqual(resp.status_code, 403)

    @patch("server.get_db_connection")
    def test_remove_item_entry_belongs_to_other_user(self, mock_get_conn):
        """Collection is mine, journal entry belongs to user_b → 403."""
        cursor = self._mock_sequential("user_a", "user_b")
        mock_get_conn.return_value = _make_conn(cursor)

        resp = self.client.delete(
            "/api/collections/10/items/99",
            headers={"X-User-ID": "user_a"},
        )
        self.assertEqual(resp.status_code, 403)

    @patch("server.get_db_connection")
    def test_remove_item_collection_not_found(self, mock_get_conn):
        cursor = MagicMock()
        cursor.fetchone.return_value = None
        mock_get_conn.return_value = _make_conn(cursor)

        resp = self.client.delete(
            "/api/collections/999/items/1",
            headers={"X-User-ID": "user_a"},
        )
        self.assertEqual(resp.status_code, 403)


# ===========================================================================
class TestUserIsolation(unittest.TestCase):
    """Verifies that one user cannot read or mutate another user's data."""

    def setUp(self):
        self.client = app.test_client()
        app.testing = True

    @patch("server.get_db_connection")
    def test_user_b_cannot_see_user_a_entries(self, mock_get_conn):
        """user_b sends correct header but DB returns empty set (isolation enforced at DB layer)."""
        cursor = _make_cursor(rows=[], description=LIBRARY_DESCRIPTION)
        mock_get_conn.return_value = _make_conn(cursor)

        resp = self.client.get("/api/library", headers={"X-User-ID": "user_b"})
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.get_json(), [])

    @patch("server.get_db_connection")
    def test_user_b_update_user_a_entry_returns_404(self, mock_get_conn):
        """rowcount=0 means the WHERE user_id=%s clause protected user_a's entry."""
        cursor = _make_cursor(rowcount=0)
        mock_get_conn.return_value = _make_conn(cursor)

        resp = self.client.put(
            "/api/library/1",
            headers={"X-User-ID": "user_b"},
            json={"notes": "Hacked"},
        )
        self.assertEqual(resp.status_code, 404)

    @patch("server.get_db_connection")
    def test_user_b_delete_user_a_entry_returns_404(self, mock_get_conn):
        cursor = _make_cursor(rowcount=0)
        mock_get_conn.return_value = _make_conn(cursor)

        resp = self.client.delete(
            "/api/library/1",
            headers={"X-User-ID": "user_b"},
        )
        self.assertEqual(resp.status_code, 404)


# ===========================================================================
if __name__ == "__main__":
    unittest.main()

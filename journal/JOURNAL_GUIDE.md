# State of Mind — My Journal: Developer Guide

Personal entertainment journal feature for State of Mind: a mood-based
recommendation engine for movies, TV shows, music, and games.

---

## Table of Contents

1. [Overview](#overview)
2. [Project Structure](#project-structure)
3. [Database Setup](#database-setup)
4. [Backend Startup](#backend-startup)
5. [Environment Variables](#environment-variables)
6. [Frontend Access](#frontend-access)
7. [User Identity (X-User-ID)](#user-identity)
8. [LocalStorage Migration](#localstorage-migration)
9. [API Reference](#api-reference)
10. [Running Tests](#running-tests)
11. [Security Notes](#security-notes)
12. [Troubleshooting](#troubleshooting)

---

## Overview

The journal feature lets users:

- Record movies, shows, music, and games they have experienced.
- Add personal notes, ratings (0–5), dates, and moods.
- Mark items as favourites.
- Maintain a wishlist of things they want to explore later.
- Search and filter their collection.
- Organise entries into custom named collections.
- Review their entertainment history.

Data is persisted in MySQL via a Flask REST API and falls back to browser
`localStorage` when the backend is unreachable.

---

## Project Structure

```
├── server.py                  # Flask REST API (port 5001)
├── schema.sql                 # Core tables (moods, items, …)
├── journal_schema.sql         # Journal extension tables
│
journal/
├── journal.js                 # JS data layer + API client (edit this)
├── index.html                 # Journal UI entry point
├── style.css                  # UI styles
├── test_runner.html           # In-browser test suite
├── JOURNAL_GUIDE.md           # This file
│
tests/
└── test_server.py             # Python backend test suite (51 tests)
```

---

## Database Setup

> **Prerequisite:** MySQL 5.7 or 8.x running locally (XAMPP, Homebrew, or
> native install).  The database name defaults to `state_of_mind`.

### 1. Create the database (once)

```sql
CREATE DATABASE IF NOT EXISTS state_of_mind CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
```

### 2. Apply core schema

```bash
mysql -u root -p state_of_mind < schema.sql
```

### 3. Apply journal extension schema

```bash
mysql -u root -p state_of_mind < journal_schema.sql
```

The journal schema creates three tables (idempotent — uses `CREATE TABLE IF NOT EXISTS`):

| Table | Purpose |
|---|---|
| `user_journal` | Individual entries (title, media_type, mood_id, rating, …) |
| `user_collections` | Custom named collections per user |
| `user_collection_items` | Many-to-many link between collections and entries |

**Never drop these tables unless you intend to delete all user data.**

---

## Backend Startup

```bash
# From the repository root
python3 server.py
```

The server starts on **http://127.0.0.1:5001** by default.

To use a different port:

```bash
PORT=8080 python3 server.py
```

---

## Environment Variables

| Variable | Default | Description |
|---|---|---|
| `DB_HOST` | `localhost` | MySQL host |
| `DB_PORT` | `3306` | MySQL port |
| `DB_USER` | `root` | MySQL username |
| `DB_PASSWORD` | *(empty)* | MySQL password |
| `DB_NAME` | `state_of_mind` | MySQL database name |
| `PORT` | `5001` | Flask server port |

Example with overrides:

```bash
DB_USER=myuser DB_PASSWORD=secret python3 server.py
```

---

## Frontend Access

Open `journal/index.html` directly in a browser (file:// or via a local
server):

```bash
# Simplest option — Python built-in server from repo root
python3 -m http.server 8000
# Then open http://localhost:8000/journal/index.html
```

`journal.js` automatically detects whether the Flask API is reachable on
startup and operates in the appropriate mode:

- **Connected mode** — all writes go to the API; localStorage is kept as a
  read-cache.
- **Offline mode** — writes go to localStorage only; data will migrate
  automatically when the backend next becomes available.

---

## User Identity

Each browser session is assigned a stable anonymous UUID stored under the
`state_of_mind_user_id` key in `localStorage`.

```javascript
// Generated once on first load using crypto.randomUUID() where available
// Falls back to a timestamp+random string in older environments
console.log(Journal.userId);   // e.g. "550e8400-e29b-41d4-a716-446655440000"
```

Every API request includes this value as the `X-User-ID` header.  The
backend rejects any request to a personal endpoint that lacks this header
with HTTP 400.

> **Security note:** `X-User-ID` is NOT authenticated.  Any person who knows
> another user's UUID can read and modify their data.  Do not store sensitive
> personal data in the journal.

---

## LocalStorage Migration

If a user has existing data in localStorage (from before the backend was
added), it is automatically migrated to MySQL on the first load where the
backend is reachable.

Migration behaviour:

- Entries are POSTed one at a time; the mapping of local ID → server ID is
  recorded in `localStorage` under `state_of_mind_migrated_ids`.
- Collection membership is recreated using the newly-assigned server IDs.
- Duplicate collection names raise a 409 (already-migrated) and are
  silently skipped.
- **Existing local data is preserved** until migration completes without
  errors.
- If the migration is interrupted (e.g., network failure), it resumes from
  where it left off on the next load (it skips IDs already in the migrated
  set).

To trigger a manual migration from the browser console:

```javascript
const result = await Journal.migrateLocalData();
console.log(result);
// { migratedEntries: 6, migratedCollections: 2, errors: [] }
```

---

## API Reference

All personal endpoints require the `X-User-ID` header.

### Public

| Method | Path | Description |
|---|---|---|
| `GET` | `/api/health` | Health check (no auth required) |
| `GET` | `/api/moods` | List mood categories (no auth required) |

### Library entries

| Method | Path | Description |
|---|---|---|
| `GET` | `/api/library` | List entries (supports `status`, `media_type`, `mood_id`, `is_favorite`, `collection_id`, `search` query params) |
| `POST` | `/api/library` | Create entry |
| `GET` | `/api/library/<id>` | Get single entry |
| `PUT` | `/api/library/<id>` | Update entry fields |
| `DELETE` | `/api/library/<id>` | Delete entry |
| `POST` | `/api/library/<id>/favorite` | Toggle favourite |
| `POST` | `/api/library/<id>/status` | Toggle wishlist ↔ experienced |

### Collections

| Method | Path | Description |
|---|---|---|
| `GET` | `/api/collections` | List collections (includes `item_ids`) |
| `POST` | `/api/collections` | Create collection |
| `PUT` | `/api/collections/<id>` | Rename / update description |
| `DELETE` | `/api/collections/<id>` | Delete collection (entries are kept) |
| `POST` | `/api/collections/<id>/items` | Add entry to collection |
| `DELETE` | `/api/collections/<id>/items/<journal_id>` | Remove entry from collection |

**Ownership enforcement on collection items:**
Both the collection and the journal entry must belong to the requesting
`X-User-ID`.  Cross-user membership attempts return HTTP 403.

---

## Running Tests

### Backend tests (Python — no real database required)

```bash
# Syntax check
python3 -m py_compile server.py

# Full test suite (51 tests, all mocked)
python3 -m unittest discover -s tests -v

# Check for whitespace issues in tracked changes
git diff --check
```

Expected output:

```
Ran 51 tests in 0.026s
OK
```

### Frontend tests (in-browser)

Open `journal/test_runner.html` in a browser.  All tests should pass
(green).

> **Note:** Frontend tests exercise the in-memory / localStorage layer.
> API integration requires a running Flask server and a real MySQL instance.
> Results of real-database integration must be verified manually.

---

## Security Notes

1. `X-User-ID` is **not** authenticated — treat it as best-effort isolation
   only.
2. Error responses from the API never expose raw SQL error details to the
   client.
3. All SQL queries use parameterised statements (no string interpolation of
   user input).
4. CORS is open (`*`) — suitable for local development only.  Restrict this
   before any production deployment.
5. No credentials, tokens, or passwords are stored in localStorage or
   committed to the repository.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Journal loads but shows no data | Backend not running | Start `server.py`; journal will sync automatically |
| `400 X-User-ID … required` in console | UUID not sent | Reload the page so `journal.js` generates a UUID |
| `403 unauthorized` on collection item | Cross-user ID mismatch | Ensure the correct `X-User-ID` is in localStorage |
| `409 already exists` on collection | Duplicate name | Choose a different collection name |
| Migration shows errors | Network interruption | Reload the page; migration resumes from last checkpoint |
| `Database error` from API | MySQL not running or wrong credentials | Check `DB_*` env vars and confirm MySQL is running |

---

## Committing the Feature

Stage only the new/modified files:

```bash
git add journal/journal.js
git add journal/JOURNAL_GUIDE.md
git add server.py
git add journal_schema.sql
git add tests/test_server.py
# If you added any new journal UI files:
git add journal/index.html journal/style.css journal/test_runner.html
```

Recommended commit message:

```
feat: integrate journal frontend with Flask backend

- Add require_user_id() — all personal endpoints now reject requests
  lacking a valid X-User-ID header (HTTP 400) instead of falling back
  to a shared anonymous_user identifier.
- Enforce dual ownership check on collection-item add/remove: both
  the collection and journal entry must belong to the requesting user;
  cross-user access returns HTTP 403.
- Sanitise API error responses (no raw SQL details exposed).
- Add rating validation (0–5) on create and update.
- journal.js: UUID generation via crypto.randomUUID() with fallback,
  persisted under state_of_mind_user_id.
- journal.js: full API client (apiRequest) — all CRUD, favorites,
  status, moods, collections, and collection membership now backed by
  the Flask API with transparent localStorage fallback when offline.
- journal.js: safe retryable migration from localStorage to MySQL
  (preserves local data until migration succeeds, avoids duplicates).
- Expand test suite from 9 to 51 tests covering: missing X-User-ID on
  every endpoint, input validation, CRUD ownership, favorite/status
  toggling, collection CRUD, and cross-user collection-item security.
- Update JOURNAL_GUIDE.md with full setup, migration, and test docs.
```

Push command:

```bash
git push origin main
```

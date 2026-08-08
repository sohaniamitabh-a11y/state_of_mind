# State of Mind

A mood-based cross-media recommendation engine. Pick how you're feeling — the engine hands back Movies, TV, Music, and Games that actually fit that headspace.

No sign-up, no live API calls at query time. Everything runs off a locally cached database, refreshed periodically by scheduled harvesters, so recommendations are instant.

## Core idea

> "A brain shall never be restricted to specific data."

New moods, genres, or media domains get added as new **rows**, never new tables or columns. The system is built to grow without structural rewrites.

## Architecture

The project has four components:

| Component | Status | Description |
|---|---|---|
| **The Brain** | ✅ Live | `mood_genre_mapping` table — weighted mood-to-genre relevance scores, built from team ratings |
| **The Harvester** | ⚙️ Partial | Three scripts pulling trending data (movies/TV, games, music) into the cache |
| **The Backend / Engine** | 🚧 In progress | Flask API (`/get-state?mood=X`) that joins mood → genre → items and returns recommendations |
| **Frontend** | ⏳ Not started | Flutter app — fixed mood-button UI, no free text input |

## Database

Cloud-hosted on Aiven MySQL (SSL required). Six tables:

- `moods` — the 5 fixed moods (Happy/Excitement, Calm/Serene, Sad/Melancholy, Anger/Rage, Confusion/Anxiety)
- `genres` — cross-media genre catalog (TMDB movie/TV genres, Deezer music genres, RAWG game genres)
- `mood_genre_mapping` — "the Brain": weighted relevance score per mood-genre pair
- `items` — harvested trending content (title, popularity, metadata)
- `item_genres` — junction table linking items to their genres
- `feedback` — user feedback per recommendation (schema ready, not yet in use)

Sort logic for recommendations: **relevance_score first** (mood-fit is the priority), **popularity_score as tiebreaker** — this is a feeling-oriented app, not a trending-oriented one.

## Backend build progress

Building the Flask backend as a step-by-step learning project rather than from a generic tutorial. Progress so far:

- [x] **Stage 1** — Basic Flask app, run/debug mode
- [x] **Stage 2** — Reading query params (`/get-state?mood=X`) via `request.args`
- [x] **Stage 3** — Live connection to the cloud DB from inside a request
- [x] **Stage 4** — The full mood → genre → items join query, wired into the live route
- [ ] **Stage 5** — Shaping the response: dedupe results, bucket into movies_tv / music / games, cap at top 5 each
- [ ] **Stage 6** — Error handling (404 on invalid/missing mood)
- [ ] **Stage 7** — Testing the API standalone, without the frontend

## Tech stack

- **Backend:** Python (Flask), MySQL (Aiven cloud)
- **Data sources:** TMDB (movies/TV), RAWG (games), Deezer (music)
- **Frontend (planned):** Flutter
- **Data prep:** Python runner scripts for schema/seed/mapping SQL, Google Forms for genre-mood survey ratings

## Setup

Each device needs its own `.env` (never committed) with:
```
DB_HOST=...
DB_PORT=...
DB_USER=...
DB_PASSWORD=...
DB_NAME=state_of_mind
DB_SSL_CA=...
# plus whichever single API key that device's harvester needs
```

Install dependencies:
```
pip install requests mysql-connector-python python-dotenv flask
```

Run the backend:
```
python app.py
```

## Team

A 3-person college mini-project. Each teammate's device runs one harvester (movies/TV, games, or music) against the shared cloud database.
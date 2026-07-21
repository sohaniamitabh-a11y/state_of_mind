# State of Mind

A mood-based cross-media recommendation engine. Pick how you're feeling — the engine hands back the Movies, TV, Music, and Games that actually fit that headspace.

> No sign-up, no live API calls at query time. Everything runs off a locally cached database, so recommendations are instant and the whole thing works offline once seeded.

---

## How it works

```
   You pick a mood
         │
         ▼
┌─────────────────────┐
│   THE BRAIN          │   mood_genre_mapping — every mood is linked to a
│   (weighted mapping) │   set of genres, each with a relevance_score
└─────────┬────────────┘
          │
          ▼
┌─────────────────────┐
│   THE ENGINE          │   runs the JOIN, ranks by relevance × popularity,
│   /get-state?mood=X   │   returns the top 5 per media type
└─────────┬────────────┘
          │
          ▼
   Top 5 Movies/TV · Top 5 Music · Top 5 Games
```

Behind the scenes, **The Harvester** runs on a schedule (cron / Task Scheduler) to keep the item catalog fresh — pulling trending content from external APIs and caching it locally, so the Engine never has to hit a live API mid-request.

**Core design principle:** a brain shall never be restricted to specific data. The schema is built so new domains — food, fashion, anything — can be added later as just more rows, never new tables or columns.

---

## Architecture

| Component | Role | Status |
|---|---|---|
| **The Brain** | `mood_genre_mapping` table — moods weighted against genres | ✅ Populated |
| **The Harvester** | Scheduled script pulling trending data into cache | 🚧 Built (Java + Python), not yet scheduled |
| **The Engine** | `/get-state?mood=X` endpoint running the ranked JOIN | ⬜ Not started |
| **Frontend** | User-facing mood picker + results view | ⬜ Not started |

---

## Data sources

| Media type | Source | Notes |
|---|---|---|
| Movies / TV | [TMDB](https://www.themoviedb.org/documentation/api) | Genre data verified and loaded |
| Games | [RAWG](https://rawg.io/apidocs) | 19 genre slugs verified and loaded |
| Music | [Deezer](https://developers.deezer.com/api) (+ Last.fm for tag nuance) | Genre IDs pending live verification |

---

## Database schema

MySQL, 6 core tables:

- **`moods`** — the 5 fixed mood categories (Happy/Excitement, Calm/Serene, Sad/Melancholy, Anger/Rage, Confusion/Anxiety)
- **`genres`** — all genres across all 4 media types, one table
- **`mood_genre_mapping`** — the weighted links between moods and genres (the "Brain")
- **`items`** — harvested content, cached with full raw metadata as JSON
- **`item_genres`** — many-to-many links between items and genres
- **`feedback`** — user reactions, reserved for future adaptive scoring

Full definitions live in [`schema.sql`](./schema.sql). Seed data for the mood-genre weights (crowd-rated by a 3-person team) is in [`mood_genre_mapping_inserts.sql`](./mood_genre_mapping_inserts.sql).

---

## Getting started

### 1. Set up the database

```bash
mysql -u root -p < schema.sql
mysql -u root -p < mood_genre_mapping_inserts.sql
```

### 2. Set up your secrets

Real API keys and passwords are **never committed** — copy the example files and fill in your own values:

```bash
cp .env.example .env                              # for the Python harvester
cp config.example.properties config.properties     # for the Java harvester
```

### 3. Run the Harvester

**Python:**
```bash
pip install requests mysql-connector-python python-dotenv
python trending_harvester.py
```

**Java:**
```bash
# add MySQL Connector/J and org.json to your classpath, then:
java TrendingHarvester
```

---

## Roadmap

- [x] Learn the SQL needed for this project
- [x] Design the mood → genre mapping
- [x] Build and populate the core schema
- [x] Crowd-rate genre relevance scores (3-person team average)
- [x] Build the Harvester (movie/TV branch — TMDB)
- [ ] Extend Harvester to RAWG (games) and Deezer (music)
- [ ] Hand-populate sample items to test the full JOIN end-to-end
- [ ] Build the Engine (`/get-state?mood=X`)
- [ ] Build the frontend
- [ ] Polish

---

## Tech stack

- **Database:** MySQL
- **Harvester:** Java (JDBC + `HttpClient` + org.json) and Python (`mysql-connector-python` + `requests`)
- **APIs:** TMDB, RAWG, Deezer

---

## the project is for collage project 
its not complete yet 

---

## License

Not yet decided.

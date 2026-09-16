# Contributing to State of Mind

A 3-person college project, so this is short. The goal is that six months from now the git log still tells us what happened and why — see [docs/09-COMMIT-HISTORY.md](docs/09-COMMIT-HISTORY.md) for what the log looks like when it doesn't.

## Commit messages

**Format:**

```
<type>: <what changed, in the imperative>

<why it changed, if it isn't obvious. Wrap at ~72 characters.>
```

**Types:**

| Type | Use for |
|---|---|
| `feat` | New behaviour a user or caller can observe |
| `fix` | Correcting behaviour that was wrong |
| `data` | Schema, seed, or mapping SQL changes |
| `harvest` | Changes to any of the three harvester scripts |
| `docs` | Documentation and comments only |
| `chore` | Tooling, `.gitignore`, housekeeping — no behaviour change |
| `refactor` | Restructuring with no behaviour change |

**Good:**

```
feat: bucket /get-state results into movies_tv, music, games

Stage 5. Movie and TV media_types both map into movies_tv; each
bucket is capped at its top 5 after the relevance sort.
```

```
data: add 74 mood_genre_mapping rows for expanded genres

Scores from the second survey round, averaged and divided by 5.
Safe to re-run — run_mapping.py skips duplicate keys.
```

**Avoid:**

- `Add files via upload` — this is what GitHub writes when you drag files into the web UI. Four commits in this repo's history say exactly this and none of them explain anything. **Commit from your machine, not the browser.**
- `updates`, `fixes`, `changes`, `work`, `asdf` — true of every commit ever made.
- `Stage 4: ...; add .gitignore` — two unrelated changes in one commit. Split them.
- A message that describes only part of what the commit contains. If you can't summarise it in one line, that's the commit telling you it should be two commits.

## One logical change per commit

If the message needs an "and", consider splitting. A `.gitignore` addition and a new feature are two commits even when you wrote them in the same sitting.

This genuinely matters here: `.gitignore` arrived three days after the commit whose message claimed it, so for that window there was no rule keeping `.env` out of the repository.

## Never commit secrets

`.gitignore` covers `.env` and `config.properties`. Real credentials live only on your own machine.

Each device needs only its own harvester's API key — `TMDB_API_KEY` for movies/TV, `RAWG_API_KEY` for games, none for music. Nobody needs all three. See [docs/07-SETUP.md](docs/07-SETUP.md).

Be aware that the `ignore/` directory is **not** git-ignored despite its name — files placed there are tracked and published. It currently holds only `ca.pem`, a public SSL CA certificate, which is fine. Don't assume that folder protects anything.

## Before you push

- `python check_table.py` still connects and reports `moods: 5`, `genres: 63`.
- `python app.py` starts and `/get-state?mood=Happy/Excitement` returns rows.
- If you changed SQL, confirm the relevant `run_*.py` applies it cleanly against the shared database, and that re-running it is still a no-op.

## Keep the docs honest

The docs in [`/docs`](docs/) state real status, including what's broken and unfinished. That's the point of them — a doc claiming a harvester works when it's never been run is worse than no doc.

If your change moves any of these, update the doc in the same commit:

- **Live row counts** — [00-OVERVIEW.md](docs/00-OVERVIEW.md) and [02-DATABASE.md](docs/02-DATABASE.md)
- **A backend stage completing** — [05-BACKEND.md](docs/05-BACKEND.md) and the checklist in [readme.md](readme.md)
- **A harvester's status** — [04-HARVESTERS.md](docs/04-HARVESTERS.md)
- **A design choice with a trade-off** — add it to [08-DECISIONS.md](docs/08-DECISIONS.md), with the cost you're accepting, not just the reason

## Branches

Work on a branch named for the change (`stage5-bucketing`, `music-genre-matching`) and merge into `main` when it works. Don't rewrite or force-push published history — teammates may have already cloned it.

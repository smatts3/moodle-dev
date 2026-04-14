# LSU Moodle dev / test environment

This repo drives local Moodle stacks (Docker Compose + Traefik), mainly via `new.sh`. The running app is a clone of **[lsuonline/lsuce-moodle](https://github.com/lsuonline/lsuce-moodle)** inside the web container—not this repository’s tree.

# Requirements

UNIX environment, Linux / Mac preferred.

## Linux / MacOS

- Docker
- Docker Compose

## Windows

- Docker Desktop (or docker / docker compose)
- Git Bash (or MINGW)

# Setup

Put confidential moodle / plugin config settings into `./confidential`.

The format is `COMPONENT`|`NAME`|`VALUE`. One per line. See `confidential.template`.

# Usage

On Windows, make sure docker desktop is running.

1. To launch a new instance of a dev environment, in a bash terminal run:

   ```bash
   new.sh [NAME]
   ```

   Where `NAME` is an optional compose project name (e.g. `new_widget`, `fix_login`). If omitted, a random 4-character name is used (e.g. `e92d`).

1. If successful, you can access the site at `http://moodle.NAME.localhost` (with Traefik / `TRAEFIK_HOST` as configured).

1. Open a shell in the Moodle container:

   ```bash
   MSYS_NO_PATHCONV=1 docker exec -it {NAME}-moodle /bin/bash
   ```

1. You can edit code with VS Code [Dev Containers](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers) and open `/var/www/html` (or attach to the container).

1. Use Git **inside the container** for Moodle/plugin work (`/var/www/html`).

1. Tear down the stack:

   ```bash
   docker compose -p {NAME} down
   ```

   Or remove the stack from Docker Desktop.

### Optional: submodules after merge

To convert vendored plugin directories in the container to Git submodules (see **lsuce-moodle branches** below):

```bash
./new.sh NAME --submodulize
```

GitHub auth for private `lsuonline/*` repos: `GITHUB_TOKEN` or `GH_TOKEN`, file `cleandev/.github-token` (gitignored), interactive prompt when run in a TTY, or `SUBMODULIZE_SSH=1` if SSH works inside the container.

# Build

By default, `docker-compose.yml` **builds** the web image from `./Dockerfile` (`php:8.3-apache`) and tags it as `lsuce-moodle-web:local`. That avoids PHP 8.4 + Moodle 4.5 CLI issues noted in `docker-compose.yml`. To use a pre-built image instead, follow the comment in `docker-compose.yml` (`image:` vs `build:`).

To build the legacy Hub-oriented image name (used by `build.sh`):

```bash
docker build -t lsuonline/moodle-dev:latest .
```

# lsuce-moodle: `develop` vs `cleandev`

These are **branches on the Moodle repo** (`lsuce-moodle`), not branch names in *this* repo.

| Branch | Layout |
|--------|--------|
| **develop** | Plugins **vendored** (plain files committed in the monorepo). This is what most developers use today. |
| **cleandev** | Same plugins as **submodules** (per `.gitmodules` + manifest), for cleaner boundaries and per-plugin Git history. |

**Goal (not fully implemented):** Devs can move to **cleandev** as the primary line of work, while **develop** stays mergeable. That requires agreed process and/or automation for:

- Porting changes **both ways** (submodule layout ↔ vendored layout).
- **Redoing or replaying commits** with a **provenance note** (e.g. original commit SHA / branch)—so history stays traceable across layouts.

**Current repo state:** This project ships **layout converters** (`submodulize.sh` / `unsubmodulize.sh`). **Replay is the default:** they build `submodulized` / `unsubmodulized` branches with **one superproject commit per plugin-repo commit** (chronological ordering, carry-forward; **`--fork-point`** required). Use **`--no-replay`** for one-shot conversion over the manifest only. A `new.sh` mode that detects vendored vs submodulized state without manual choice is still not implemented.

**Branch policy, Docker image decision, and updating the manifest from the CSV:** [cleandev/TEAM-PROCESS.md](cleandev/TEAM-PROCESS.md).

# Submodule tooling (`cleandev/`)

## Manifest (`cleandev/plugin-submodules.manifest`)

This repo keeps a **canonical copy** under `cleandev/` for linting and for `new.sh --submodulize` (copied into the Moodle tree at runtime). When you run `submodulize.sh` / `unsubmodulize.sh` against a checkout, the default manifest path is **`plugin-submodules.manifest` at the Moodle superproject root** (`--repo` / current directory), not next to the scripts; use `--manifest PATH` to override.

- Format: `relative_path|clone_url|branch` (e.g. `mod/hvp|https://github.com/...|main`). Lines starting with `#` are ignored.
- If the third field is empty, scripts default the branch to `main`; if `refs/heads/<branch>` is missing on the remote, they omit `-b` and use the remote’s default branch.
- **Active lines:** one Git repo root per Moodle path (works with `git submodule add` and shallow clone + copy).
- **Commented “monorepos”:** same URL, multiple top-level Moodle paths. Today’s scripts cannot express “clone once, map subpaths”; those stay vendored or need manual handling until manifest/script support exists.
- **Commented “no clone” / bad remote:** e.g. `local/ml` where inventory pointed at a wrong/404 repo—left vendored until a real remote exists.
- **Commented “no https URL”:** no usable URL in source inventory.

## Scripts

| Script | Role |
|--------|------|
| `cleandev/submodulize.sh` | Default **replay** (`--fork-point`): one superproject commit per plugin commit (gitlinks + `.gitmodules`). **`--no-replay`**: one-shot vendored → submodules (sparse-checkout disabled first; skips paths already in `.gitmodules`; `GITHUB_TOKEN` via `-c url...insteadOf` for `ls-remote` / `submodule add`). |
| `cleandev/unsubmodulize.sh` | Default **replay** (`--fork-point`): one superproject commit per plugin commit (vendored trees). **`--no-replay`**: one-shot submodules → vendored (clone depth 1, drop nested `.git`, `git add`). Same `GITHUB_TOKEN` / `--ssh` as `submodulize.sh`. |

Run manually from a Moodle clone:

```bash
./cleandev/submodulize.sh [--no-replay] [--dry-run] [--no-commit] [--ssh] [--manifest PATH] [--repo ROOT]
./cleandev/unsubmodulize.sh [--no-replay] [--dry-run] [--no-commit] [--ssh] [--manifest PATH] [--repo ROOT]
```

Automated tests (manifest lint, PAT wiring checks, `submodulize`/`unsubmodulize` round-trip in temp repos—no changes to your working tree):

```bash
bash cleandev/tests/run.sh
```

## Container startup (`new.sh`)

- Compose project name = first argument (containers `{NAME}-moodle`, etc.).
- Web service builds from `.` per `docker-compose.yml`.
- As `www-data`: `git fetch` / `git merge origin/develop`; removes `blocks/ues_people` and uses `skip-worktree` so it does not clash with `block_lsu_people` (see `config/moodle-pull` for the same idea on `git pull`).
- With `--submodulize`: copies scripts into the container, stages `cleandev/plugin-submodules.manifest` into `/var/www/html/plugin-submodules.manifest` after the merge, resolves GitHub token, sets local `url...insteadOf` when using HTTPS token, runs `manifest-submodulize-redundant.sh` / `submodulize.sh --no-replay` with default manifest paths (`--repo /var/www/html`, optional SSH via `SUBMODULIZE_SSH=1`).

Secrets: `cleandev/.github-token` is listed in `.gitignore`.

# Roadmap

Done items, TODOs, and progress toward seamless **`develop` ↔ `cleandev`** on lsuce-moodle: see **[ROADMAP.md](ROADMAP.md)**.

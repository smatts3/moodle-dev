# Roadmap

Progress toward **seamless `develop` ↔ `cleandev`** (on [lsuce-moodle](https://github.com/lsuonline/lsuce-moodle)) and polish around this Docker/tooling repo.

## Done (current state)

- [x] Docker Compose + Traefik-oriented local stack via `new.sh`
- [x] Web image built from repo `Dockerfile` (PHP 8.3) to avoid Moodle 4.5 + PHP 8.4 CLI `SerializableClosure` install failure (`docker-compose.yml` documents reverting to a pre-built image if desired)
- [x] `cleandev/plugin-submodules.manifest` + `submodulize.sh` + `unsubmodulize.sh`
- [x] `new.sh --submodulize` with token file / env / prompt and optional SSH
- [x] Sparse-checkout disabled in both scripts before mutating plugin paths
- [x] `blocks/ues_people` handling in `new.sh` and `config/moodle-pull` (merge / pull alias)
- [x] Git ignore for `cleandev/.github-token`
- [x] **Team process, image strategy, manifest-from-CSV docs:** [cleandev/TEAM-PROCESS.md](cleandev/TEAM-PROCESS.md)

## TODO

- [ ] **Commit portability:** Script or documented workflow to **replay or port commits** across layouts with a **header** noting the original commit (and branch/repo). *Not in repo today—only bulk layout conversion exists.*
- [ ] **`new.sh` / tooling:** Detect or select **vendored vs submodulized** Moodle tree so one flow works without guessing flags.
- [x] **`unsubmodulize.sh`:** Same `GITHUB_TOKEN` `-c url.insteadOf` pattern as `submodulize.sh` for private HTTPS (parity with submodule add).
- [ ] **Monorepo manifest + scripts:** Support “clone once, map subpaths”, or publish **one-shot manual procedures** for commented monorepo lines.
- [ ] **`local/ml`:** Point at the correct Git remote when known; uncomment or add manifest line.
- [ ] **Optional CI:** Check that manifest paths still match **lsuce-moodle** `develop` plugin layout when plugins move.

---

For branch policy, when to use `new.sh --submodulize`, image strategy, and refreshing `plugin-submodules.manifest` from the CSV, see [cleandev/TEAM-PROCESS.md](cleandev/TEAM-PROCESS.md).

For a concise summary of flags and auth behavior, see comments at the top of `cleandev/submodulize.sh` and `cleandev/unsubmodulize.sh`.

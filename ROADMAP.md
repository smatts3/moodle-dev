# Roadmap

Progress toward **seamless `develop` ↔ `cleandev`** (on [lsuce-moodle](https://github.com/lsuonline/lsuce-moodle)) and polish around this Docker/tooling repo.

## Done (current state)

- [x] Docker Compose + Traefik-oriented local stack via `new.sh`
- [x] Web image built from repo `Dockerfile` (PHP 8.3) to avoid Moodle 4.5 + PHP 8.4 CLI `SerializableClosure` install failure (`docker-compose.yml` documents reverting to a pre-built image if desired)
- [x] `submodulizer-local/plugin-submodules.manifest` + `submodulizer/submodulize.sh` + `submodulizer/unsubmodulize.sh` (the scripts vendored as a Git submodule from [smatts3/submodulizer](https://github.com/smatts3/submodulizer))
- [x] `new.sh --submodulize` with token file / env / prompt and optional SSH
- [x] Sparse-checkout disabled in both scripts before mutating plugin paths
- [x] `blocks/ues_people` handling in `new.sh` and `config/moodle-pull` (merge / pull alias)
- [x] Git ignore for `submodulizer-local/.github-token`
- [x] **Team process, image strategy, manifest-from-CSV docs:** [submodulizer-local/TEAM-PROCESS.md](submodulizer-local/TEAM-PROCESS.md)

## TODO

- [ ] **Commit portability:** Script or documented workflow to **replay or port commits** across layouts with a **header** noting the original commit (and branch/repo). *Not in repo today—only bulk layout conversion exists.*
- [x] **`new.sh` / tooling:** With `--submodulize`, **detect** when every manifest path is already a submodule (cleandev-style) and **skip** `submodulize.sh` instead of a no-op pass. *Not done: auto-run conversion without passing `--submodulize`.*
- [x] **`unsubmodulize.sh`:** Same `GITHUB_TOKEN` `-c url.insteadOf` pattern as `submodulize.sh` for private HTTPS (parity with submodule add).
- [x] **Monorepo manifest + scripts:** **One-shot manual procedures** for commented monorepo lines: [submodulizer-local/TEAM-PROCESS.md](submodulizer-local/TEAM-PROCESS.md) (manifest regeneration → Monorepos). *Not done: automated “clone once, map subpaths” in `submodulize.sh`.*
- [ ] **`local/ml`:** Point at the correct Git remote when known; uncomment or add manifest line.
- [x] **CI (submodulizer):** GitHub Actions runs `submodulizer/tests/run.sh` (manifest lint, round-trip integration tests, shellcheck on Ubuntu).
- [ ] **Optional CI:** Check that manifest paths still match **lsuce-moodle** `develop` plugin layout when plugins move.

---

For branch policy, when to use `new.sh --submodulize`, image strategy, and refreshing `plugin-submodules.manifest` from the CSV, see [submodulizer-local/TEAM-PROCESS.md](submodulizer-local/TEAM-PROCESS.md).

For a concise summary of flags and auth behavior, see comments at the top of `submodulizer/submodulize.sh` and `submodulizer/unsubmodulize.sh`.

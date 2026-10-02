# CLAUDE.md

Guidance for Claude Code in this repository: a public macOS client that keeps
an `ssh -D` SOCKS tunnel, a gost HTTP bridge, a watchdog and a log cap running
as launchd services. The README is the full reference.

<!-- aicolab:holding-block lang=en: canonical text in aicolab/templates/holding-block.en.md; do not edit here, run aicolab/scripts/holding_block.py write -->

## Place in the AIColab holding

`macos-socks-proxy-tunnel-autostart` is a personal repository of the operator in the AIColab holding: entry `repos.macos-socks-proxy-tunnel-autostart` in the
`holding.yaml` registry of the management company
[`PavelSozonov/aicolab`](https://github.com/PavelSozonov/aicolab), locally
`~/projects/aicolab`. When the `aicolab` directory is not attached to the
session, read its files by the local path.

- **Shared rules live in `aicolab`**: the charter `docs/charter.md` and the
  standards `docs/standards/`. This file refines them for this repository but
  never overrides them; a conflict is settled by a PR to `aicolab`, not by an
  exception here.
- **A task wider than this repository** — another company, a shared service,
  ownership — starts from the `CLAUDE.md` and the registry of `aicolab`;
  `scripts/session.sh <company>` there attaches the right directories.
- **Holding sync**: a significant change is checked against the registry,
  contracts, charter and standards of `aicolab` before it merges and brought
  into line with them — by changing the change or by a PR to `aicolab`. What
  counts as significant and how to settle a divergence:
  `docs/standards/holding-sync.md`.
- **TODO**: work that spans several companies is tracked in the `TODO.md` of
  `aicolab`; this repository keeps a pointer.

Standards (`~/projects/aicolab/docs/standards/`):

| Standard | Gist |
| --- | --- |
| `commits.md` | Conventional Commits; English subject, Russian body; no trailers and no tool attribution anywhere |
| `language.md` | English for anything that becomes an identifier, Russian for anything that explains |
| `ownership.md` | one owner per file, host and name; an ownership dispute is settled, not worked around |
| `todo-file.md` | one `TODO.md` at the repository root, a snapshot of what is owed; done items are deleted, what outlives a task moves; warnings and deprecations are recorded at once and triaged by priority |
| `secrets.md` | where secrets live and what never enters a repository |
| `new-repo.md` | what every holding repository must have; the template and the creation script |
| `checks.md` | baseline pre-commit hooks and CI jobs; CI repeats the local hooks, hooks are never bypassed |
| `alerts.md` | every false alarm is a defect: measure the cause, exclude exactly it, record the cost |
| `holding-sync.md` | a significant change is checked against the registry, contracts, charter and standards of `aicolab`; a divergence is settled in the change or in the document |
| `holding-block.md` | every `CLAUDE.md` carries this canonical block from `aicolab`; it is never edited by hand and `check.py` compares it |

<!-- /aicolab:holding-block -->

## Public repository

- Everything written here is in English: docs, comments, commit messages
  (subject and body), pull request titles and descriptions.
- Server addresses, user names and keys live only in the gitignored `.env`
  and `/private/`; examples use the placeholders of `.env.template`.

## Checks

`make lint` runs the same pre-commit hooks as CI (whitespace, file endings,
YAML, shebangs, private keys, `shellcheck` on the scripts); `make help` lists
every target.

## TODO.md

Hygiene follows the holding standard `todo-file.md`.

# Changelog

Notable changes. Versions between tags exist in `main` history but weren't tagged
(tags are just bookmarks — `upgrade` and `install.sh` pull from `main`).

## v0.10.4
- Interview autodetect: the incremental dir now explicitly defaults to the
  **snapshot dir** (not the ledger) when the validator has no incremental-
  snapshot flag — matching Agave's own default.
- Hardened validator-process detection: instead of blindly taking the first
  `pgrep` hit, try each candidate and accept only one that carries real
  snapshot/ledger argv tokens, so a stray shell / `tail` / monitor that merely
  mentions `agave-validator` can't be mistaken for the validator.

## v0.10.3
- Interview autodetect recognizes the older Agave flag aliases `--snapshots`
  (full) and `--incremental-snapshot-archive-path` (incremental), so the
  full-snapshot dir no longer wrongly falls back to `--ledger`.

## v0.10.2
- `version [HOST]` reports a remote host's xfsnap version over ssh.

## v0.10.1
- `--to-staging` / `--from-staging`: land into / read from a `staging/` subdir
  instead of the live ledger dir (works on every transfer command).
- README: "Design goals" section.

## v0.8.x
- `install` → renamed **`deploy`** (`install` kept as a hidden alias); reads as
  "push this build", not "pull from a repo".
- Remote management: `doctor [HOST]`, `clean [HOST]`, `upgrade [HOST]` run over
  ssh; `upgrade HOST` offers to deploy if the host has no xfsnap yet.
- `role=orchestrator` config so `doctor` passes orchestrator-only boxes.
- Consistent sentence-case output (`OK:`/`Warn:`/`Error:`/`Fail:`).

## v0.7.0
- `xfsnap interview [HOST]` — run setup on a remote host over ssh, syncing its
  version first.
- Optional `[peer]` arg on `put`/`get`/`putinc`/`getinc`.
- Clearer interview prompts; guided multi-host wizard.

## v0.6.x
- `xfsnap upgrade` (self-update from GitHub); non-blocking version-skew warnings
  (`--strict`); remote install + downgrade guard (`--force`).
- macOS fixes: atomic self-replace (rename, not in-place `cp`); BSD `chmod`.

## v0.5.0
- **First public release.** Config-driven, self-describing nodes (each host
  describes only itself; the source discovers a peer's dirs over ssh).
- `config` (get/set/list/interview with validator autodetect), `install.sh`
  (`curl | sh`), `install`, `doctor`, `clean`. MIT licensed.

## v0.2.0
- Ported from zsh to bash (single self-contained file).

## v0.1 (untagged)
- Initial zsh prototype: chunked `dd | ssh dd seek` transfer, resumable via a
  ledger, `zstd -t` verify, atomic rename, pre-snapshot timing guard.

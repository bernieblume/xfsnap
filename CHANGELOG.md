# Changelog

Notable changes. Versions between tags exist in `main` history but weren't tagged
(tags are just bookmarks — `upgrade` and `install.sh` pull from `main`).

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

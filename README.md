# xfsnap

Fast, resumable transfer of Solana (Agave) snapshots between validator hosts.

Downloading a 100GB+ full snapshot from the cluster is slow and the snapshot is
stale by the time it lands. When one of a validator pair fails, it's far faster
to copy the freshest snapshot the *other* box already has. `xfsnap` does that
over a saturated, multi-stream SSH transfer with full resume.

## How it works

A full snapshot is a single `snapshot-<slot>-<hash>.tar.zst`. To fill a
long-fat WAN link (a single TCP flow can't), `xfsnap` splits the file into
fixed-size byte ranges and pushes them with N concurrent
`dd | ssh dd seek` streams **straight into a pre-allocated file** on the
destination — no reassembly step, no double disk usage.

- **Resume**: a tiny ledger under `<dstdir>/.xfsnap/<name>.state` records each
  completed chunk. Interrupt anytime; re-run the same command and it ships only
  what's missing.
- **Integrity**: each chunk is marked done only if the receiver wrote the exact
  byte count (so a killed sender can't leave a chunk falsely "complete"); the
  finished file is `zstd -t`-tested. `--verify` adds a full end-to-end sha256.
- **Atomic**: transfers into `<name>.part`, renames into place only on success —
  the target validator never sees a partial file.
- **No wasted CPU**: SSH compression off (already zstd), fast AES-GCM cipher.

## Install

Self-contained single file. Copy to each host:

```sh
scp xfsnap vn:/usr/local/bin/xfsnap   # and ve, etc.
ssh vn 'sudo chmod +x /usr/local/bin/xfsnap'
```

It auto-detects which host it's on (via `hostname -s`) and sets the snapshot
dirs + peer from the built-in host table. **Edit the table at the top of the
script** to match your hosts.

## Usage

```
xfsnap <subcommand> [options]

  help  h                    show help
  get   g                    pull newest full snapshot: peer -> here
  getinc  gi                 pull newest incremental:   peer -> here
  put   p                    push newest full snapshot: here -> peer
  putinc  pi                 push newest incremental:   here -> peer
  transfer  trf  SRC DST     push newest full   SRC -> DST  (ssh short names)
  transferinc trfi SRC DST   push newest incremental SRC -> DST
  clean  cl                  remove leftover .xfsnap staging on this host

Options:
  --streams N     concurrent streams (default 8)
  --chunk SIZE    chunk size, e.g. 512M, 2G (default 1G)
  --yes           assume yes to the pre-snapshot timing guard
  --no-verify     skip the final zstd -t on the dest
  --verify        also sha256 the whole file end-to-end (slow)
  --watch         (putinc/getinc) loop, shipping each new incremental
  --now           (putinc/getinc) ship the current newest now, don't wait
  --dry-run       show the plan only
```

### `--now` vs the default wait

`putinc`/`getinc` default to **waiting for the next** incremental (so the copy
is the freshest possible). `--now` instead ships whatever's newest *right now*.
Combine with `--watch` to ship the current one immediately and then keep
shipping newer ones as they land.

### Just-in-time incremental (cold start with `--no-snapshot-fetch`)

When you boot a validator from a full snapshot with `--no-snapshot-fetch`, it
spends ~10-15 min rebuilding storages before it loads an incremental — and you
want that incremental as fresh as possible at the moment rebuild finishes.
Simplest robust approach: run `xfsnap putinc --now --watch` on the source for
the whole rebuild window, so the dest always holds an incremental at most ~1 min
old. Or, if you'd rather do it by hand, run `xfsnap putinc --now` when the
rebuild is ~1 min from done. (Timing the transfer to land *exactly* at rebuild
completion is marginal gain over continuous `--watch`, and a pain to test.)

### Typical DR flow

On the healthy box (say `vn`), push the freshest full snapshot to the backup,
then keep the incremental fresh until you boot:

```sh
vn$ xfsnap put            # 8-stream full snapshot -> ve  (resumable)
vn$ xfsnap putinc --watch # ship each new incremental to ve as it lands
```

Or orchestrate from a third box (data still flows source->dest directly, it
hops to the source to avoid trom­boning through you):

```sh
gentian$ xfsnap transfer vn ve
```

### The pre-snapshot timing guard (`put`/full transfers)

Agave writes a full snapshot every `--full-snapshot-interval-slots` (default
**100000** ≈ 11h). `xfsnap` reads the newest snapshot's slot from its filename,
asks `solana slot` for the chain tip, and if a fresh full is due within the next
hour it warns and asks whether to proceed (better to wait for the newer one).
`--yes` skips the prompt; non-interactive runs abort by default.

## Notes / roadmap

- **Host table** keys are ssh short names from `~/.ssh/config`. Each entry:
  full-snapshot dir, incremental dir, peer, and the `hostname -s` to match.
- Incrementals need their base full snapshot present on the dest to be usable;
  `putinc`/`getinc` warn if it's missing (but still ship).
- If the source validator is down, `solana slot` may fail and the guard is
  skipped — which is correct (no new snapshot is coming).
- **Roadmap**: a true coordinator that holds no data path (SSH tunnels) for the
  remote→remote case; currently that case hops to the source, which needs
  `xfsnap` installed there.

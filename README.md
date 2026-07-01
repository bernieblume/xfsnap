# xfsnap

**Fast, resumable transfer of Solana (Agave) snapshots between your own validator hosts.**

## The problem

Your primary validator just went down. You need the backup voting *now* — but
its snapshot is hours old, so first it has to fetch a fresh one from the
cluster. A full snapshot is 100 GB+ these days, the download crawls, peers throttle
you, and by the time it lands it's already stale so the validator fetches an
incremental on top... and you're still delinquent while the clock runs.

Meanwhile your *other* box already has a snapshot that's minutes old. It's
sitting right there on a machine you own. Getting it across the wire should be
the easy part — except a single `scp`/`rsync` tops out at a fraction of your
link because one TCP flow can't fill a long-fat path, and the "just use bbcp /
rclone" answer is a configuration rabbit hole every single time.

If you run a validator pair for failover, you've had this exact problem.

## What xfsnap does

Copies the freshest snapshot from the healthy box to the other one, **fast and
resumably**:

- **Saturates the link.** Splits the snapshot into byte-range chunks and pushes
  them over **N parallel `dd | ssh dd` streams** (default 8) straight into a
  pre-allocated file on the destination — no reassembly, no double disk usage.
- **Resumes.** Interrupted at 80 GB of 109? Re-run the same command; it ships
  only the missing chunks. A tiny ledger under `.xfsnap/` tracks progress and
  survives reboots on either end.
- **Won't hand you a corrupt snapshot.** Each chunk is committed only if the
  receiver wrote the exact byte count; the finished file is `zstd -t`-tested and
  atomically renamed into place. `--verify` adds a full end-to-end sha256.
- **Times the full snapshot.** Warns if a fresh full snapshot is about to be
  generated so you don't ship one that's about to be stale.
- **Streams incrementals just-in-time.** `putinc --watch` ships each new
  incremental the moment it lands, so the backup is always ~1 minute behind.
- **One self-contained file.** No daemon, no dependencies beyond what a
  validator box already has (zsh, coreutils, ssh, zstd).

It moves snapshots **between hosts you control over ssh** — it is not a public
snapshot service and does not talk to the cluster's RPC (except to read the
current slot for the timing guard).

## Getting started

You need **two hosts that can already `ssh` to each other by short name** (from
`~/.ssh/config`) — e.g. `primary` and `backup`. xfsnap is one self-contained
file; you set it up on **both**. Requires `zsh`, GNU coreutils, `ssh`, and
`zstd` (all already on a validator box).

### 1. On the first host (`primary`)

```sh
# fetch the single file
curl -fsSL https://raw.githubusercontent.com/<you>/xfsnap/main/xfsnap -o /tmp/xfsnap

# install to /usr/local/bin (uses sudo if needed)
zsh /tmp/xfsnap install

# configure this host — autodetects snapshot dirs from the running validator,
# asks for the peer's ssh short name, writes ~/.config/xfsnap/config
xfsnap config interview
```

`config interview` proposes the snapshot dirs it reads from your live
`agave-validator` process; press Enter to accept. When it asks for the **peer**,
give the ssh short name of the *other* host (`backup`). Prefer non-interactive?
Set the keys directly:

```sh
xfsnap config set snapdir /mnt/ledger   # where snapshot-<slot>-*.tar.zst live
xfsnap config set incdir  /mnt/ledger   # where incremental-*.tar.zst live (often the same dir)
xfsnap config set peer    backup        # ssh short name of the other host
```

### 2. On the second host (`backup`) — do the same

Repeat the exact same three steps on the other machine. Everything is
symmetric; just set its `peer` back to the first host:

```sh
curl -fsSL https://raw.githubusercontent.com/<you>/xfsnap/main/xfsnap -o /tmp/xfsnap
zsh /tmp/xfsnap install
xfsnap config interview                 # ... and set peer = primary
```

> You need **at least two configured hosts**. There's no central config or host
> list — each box only describes *itself* (its snapshot dirs + its peer). When
> you transfer, the source discovers the destination's dirs by asking it over
> ssh (`ssh peer xfsnap config get snapdir`).

### 3. Confirm both ends are ready

From either host:

```sh
xfsnap check
```

It verifies your local dirs exist, that the peer is reachable over ssh, that
xfsnap is installed there, and that the peer is configured — printing exactly
what to fix if not:

```
==> xfsnap 0.2.0 setup check
ok: local snapdir = /mnt/ledger
ok: local incdir = /mnt/ledger
ok: ssh 'backup' reachable
ok: 'backup' has xfsnap 0.2.0
ok: 'backup' snapdir = /mnt/ledger
ok: ready to transfer
```

### 4. First transfer

```sh
xfsnap put            # push newest full snapshot: here -> peer  (8 streams, resumable)
```

### What if a host isn't configured yet?

xfsnap tells you precisely, at `check` time and at transfer time. If the peer
has no config, or xfsnap isn't installed there, you'll get e.g.:

```
fail: 'backup' has xfsnap but is not configured   ->  ssh backup xfsnap config interview
fail: xfsnap not installed on 'backup'            ->  install it there (copy the file, run: xfsnap install)
```

Just run the suggested command on (or against) that host and re-run
`xfsnap check`. Nothing transfers until both ends are configured.

> **ssh user must be consistent.** Config is per-user (like `solana config`).
> Whatever user your inter-host ssh lands as on the peer must be the user that
> ran `xfsnap config` there. On a validator pair that's normally the same
> service account on both ends, so this is automatic.

## Usage

```
xfsnap <subcommand> [options]

  get   g                    pull newest full snapshot: peer -> here
  getinc  gi                 pull newest incremental:   peer -> here
  put   p                    push newest full snapshot: here -> peer
  putinc  pi                 push newest incremental:   here -> peer
  transfer  trf  SRC DST     push newest full        SRC -> DST  (ssh short names)
  transferinc trfi SRC DST   push newest incremental SRC -> DST
  clean  cl                  remove leftover .xfsnap staging on this host
  config ...                 interview | get | set | unset | list | path
  check [PEER]               verify this host + peer are ready to transfer
  install [PREFIX]           self-install (default /usr/local/bin)
  version | help

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

### Failover flow

On the healthy box, push the freshest full snapshot to the backup, then keep the
incremental fresh until it boots:

```sh
xfsnap put              # 8-stream full snapshot -> peer  (resumable)
xfsnap putinc --watch   # ship each new incremental as it lands
```

Pulling from the backup's side instead? Use `get` / `getinc`. Orchestrating from
a third box (a laptop) works too — it hops to the source so the bytes flow
source→dest directly instead of trom­boning through you:

```sh
xfsnap transfer primary backup
```

### Cold start with `--no-snapshot-fetch`

Booting from a full snapshot, the validator spends ~10-15 min rebuilding
storages before it loads an incremental — and you want that incremental as fresh
as possible when rebuild finishes. Run `xfsnap putinc --now --watch` on the
source for the whole window (the dest always holds a ~1-min-old incremental), or
fire `xfsnap putinc --now` by hand when rebuild is nearly done.

### The pre-snapshot timing guard

Agave writes a full snapshot every `--full-snapshot-interval-slots` (default
**100000** ≈ 11h). `xfsnap` reads the newest snapshot's slot from its filename,
gets the chain tip from `solana slot`, and if a fresh full is due within the
hour it warns and asks whether to proceed. `--yes` skips the prompt;
non-interactive runs abort by default. (If the source validator is down and
`solana slot` fails, the guard is skipped — correct, since no new snapshot is
coming.)

## How it works

```
source                                   destination
------                                   -----------
dd if=snap skip=off count=len  ──ssh──▶  dd of=snap.part seek=off conv=notrunc
        × N streams in parallel          (pre-allocated to full size; chunks
                                          land at their offsets, no reassembly)
                                         ledger records each verified chunk
                                         zstd -t, then atomic rename -> snap
```

Config: `${XFSNAP_CONFIG:-~/.config/xfsnap/config}`. Tunables (`streams`,
`chunk`, `full_interval`, `cipher`, `solana`) can be set in config or per-run
with flags.

## License

MIT — see [LICENSE](LICENSE).

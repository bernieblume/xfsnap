# xfsnap

**Fast, resumable transfer of Solana (Agave) snapshots between your own validator hosts.**

## The problem

You need to start a validator. You don't have a fresh snapshot.

Maybe it's a brand-new box. Maybe your backup died and has to come back. Maybe
you moved identity to the secondary and now the cold primary has to catch up.
Same wall either way.

The "just let it fetch on boot" path is a trap:

- The full snapshot is 100 GB+. The download crawls. Peers throttle you.
- Then it pulls an incremental on top — slow too. You come up **1000+ slots behind.**
- Worst case: the full is already out of date before it even finishes.

Meanwhile the snapshot you want is sitting on another box you own. Minutes old.
Right there. Copying it should be the easy part. It isn't:

- `scp` and `rsync` use **one TCP stream**. One stream can't fill a fat,
  long-distance link — the bandwidth-delay product caps you at a fraction of
  your pipe, and the far colo throttles the flow.
- Incrementals drop about once a minute. Grabbing the freshest one at the right
  moment, by hand, is fiddly — you keep copying a stale one.
- "Just use bbcp / rclone." A config rabbit hole. Every. Single. Time.

You have the data. Moving it shouldn't be the hard part.

## What xfsnap does

Copies the freshest snapshot from a box you own to the one that needs it. Fast.
Resumable.

- **Fills the pipe.** Splits the snapshot into byte ranges and pushes them over
  **N parallel `dd | ssh dd` streams** (default 8), straight into a pre-allocated
  file on the far side. No reassembly. No double disk.
- **Resumes.** Died at 80 GB of 109? Re-run the same command. It ships only what's
  missing. A tiny ledger tracks progress and survives reboots on either end.
- **Never hands you a corrupt snapshot.** A chunk counts only if the receiver
  wrote the exact bytes. The finished file gets `zstd -t`-tested, then atomically
  renamed. `--verify` adds full end-to-end sha256.
- **Knows the snapshot clock.** Warns if a fresh full is about to drop, so you
  don't ship one that's already dying.
- **Streams incrementals just-in-time.** `putinc --watch` ships each new
  incremental the second it lands — the target stays ~1 minute behind the tip.
- **One file. Zero fuss.** No daemon, no deps beyond what a validator box already
  has (bash, coreutils, ssh, zstd).

It moves snapshots **between hosts you control, over ssh.** It's not a public
snapshot service and doesn't touch the cluster RPC (except one `solana slot` read
for the timing guard).

## Getting started

You need **two hosts that can already `ssh` to each other by short name** (from
`~/.ssh/config`) — e.g. `primary` and `backup`. xfsnap is one self-contained
file; you set it up on **both**. Requires `bash` 4+, GNU coreutils, `ssh`, and
`zstd` (all already on a validator box).

### 1. On the first host (`primary`)

```sh
# download + install to /usr/local/bin (sudo if needed)
curl -fsSL https://github.com/bernieblume/xfsnap/raw/main/install.sh | sh

# configure this host — autodetects snapshot dirs from the running validator,
# asks for the peer's ssh short name, writes ~/.config/xfsnap/config
xfsnap config interview
```

`config interview` proposes the snapshot dirs it reads from your live
`agave-validator` process; press Enter to accept. When it asks for the **peer**,
give the ssh short name of the *other* host (`backup`). It then **offers to set
up that peer for you** — installing xfsnap on `backup` and running its setup over
ssh — so you can do both hosts in one sitting (and skip step 2). Prefer
non-interactive? Set the keys directly:

```sh
xfsnap config set snapdir /mnt/ledger   # where snapshot-<slot>-*.tar.zst live
xfsnap config set incdir  /mnt/ledger   # where incremental-*.tar.zst live (often the same dir)
xfsnap config set peer    backup        # ssh short name of the other host
```

### 2. On the second host (`backup`) — or let step 1 do it

If you accepted the wizard's offer above, `backup` is already installed and
configured — skip to step 3. Otherwise, repeat the same steps on the other
machine (symmetric; set its `peer` back to the first host):

```sh
curl -fsSL https://github.com/bernieblume/xfsnap/raw/main/install.sh | sh
xfsnap config interview                 # ... and set peer = primary
```

> **Manual shortcut:** from a host that already has xfsnap, set up another in one
> command — `xfsnap interview backup` installs xfsnap on `backup` (asking first if
> it just needs an upgrade), then runs its interview over ssh.

> You need **at least two configured hosts**. There's no central config or host
> list — each box only describes *itself* (its snapshot dirs + its peer). When
> you transfer, the source discovers the destination's dirs by asking it over
> ssh (`ssh peer xfsnap config get snapdir`).

### 3. Confirm both ends are ready

From either host:

```sh
xfsnap doctor
```

It verifies your local dirs exist, that the peer is reachable over ssh, that
xfsnap is installed there, and that the peer is configured — printing exactly
what to fix if not:

```
==> xfsnap 0.2.0 doctor
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

xfsnap tells you precisely — from `xfsnap doctor` and at transfer time. If the
peer has no config, or xfsnap isn't installed there, you'll get e.g.:

```
fail: 'backup' has xfsnap but is not configured   ->  ssh backup xfsnap config interview
fail: xfsnap not installed on 'backup'            ->  install it there (copy the file, run: xfsnap install)
```

Just run the suggested command on (or against) that host and re-run
`xfsnap doctor`. Nothing transfers until both ends are configured.

> **ssh user must be consistent.** Config is per-user (like `solana config`).
> Whatever user your inter-host ssh lands as on the peer must be the user that
> ran `xfsnap config` there. On a validator pair that's normally the same
> service account on both ends, so this is automatic.

## Usage

```
xfsnap <subcommand> [options]

  get   g   [peer]           pull newest full snapshot: peer -> here
  getinc  gi [peer]          pull newest incremental:   peer -> here
  put   p   [peer]           push newest full snapshot: here -> peer
  putinc  pi [peer]          push newest incremental:   here -> peer
  transfer  trf  SRC DST     push newest full        SRC -> DST  (ssh short names)
  transferinc trfi SRC DST   push newest incremental SRC -> DST
  clean  cl [HOST]           remove leftover .xfsnap staging (here, or on HOST)
  interview [HOST]           interactive setup (here, or on a remote ssh HOST)
  config ...                 interview | get | set | unset | list | path
  doctor (check) [HOST]      check readiness (here, or on a remote ssh HOST)
  install [PREFIX]           self-install here (default /usr/local/bin)
  install HOST [PREFIX]      copy + install on a remote ssh host
  upgrade                    download + install the latest xfsnap from GitHub
  version (-V) | help

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

The management commands (`interview`, `doctor`, `clean`, `install`) take an
optional **`HOST`** to act on a remote box over ssh — so `xfsnap doctor backup`
checks `backup` without you typing `ssh backup xfsnap doctor`. The transfer
commands instead take a **`peer`** — the other end of the copy.

### Bring a box up

A box needs a snapshot. Push it from the box that has a good one:

```sh
# run on the box that HAS the snapshot
xfsnap put              # 8-stream full snapshot -> peer  (resumable)
xfsnap putinc --watch   # then keep the incremental fresh until it boots
```

Or pull it from the box that needs it:

```sh
# run on the box that NEEDS the snapshot
xfsnap get
xfsnap getinc --watch
```

`put`/`get` use your configured `peer` by default, but you can target **any**
set-up host by name — handy if you keep more than one backup:

```sh
xfsnap put backup-2      # push to a specific peer instead of the default
```

Driving from a third box (your laptop) works too. It hops to the source, so the
bytes flow source→dest directly instead of tromboning through you:

```sh
xfsnap transfer good-box needy-box
```

> An **orchestrator box needs no config of its own** — `transfer` names both
> ends explicitly, and the two endpoints describe themselves. (`config
> interview` there will say as much and let you skip.)
>
> **On macOS**, that orchestrating box needs **bash 4+** — the system bash is
> stuck at 3.2, so `brew install bash` first. (Linux validator hosts already
> ship bash 5.) If your shell can't find `xfsnap` right after install, start a
> new shell — or `rehash` (zsh) / `hash -r` (bash).

### Cold start with `--no-snapshot-fetch`

Booting from a full snapshot, the validator spends ~10-15 min rebuilding
storages before it loads an incremental — and you want that incremental as fresh
as possible when rebuild finishes. Run `xfsnap putinc --now --watch` on the
source for the whole window (the dest always holds a ~1-min-old incremental), or
fire `xfsnap putinc --now` by hand when rebuild is nearly done.

### Keeping hosts in sync

Update in place with `xfsnap upgrade` (pulls the latest from GitHub). Then push
the same build to the peer with `xfsnap install <peer>`.

The two ends don't have to match — for a direct `put`/`get` the peer just runs
plain `dd`/`zstd`, so version drift is harmless. When they do differ, `xfsnap
doctor` and every transfer print a non-blocking **version skew** warning that
points the right way: if the peer is *older*, `xfsnap install <peer>` pushes your
build to it; if it's *newer*, `xfsnap upgrade` updates you (so you never
accidentally downgrade the newer box). Add `--strict` to any transfer to abort
on a mismatch instead of warning.

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

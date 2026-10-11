# logos-bitcoind-ui

`bitcoind_ui` manages the Bitcoin node (Bitcoin Core) that `bitcoind_module` runs in-process:
start and stop it, watch it sync, change its settings per network, choose its Tor proxy and
whether it opens Core's RPC port to other programs, and read its log. Built on the Logos Design
System, like the Zcash and Monero node apps it follows.

```bash
nix build .#install        # -dev variant, for Basecamp's standalone mode
nix build .#lgx
```

- **Status:** the state and last error, the block height against the best header, a progress
  bar from Core's verification progress during initial sync, outbound peers, uptime, the age of
  the last block, the filter index height, the prune height, size on disk, the cache in use and
  the version.
  - **Synchronized** needs an outbound peer and a tip under an hour old: Core's initial-sync
    flag stays false on a node that has lost its peers, the trap the Monero node's
    `synchronized` flag set.
  - A node out of initial sync with peers but an older tip reads **Stalled · N hours behind**;
    with no peer, **No peers**.
  - A node that has no peer yet, during initial sync or in its first five minutes, reads
    **Waiting for peers**. Regtest reads **Local chain**.
- **Stop** goes through `bitcoind_module`'s `stop()`, which writes the UTXO cache first: the
  card shows "Writing the chain state to disk…" with the seconds so far, then "Stopping…".
- **Disk:** before a mainnet start the view says, and asks: pruned with block filters the node
  keeps about 30 GB, but its first sync downloads every block, about 774 GB, roughly 43 hours
  over Tor at 5 MB/s (an estimate).
- **Settings**, per network, applied on the next start and locked while the node runs: data
  directory, prune target, the cache during initial sync (300 MiB once a run has reached the
  tip), mempool size, the Tor proxy, up to eight peers of one's own, and log categories.
  Without a proxy the view warns that the node goes over clearnet.
- **Open to other programs:** `exposeRpc` is off by default and turns on only through a
  warning: Core's RPC server on 127.0.0.1, cookie authentication, the wallet's read methods and
  `sendrawtransaction` only, but reachable by any program on this computer and by web pages
  in a browser on it. The status card says when the port is open. The wallet never needs it.
- **Log:** the last 80 lines of `debug.log`.

The view polls `status()` and the log tail every 2 s, and applies `bitcoindStateChanged` as it
arrives: the event marks state changes, while blocks and peers move between them.

## Intents

The app **provides** `bitcoin.node.configure` (handoff). A request may carry
`{"network": "mainnet"}`; if the node is stopped the view switches to that network.

## Checks

```bash
qmllint -I <qt qml> -I <logos-design-system>/src/qml -W 0 --unqualified disable src/qml/Main.qml
QT_QPA_PLATFORM=offscreen qml -I <qt qml> -I <logos-design-system>/src/qml ci/construct.qml   # VIEW-READY
QT_QPA_PLATFORM=offscreen qml -I <qt qml> -I <logos-design-system>/src/qml ci/states.qml      # STATES-OK
doctests/run.sh    # Basecamp's standalone mode, a regtest node, offline
```

`ci/states.qml` drives the pure `syncState`/`syncLabel` through every status a live node will
not hold on demand. CI runs the build, the secret-PROP rule, these three checks and the Windows
cross build. The doctest marks its platforms: on Windows the nix step gives way to staged
cross builds (Basecamp's `app-standalone-portable`, both `install-portable` trees), and the rest
runs under Git Bash. Its Windows half passed on Windows 10.0.26200 on 2026-10-11: 21 of 21
actions, every screenshot rendered. The doctest opens the app in Basecamp's standalone mode with
`bitcoind_module` beside it, starts and stops a regtest node, and checks the mainnet notice and
the RPC warning.

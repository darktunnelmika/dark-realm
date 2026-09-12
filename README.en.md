# DARK REALM PRO

[فارسی](README.fa.md) · [English](README.md)

```text
╭──────────────────────────────────────────────────────────────────╮
│ ██████╗  █████╗ ██████╗ ██╗  ██╗                                │
│ ██╔══██╗██╔══██╗██╔══██╗██║ ██╔╝                                │
│ ██║  ██║███████║██████╔╝█████╔╝                                 │
│ ██║  ██║██╔══██║██╔══██╗██╔═██╗                                 │
│ ██████╔╝██║  ██║██║  ██║██║  ██╗                                │
│ ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝                                │
│ R E A L M  ·  Native high-performance relay                     │
╰──────────────────────────────────────────────────────────────────╯
```

**DARK REALM PRO v1.0.0** is a standalone Bash management layer for the upstream [Realm](https://github.com/zhboner/realm) relay core.

It keeps Realm's native architecture and configuration model. The DARK layer adds a consistent operator experience: guided Iran/Kharej setup, versioned Pair Codes, multi-port mappings, TLS certificate automation, per-tunnel systemd services, diagnostics, real tunnel throughput testing, updates, backups and rollback.

> Same DARK operator experience; native Realm logic underneath.

Maintainer and support: **@mikakhadm**

## Architecture

Realm is a direct relay, not a Backhaul-style reverse/multiplexed tunnel.

```text
USER
  │
  ▼
IRAN Realm Edge
public user-facing ports
  │
  │ TCP / TLS / WS / WSS
  ▼
KHAREJ Realm Gateway
transport listener ports
  │
  ▼
127.0.0.1:<Xray / panel / application port>
```

The Iran Edge creates a `DR1` Pair Code. Paste that code into the Kharej Gateway setup. Pair Codes contain validated deployment metadata only—never private keys or passwords.

## Quick installation

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/darktunnelmika/dark-realm/main/install.sh)
```

Run it later with:

```bash
darkrealm
```

Supported primary platforms:

- Modern Linux on `amd64/x86_64`
- Modern Linux on `arm64/aarch64`
- `apt`, `dnf`, `yum`, and `apk` dependency installation where feasible

The manager downloads the full Realm release build, verifies the GitHub-provided SHA-256 digest, checks the binary version and installs it atomically. The initial validated upstream core is **Realm v2.9.6**.

## Main menu

```text
SETUP
  [1] Core
  [2] New Tunnel — IRAN
  [3] New Tunnel — KHAREJ

OPERATE
  [4] Manage Tunnels
  [5] Dashboard
  [6] Diagnostics

MAINTENANCE
  [7] Update
  [8] Backup / Restore
  [9] Uninstall
```

## Native transports

| Transport | Domain | Certificate | Typical use |
|---|---:|---:|---|
| TCP | No | No | Lowest overhead and highest raw throughput |
| TLS | Yes | On Kharej Gateway | Encrypted backbone |
| WS | Host + Path | No | WebSocket transport |
| WSS | Yes + Host + Path | On Kharej Gateway | WebSocket over trusted TLS |

Realm transport behavior comes from its native Kaminari transport support. The manager does not invent Backhaul-specific mux, pool or channel parameters.

### TLS placement rule

The certificate belongs to the endpoint running Realm `listen_transport`. In the standard DARK Realm topology, that endpoint is the **Kharej Gateway**.

When TLS or WSS is imported on Kharej, the script automatically opens the certificate flow:

```text
[1] Select an existing certificate
[2] Get a Let's Encrypt certificate now
[3] Create a self-signed certificate (test mode only)
[4] Enter certificate/key paths manually
```

The certificate manager:

- Discovers DARK, Let's Encrypt and common panel certificate pairs
- Verifies that certificate and private key match
- Validates SAN/wildcard hostname matching and expiration
- Checks domain DNS against the current Gateway
- Detects the exact service occupying port 80
- Installs `acme.sh` only when issuance is requested
- Stores managed copies under `/etc/dark-realm/certs/<domain>/`
- Uses a renewal reload hook that restarts only dependent DARK Realm tunnels
- Keeps private keys out of Pair Codes, terminal summaries and diagnostics exports

Trusted TLS verification is the production default. Self-signed mode is explicitly test-only and adds client-side `insecure`.

## Multi-port mappings

One logical DARK Realm tunnel can contain many native Realm `[[endpoints]]` entries.

Accepted formats:

```text
443
443,2053,2083,8443
2000-2100
443>8000,2053>8000,8443>8443
```

Canonical meaning:

```text
public-port > kharej-target-port @ kharej-backbone-port
```

The manager normalizes mappings, rejects duplicates, detects port conflicts and limits expansion to 256 endpoints by default.

## Performance profiles

Profiles change real Realm and systemd values only.

| Profile | Purpose |
|---|---|
| Stable | Conservative timeouts and restart behavior for unstable routes |
| Balanced | Safe general default |
| Low Ping | Faster keepalive and lower connect timeout |
| Turbo | High file-descriptor and connection capacity |
| Custom | Validated manual values |

Applied values include Realm TCP connect timeout, keepalive interval/probes, log level, systemd `LimitNOFILE` and restart delay.

## Tunnel management

Each tunnel receives an independent config and service:

```text
/etc/dark-realm/tunnels/turkey/config.toml
/etc/dark-realm/tunnels/turkey/meta.conf
dark-realm@turkey.service
```

Management includes:

- Start, stop and restart
- Pair Code display on Iran and import on Kharej
- Port mapping, profile, endpoint and transport updates
- TLS certificate replacement
- Scheduled restart timers
- Config display and fingerprint
- Live/recent logs and kernel connection inspection
- Transactional regeneration with automatic rollback
- Per-tunnel backup and restore
- Guarded manual TOML editing
- Safe deletion while preserving shared certificates

## Dashboard and diagnostics

The dashboard reports:

- Service state, PID and uptime
- Role, transport, profile and endpoint count
- Established sessions
- Kernel-derived RX/TX rates and totals on tunnel sockets
- TLS domain and remaining certificate days

Diagnostics include:

- Local service/process/listener checks
- Realm TOML structural validation
- Gateway TCP latency samples
- TLS SNI/chain verification
- Target listener checks
- Certificate/key/SAN/expiry checks
- Configuration fingerprint
- Redacted diagnostic exports

### Real tunnel throughput test

The speed helper does not run a generic Internet speed test.

1. On the Kharej Gateway, start **Tunnel throughput**. It creates a one-use Realm listener plus an `iperf3` responder and prints a `DRS1` code.
2. On the Iran Edge, open **Tunnel throughput**, paste the `DRS1` code and run the test.
3. The temporary processes exit and clean themselves after the test.

The resulting throughput crosses the selected Realm transport.

## Security model

- Pair Codes and `meta.conf` are parsed strictly as data and are never shell-sourced.
- Every accepted field has a whitelist and validator.
- Pair Code checksums detect corruption; they are not presented as authentication.
- Control characters, unsafe paths and shell injection payloads are rejected.
- Temporary files use `mktemp`.
- Core downloads require HTTPS and a GitHub release SHA-256 digest.
- Binary and config replacements are atomic where possible.
- Failed updates and config changes restore the last working state.
- systemd applies high file-descriptor limits and defensive hardening.
- Private keys are mode `0600` and excluded from normal backups by default.
- Destructive actions require explicit typed confirmation.

See [SECURITY.md](SECURITY.md) for reporting and threat-model details.

## Backup and uninstall behavior

Full backup defaults to excluding private keys. Exporting keys requires a separate explicit confirmation.

Uninstall offers three scopes:

1. Manager command only
2. Tunnels and Realm core, while preserving certificates
3. Full DARK Realm cleanup

The manager does not remove unrelated panel files, tunnel services or firewall rules.

## Server paths

```text
/etc/dark-realm/
├── tunnels/<name>/
│   ├── config.toml
│   ├── meta.conf
│   └── backups/
├── certs/<domain>/
│   ├── fullchain.pem
│   └── privkey.pem
├── runtime/
├── backups/
├── core.version
└── update.url

/usr/local/bin/realm
/usr/local/bin/darkrealm
/etc/systemd/system/dark-realm@.service
/etc/systemd/system/dark-realm-restart@.service
/etc/systemd/system/dark-realm-restart@.timer
```

## Development and tests

```bash
bash -n dark-realm.sh install.sh
./tests/test.sh
shellcheck --severity=error -e SC1090 dark-realm.sh install.sh tests/test.sh
```

The regression suite covers mapping parsing, Pair Code tampering/injection, safe metadata parsing, native TCP/WSS TOML generation, certificate/key matching and SAN validation.

## Upstream and license

Realm is developed independently by its upstream maintainers. DARK REALM PRO is an independent management wrapper and is not an official Realm project.

Both the manager and upstream Realm are distributed under the MIT License. See [LICENSE](LICENSE).

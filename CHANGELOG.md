# Changelog

All notable changes to DARK REALM PRO are documented here. The project follows Semantic Versioning.

## [1.0.0] - 2026-09-12

### Added

- Native Realm management wrapper with the shared DARK terminal UI.
- Guided Iran Edge and Kharej Gateway creation.
- Versioned `DR1` Pair Code with strict field validation and corruption checksum.
- Native TCP, TLS, WS and WSS Realm transport generation.
- Multi-port/range/many-to-one mapping expansion into Realm `[[endpoints]]`.
- Stable, Balanced, Low Ping, Turbo and Custom performance profiles using real Realm/systemd values.
- Full Realm core installer for verified GitHub release assets with SHA-256 validation and rollback.
- Per-tunnel systemd services and optional scheduled restart timers.
- TLS manager with certificate discovery, cert/key/SAN validation, Let's Encrypt issuance through `acme.sh`, self-signed test mode and renewal reload hooks.
- Per-tunnel management, config fingerprinting, backups, guarded TOML editing and transactional rollback.
- Dashboard with service, session, TLS and best-effort socket traffic information.
- Diagnostics with TCP latency, TLS handshake, target/listener checks, redacted export and live logs.
- One-use `DRS1` Realm + iperf3 helper for measuring throughput through the selected tunnel transport.
- Full backup/restore and scoped uninstall behavior.
- Security regression tests and GitHub Actions CI.

### Security

- Pair Codes and metadata are parsed as whitelisted data and are never evaluated by a shell.
- Temporary files use `mktemp`.
- Core downloads require HTTPS and a GitHub-provided SHA-256 digest.
- Private keys are omitted from Pair Codes, diagnostics and default backup archives.
- Destructive actions require explicit typed confirmation.

[1.0.0]: https://github.com/darktunnelmika/dark-realm/releases/tag/v1.0.0

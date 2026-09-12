# Security Policy

## Supported versions

| Version | Supported |
|---|---|
| 1.0.x | Yes |
| Older | No |

## Reporting a vulnerability

Do not publish working exploit details in a public issue.

Contact the maintainer through **@mikakhadm** and include:

- Affected DARK REALM PRO version
- Operating system and architecture
- Reproduction steps
- Security impact
- Suggested mitigation, when available

Secrets, private keys, Pair Codes from production systems, server IP credentials and full diagnostic archives must be redacted before sharing.

## Threat model

DARK REALM PRO is a privileged server-management script. It protects the main untrusted input paths as follows:

- `DR1` and `DRS1` codes have strict size limits, checksums, known-field whitelists and field-level validation.
- `meta.conf` is parsed as data. It is never sourced or evaluated.
- TOML and transport values reject control characters and are escaped before generation.
- Core assets require HTTPS and a GitHub release SHA-256 digest.
- Updates are syntax/marker checked and retain rollback copies.
- Certificate and private-key pairs are cryptographically matched.
- TLS hostnames are checked against SAN/wildcard data.
- Private keys are not included in Pair Codes or normal diagnostics.
- Default full backups exclude private keys.

A Pair Code checksum detects accidental or malicious modification, but it is not a cryptographic authentication mechanism. Transfer Pair Codes through a trusted channel.

## Operational recommendations

- Use trusted TLS certificates in production.
- Keep self-signed/insecure mode limited to controlled testing.
- Restrict SSH and server-management access.
- Review exposed public and backbone ports.
- Keep the manager and Realm core updated through verified release paths.
- Protect any backup archive that explicitly includes TLS private keys.

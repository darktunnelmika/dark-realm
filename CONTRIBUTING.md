# Contributing

1. Preserve Realm's native behavior. Do not add Backhaul-only or imaginary core options.
2. Preserve the shared DARK management UX unless a change is intentionally coordinated across all DARK tunnel managers.
3. Run `bash -n dark-realm.sh install.sh` and `./tests/test.sh`.
4. Add regression coverage for parsers, Pair Codes, generated TOML and rollback-sensitive behavior.
5. Never place production credentials, private keys or real server access data in commits or issues.

Pull requests should explain the operational problem, the exact Realm capability used and the rollback behavior.

## Git Safety

- Do not revert, commit, or perform destructive git operations unless the user explicitly tells you to do so.
- Treat commands like `git reset`, `git checkout --`, `git restore`, rebases, force-pushes, and history rewrites as destructive unless the user explicitly requests them.
- If cleanup or rollback seems helpful, stop and ask instead of doing it implicitly.

## Build Validation

- After changing Zig source, do not trust `zig-out/bin/boon-zig` to reflect the latest code unless you explicitly rebuilt and verified that binary for this exact check.
- Prefer `zig build run -- ...` for validation commands during active iteration so the current code is used.
- If you intentionally use `zig-out/bin/boon-zig`, state that choice and why it is safe.

## Tooling Preference

- Use Zig for repo automation, helper scripts, data extraction, and expectation updates.
- Use shell only for simple command orchestration and one-liners.
- Do not use Python in this repo unless the user explicitly asks for it.

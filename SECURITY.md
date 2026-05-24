# Security policy

`codex-ubuntu` is an unofficial Ubuntu launcher project, but it still handles:

- local auth-bearing URLs
- process reuse and process termination
- local web runtimes on loopback
- desktop launch surfaces

That means security bugs here are real bugs, even when the runtime is local-only.

## Supported focus

The current security focus is:

- launcher stop and reuse safety
- token redaction and log hygiene
- XDG path handling
- desktop integration correctness

## Reporting a vulnerability

Please do not open a public issue for a vulnerability that could expose user data, local tokens, or unsafe process control behavior.

Instead:

1. describe the issue privately to the maintainer
2. include affected version or commit
3. include reproduction steps
4. include expected versus actual behavior

If you are not sure whether something is security-sensitive, err on the side of private disclosure first.

## High-priority bug classes

- stale PID reuse that can kill unrelated processes
- token leakage into logs or persistent browser history beyond what the runtime already requires
- loopback runtime unexpectedly binding beyond localhost
- unsafe provider metadata trust
- desktop entry or protocol handler behavior that enables unintended command execution

## Out of scope

The repository does not claim to secure proprietary upstream services or official upstream binaries beyond the local launcher logic it owns.

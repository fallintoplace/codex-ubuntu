# Contributing

Thanks for helping make `codex-ubuntu` better.

This project is still early, but it is not casual about desktop-launch safety. Small-looking changes in runtime discovery, PID handling, browser fallback behavior, or future Electron intake can break trust fast, so please read the docs before editing core flows.

## Before you open a pull request

Read:

- [README.md](README.md)
- [docs/architecture.md](docs/architecture.md)
- [docs/security.md](docs/security.md)
- [providers/contract.md](providers/contract.md)

## Local development

Recommended environment:

- Ubuntu 22.04 or 24.04
- `bash`
- `python3`
- `curl`
- `xdg-utils`

Useful commands:

```bash
make test
make build-deb
make install-local
```

## Contribution priorities

Good first contributions:

- Electron-first repo shaping
- launcher hardening
- test coverage improvements
- desktop integration polish
- packaging cleanup
- documentation that reduces ambiguity

Changes that need extra care:

- process stop or reuse logic
- provider contract changes
- token handling or logging changes
- anything that touches auth, runtime metadata, port ownership, or desktop identity

## Style expectations

- prefer simple Bash over clever Bash
- keep paths XDG-aware
- avoid user-specific assumptions
- document why a safety rule exists when it is not obvious
- favor honest docs over ambitious docs

## Pull request checklist

- explain the user-facing problem clearly
- mention any security or runtime-behavior impact
- include tests when behavior changes
- call out assumptions and limitations directly

If a proposed change makes the repo look better but reduces truthfulness, it is probably the wrong trade.

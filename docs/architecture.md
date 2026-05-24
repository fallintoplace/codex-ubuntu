# Architecture

## Positioning

`codex-ubuntu` is Ubuntu-first and implementation-conscious.

The repository should not assume:

- one browser
- one user-specific install path
- one long-term runtime strategy
- one future packaging outcome

The repository should define stable boundaries and implement only the parts that are mature enough to own today.

## Layer model

```text
user
  -> desktop integration
  -> launcher
  -> runtime provider
  -> auth/state/logging
  -> packaging/install path
```

## Current implemented architecture

### V1

- launcher-first
- browser-shell runtime provider
- local install flow
- Debian packaging skeleton
- smoke tests and CI

### Future track

- optional local repackager path if legal and maintenance tradeoffs are acceptable

The local repackager path is intentionally exploratory. It is not assigned to a committed version milestone yet.

## Boundaries

### Launcher

Responsibilities:

- discover runtime and browser commands
- manage XDG config/cache/state
- own process-safety rules
- own app-window launch behavior
- own local health checks and stop behavior

Should not:

- hardcode personal machine paths
- assume all providers share the same startup semantics
- smuggle Debian packaging logic directly into runtime control

### Runtime provider

The launcher talks to a provider contract.

Implemented provider:

- `browser-shell`

Planned providers:

- `app-server`
- `desktop-payload`

The provider contract is defined in [providers/contract.md](../providers/contract.md).

### Desktop integration

Responsibilities:

- `.desktop` entry
- icon registration
- GNOME/BAMF-friendly identity
- protocol handler integration when ready

### Packaging

Primary package target:

- `.deb`

Secondary or later:

- AppImage

Deferred:

- Snap
- Flatpak

## Why launcher-first

Launcher-first is the strongest v1 because it delivers a real Ubuntu app experience without pretending we already own:

- a stable upstream desktop repackager
- a final upstream asset redistribution model
- a mature updater pipeline

It also lets the repo publish a concrete product now instead of a pure design memo.

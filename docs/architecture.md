# Architecture

## Positioning

`codex-ubuntu` is Ubuntu-first and Electron-first.

The repository should not assume:

- one user-specific install path
- one future asset or distribution model
- one compatibility patch strategy that never changes

The repository should assume one important thing now:

- the primary UX target is a real Ubuntu desktop app, not a browser wrapper

## Layer model

```text
user
  -> desktop integration
  -> desktop payload (primary target)
  -> fallback launcher
  -> runtime/provider contract
  -> auth/state/logging
  -> packaging/install path
```

## Current architecture state

### Product direction

- Electron-first desktop payload
- `.deb` as the primary package target
- browser fallback retained as recovery mode

### Implemented today

- repo-owned local Electron launcher wrapper
- secure browser-shell fallback launcher
- local install flow
- local Electron install flow
- Debian packaging skeleton
- smoke tests and CI

### In progress

- Electron-first repo structure
- desktop-payload migration plan
- compatibility boundary between Ubuntu patches and upstream payload

### Optional later

- `app-server` provider

## Boundaries

### Electron desktop payload

Responsibilities:

- own the real app-window experience
- preserve Ubuntu desktop identity
- launch the packaged desktop runtime predictably
- define the narrow Linux-specific patch and compatibility layer

Should not:

- absorb unrelated packaging concerns into UI patching
- hide where upstream payload behavior ends and Ubuntu-specific behavior begins
- quietly depend on one personal machine setup

Current implementation status:

- repo-owned local launcher wrapper is in place
- payload ownership is still external

### Fallback launcher

Responsibilities:

- stay available as a recovery path
- discover runtime and browser commands
- manage XDG config/cache/state
- own process-safety rules for browser-shell mode
- own local health checks and stop behavior

Should not:

- pretend to be the main product experience
- take over the Electron roadmap
- smuggle Debian packaging logic directly into runtime control

### Runtime/provider contract

The fallback launcher and any future desktop-payload control surface should talk to a stable provider contract.

Implemented provider:

- `browser-shell` fallback

Primary target provider:

- `desktop-payload`

Optional later:

- `app-server`

The provider contract is defined in [providers/contract.md](../providers/contract.md).

### Desktop integration

Responsibilities:

- `.desktop` entry
- icon registration
- GNOME/BAMF-friendly identity
- protocol handler integration when ready
- alignment between shipped window class and launcher identity

### Packaging

Primary package target:

- `.deb`

Secondary or later:

- AppImage

Deferred:

- Snap
- Flatpak

## Why Electron-first

Browser-first was useful for hardening launcher safety, but it hit the exact ceiling people complain about:

- it feels like a browser wrapper
- when it breaks, it breaks like a browser wrapper
- it does not earn the same trust as a real desktop app

Electron-first is now the right main path because:

- the working Ubuntu desktop reference already proves the UX people actually want
- the app identity, dock behavior, and window model are materially better
- browser mode still remains valuable as fallback and recovery instead of pretending to be the main event

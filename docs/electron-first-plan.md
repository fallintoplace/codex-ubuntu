# Electron-first plan

## Goal

Turn `codex-ubuntu` into an Ubuntu desktop project whose main experience is an Electron app, while keeping the browser launcher as fallback and recovery mode.

## Working reference areas

The current working Ubuntu desktop reference already breaks into a few useful layers:

1. desktop entry and window identity
2. small user-facing launcher wrapper
3. real Electron start script
4. packaged Electron payload and resources
5. Ubuntu-specific compatibility and patch layer
6. Debian packaging and update hooks

Those layers are the right intake boundary for this repo too.

## What this repo should own

### `electron/`

The future desktop payload structure:

- intake notes
- launcher chain
- compatibility patches
- packaging boundaries

### `launcher/`

The browser fallback launcher:

- recovery mode
- constrained-environment mode
- safety testbed for provider ownership rules

### `desktop/`

Shared desktop identity:

- `.desktop` templates
- icon naming
- window-class alignment
- protocol-handler expectations

### `packaging/deb/`

Ubuntu packaging:

- fallback utility today
- desktop payload package path later

## First implementation slices

### Slice 1

Import the desktop launch chain shape:

- desktop entry expectations
- launcher wrapper expectations
- Electron start-script boundaries

Status:

- repo-owned local launcher wrapper is implemented
- same-identity local dogfooding with rollback is implemented
- minimum payload intake is implemented
- full payload intake is still pending

### Slice 2

Define the payload boundary:

- what belongs to upstream payload
- what belongs to Ubuntu compatibility code
- what belongs to this repo's packaging logic

### Slice 3

Lift in packaging and desktop integration:

- `.deb` package behavior
- window identity
- protocol handlers
- update-manager story

## Non-goal

The browser fallback should not keep dictating the repo's product story.

It stays because it is useful, not because it is the destination.

# Roadmap

## Phase 1

Electron-first pivot.

- Electron-first repo positioning
- repo-owned local Electron launcher wrapper
- browser fallback retained as recovery mode
- reference desktop component map
- desktop-payload migration plan
- launcher safety preserved while the product direction changes

## Phase 2

Desktop intake.

- adapt the working Electron launch chain into this repo
- bring over Ubuntu desktop identity and protocol handling
- define the compatibility patch layer explicitly
- start packaging the desktop payload path in `.deb` form

## Phase 3

Hardening and productization.

- updater strategy
- stronger installer polish
- multi-instance and warm-start behavior
- tighter packaging and release validation

## Fallback track

The browser fallback stays alive, but as fallback:

- recovery path when the Electron path is unavailable
- constrained-environment option
- launcher safety testbed

It is no longer the main product story.

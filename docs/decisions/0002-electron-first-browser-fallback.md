# 0002 Electron-first Ubuntu desktop with browser fallback

## Status

Accepted

## Context

The original repository foundation stayed implementation-agnostic on purpose.

That was useful while the project was still deciding whether a browser-first launcher could be a satisfying product. It also helped harden the runtime ownership model before the repo took on a heavier desktop path.

But the product conclusion is clearer now:

- the browser path is useful, but it feels second-class
- the working Ubuntu Electron desktop path is the experience people actually want to use daily
- keeping the browser wrapper as the main story would optimize the wrong thing

## Decision

`codex-ubuntu` becomes Electron-first.

That means:

- the main product target is a real Ubuntu desktop app
- the browser-shell provider stays in the repo as fallback and recovery mode
- the repo structure should make room for desktop payload intake, compatibility patches, and desktop packaging
- launcher safety work remains important because fallback paths and desktop payload helpers still need strong process ownership rules

## Consequences

### Positive

- the repo direction now matches the product experience people actually want
- browser mode can stay honest instead of pretending to be the destination
- desktop integration, packaging, and patching work can be scoped around a real target

### Negative

- maintenance cost goes up
- distribution and asset-rights questions become more important
- the current runnable implementation in this repo remains the fallback path until desktop payload work lands

# 0001 Ubuntu-first secure agnostic foundation

## Status

Superseded by 0002

## Context

The project needs a public-facing foundation before the final implementation path is settled.

There are multiple viable directions:

- secure browser-shell launcher
- CLI/App Server-backed Ubuntu client
- local desktop-payload repackager

Choosing one too early would hide tradeoffs instead of surfacing them.

## Decision

Start with a secure, Ubuntu-first, implementation-agnostic repository structure.

That means:

- launcher-first scaffolding
- security-first process model
- Debian packaging as the package target
- pluggable runtime/provider framing
- no assumption that repackaging is v1

## Consequences

### Positive

- faster to review
- lower chance of locking into a brittle path
- clearer public intent

### Negative

- less flashy than a concrete repackager prototype
- requires discipline to keep boundaries real

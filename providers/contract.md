# Provider contract

## Purpose

The project needs one stable contract so fallback runtime strategies and the future desktop-payload path can evolve without rewriting safety logic every time.

## Required launcher-facing capabilities

Every implemented provider must define:

1. how it starts
2. how it publishes runtime metadata
3. how it is health-checked
4. how launcher ownership is verified
5. how it should be stopped
6. how launcher-managed provenance is persisted across restarts

## Required runtime metadata

Structured metadata must be written to a provider-known path.

Required fields:

- `pid`
- `bind`
- `port`
- `startedAt`

Recommended fields:

- `provider`
- `tokenFile`
- `authDisabled`

Providers that expect safe reuse across launcher restarts should also support a launcher-managed provenance record, such as a persisted process fingerprint derived from the live runtime.

## Ownership verification rules

The launcher must verify:

1. the metadata file is parseable
2. the PID is live
3. the process command line matches the expected provider arguments
4. the live process start time still matches the trusted process provenance
5. the bind/port values match launcher expectations
6. the token file matches when token auth is used
7. the live process matches the last trusted launcher-managed provenance record

If any of these checks fail, the launcher must not kill the process.

## Provider statuses

### Implemented now

- `browser-shell` fallback

### Primary target

- `desktop-payload`

### Optional later

- `app-server`

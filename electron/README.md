# electron

This directory is the landing zone for the Electron-first desktop path.

Current contents:

- repo-owned local Electron launcher wrapper
- staged local Electron build bridge
- payload intake notes and import workflow
- payload patch-layer placeholder
- payload manifest docs

Planned contents:

- desktop payload intake notes
- compatibility patches
- packaging-specific desktop payload helpers

The browser launcher in `launcher/` remains useful, but it is fallback mode now.

Today the quickest real Electron path is:

1. `make build-electron-local`
2. `make install-electron-local`

That bridge still uses a pinned external Linux payload builder under the hood. The long-term goal is to absorb more of that logic into this repo over time.

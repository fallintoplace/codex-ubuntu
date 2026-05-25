# intake

This directory defines how a local desktop payload gets pulled into `codex-ubuntu` without pretending the repo already owns a full redistributable app bundle.

## Current scope

The minimum intake path copies only the pieces we need to reason about the desktop payload:

- `start.sh`
- `version`
- `resources/app.asar`
- `resources/codex-linux-build-info.json`
- `.codex-linux/codex-desktop.png`
- optional local build metadata when present

## Current command

```bash
make import-electron-payload
```

By default that imports from:

```text
$HOME/codex-desktop-linux/codex-app
```

Override the source root explicitly:

```bash
make import-electron-payload SOURCE_ROOT=/path/to/codex-app
```

## Output

The import writes:

- `electron/vendor/current/` for the copied payload slice
- `electron/manifest/current.local.json` for local provenance and checksums

Both are intentionally local and ignored by git.

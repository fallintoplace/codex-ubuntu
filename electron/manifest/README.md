# manifest

Payload provenance and intake metadata live here.

## Tracked docs

- this README
- `policy.json`
- `policy.example.json`

`policy.json` is the tracked build-verification policy used by the staged
Electron build flow.

It currently defines:

- the expected bridge-builder repository and pinned ref
- the allowed bridge modes
- required staged output files
- an optional fail-closed source DMG checksum slot

## Local generated files

- `current.local.json`

`current.local.json` is written by the intake script and ignored by git. It records:

- source payload root
- import timestamp
- version and upstream build metadata when available
- copied file sizes
- copied file SHA-256 digests

That gives the repo a real intake story without checking large proprietary payload files into version control.

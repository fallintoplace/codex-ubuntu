# Security

## Threat model

This project manages:

- local auth state
- local loopback services
- launcher-to-runtime trust
- desktop launch surfaces
- process reuse and process termination

That means a local-only Ubuntu launcher can still create serious damage if it stops the wrong process or leaks the wrong token.

## Security priorities

### P0

- do not kill unrelated processes
- do not trust stale PID files
- do not log token-bearing URLs or equivalent secrets
- do not expose runtime services beyond loopback by default

### P1

- verify runtime ownership before reusing it
- use XDG state/config/cache paths consistently
- avoid hardcoded personal path assumptions
- keep launcher state separate from provider-owned runtime metadata

### P2

- add locking to reduce double-start races
- improve port allocation race handling
- document and enforce redaction rules

## Provider/runtime contract requirement

The launcher may only reuse or stop a runtime when the provider exposes verifiable runtime metadata.

Minimum required fields:

1. `pid`
2. `bind`
3. `port`
4. `startedAt`

Optional but strongly preferred:

1. `tokenFile`
2. `provider`
3. `authDisabled`

For restart-safe reuse, the launcher should also persist its own provenance record for the trusted runtime, such as a process fingerprint captured after a healthy launch.

See [providers/contract.md](../providers/contract.md).

## Process ownership policy

The launcher must not stop a process only because:

- a PID file exists
- a PID is live

The launcher should require:

1. validated structured runtime metadata
2. matching process identity from `/proc/<pid>/cmdline`
3. matching bind/port expectations
4. matching token-file expectation when the provider supports token auth
5. matching launcher-managed runtime provenance captured from a previously trusted launch

If ownership cannot be proven, the launcher should refuse to kill the process.

The same rule applies to reuse. A healthy loopback service that cannot be tied back to a trusted launcher provenance record must be treated as unverified and must not be reused.

## Token handling policy

- bind locally by default
- avoid logging token-bearing URLs
- avoid printing login commands with live tokens into persisted logs
- prefer redacted auth hints in logs

## Path policy

Disallowed in production design:

- hardcoded `~/.nvm/...`
- hardcoded personal home paths
- hidden dependence on one user profile path

Preferred:

- `command -v`
- explicit overrides via environment
- XDG paths
- provider-owned metadata

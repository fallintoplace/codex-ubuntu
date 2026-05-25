# FAQ

## Is this a native Ubuntu app?

That is now the target.

Today the repo has two runnable local paths:

- a repo-owned Electron launcher wrapper for local dogfooding
- the browser fallback launcher

The fully self-contained Electron payload is still not owned by this repo yet.

## Why pivot away from browser-first?

Because browser-first was not good enough as the main experience.

It was useful for hardening launcher safety and packaging basics, but it still felt like a wrapper. The Electron path is the one that actually feels like a real desktop app in daily use.

## Is the browser path dead?

No.

It stays as fallback and recovery mode:

- when the Electron path is unavailable
- when a local environment is constrained
- when a simpler debug surface is useful

## Why Ubuntu-first instead of generic Linux-first?

Because support claims are expensive.

Ubuntu-first keeps the scope narrow enough to do packaging, desktop integration, and runtime assumptions properly before expanding outward.

## Is the Electron desktop-payload path now the main direction?

Yes.

But that does not mean the repository will suddenly become sloppy about distribution or patching boundaries. The main product direction is Electron-first, and the implementation still needs to stay explicit about what is upstream, what is Ubuntu-specific, and what rights are required to ship assets.

## What does secure mean here?

At minimum:

- the launcher should not kill unrelated processes
- stale runtime state should not be blindly trusted
- token-bearing URLs should not be sprayed into logs
- paths should not assume one specific personal machine layout
- desktop integration should not silently drift away from the actual running app identity

See [docs/security.md](security.md).

## Can this repo redistribute proprietary upstream assets?

Not by default.

The repository code and docs are MIT-licensed, but that does not grant rights to upstream proprietary desktop assets.

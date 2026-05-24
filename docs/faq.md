# FAQ

## Is this a native Ubuntu app?

Not yet in the fully native sense.

Today the implemented path is a launcher-first browser-shell experience with real Ubuntu desktop integration. It behaves more like an app than a random browser tab, but it is not pretending to be a finished upstream Linux desktop port.

## Why not jump straight to Electron or repackaging?

Because the maintenance bill is real.

A launcher-first path gives the project something honest and usable to ship now while keeping the heavier repackager path exploratory until the legal and maintenance tradeoffs are clearer.

## Why Ubuntu-first instead of generic Linux-first?

Because support claims are expensive.

Ubuntu-first keeps the scope narrow enough to do packaging, desktop integration, and runtime assumptions properly before expanding outward.

## Is the repackager path dead?

No.

It is deliberately kept as a future track rather than a committed milestone. That keeps the repo honest while still leaving room for a higher-fidelity desktop path later.

## What does secure mean here?

At minimum:

- the launcher should not kill unrelated processes
- stale runtime state should not be blindly trusted
- token-bearing URLs should not be sprayed into logs
- paths should not assume one specific personal machine layout

See [docs/security.md](security.md).

## Can this repo redistribute proprietary upstream assets?

Not by default.

The current repository code and docs are MIT-licensed, but that does not grant rights to upstream proprietary desktop assets.

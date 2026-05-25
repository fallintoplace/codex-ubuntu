# browser-shell provider

## Status

Implemented

## Runtime

The current implementation expects a runtime command that supports:

```text
codex-app-linux web --bind <ip> --port <port> --token-file <path>
```

The launcher does not bless a runtime by filename alone.

Instead, a runtime becomes manageable when:

1. it starts with the expected CLI shape
2. it writes valid runtime metadata
3. the live process arguments match the launcher expectations
4. the launcher captures and persists a process fingerprint for later reuse and stop checks

## Runtime metadata

The provider is expected to write a JSON file at:

```text
<token-file>.runtime
```

Expected fields:

- `pid`
- `bind`
- `port`
- `startedAt`
- `tokenFile`
- `authDisabled`

For the `browser-shell` provider, `tokenFile` is treated as required in practice because the launcher uses it as part of the ownership check.

## Launcher fingerprint

After a healthy launch, the launcher writes a managed fingerprint file at:

```text
${XDG_STATE_HOME:-$HOME/.local/state}/codex-ubuntu/runtime.fingerprint.json
```

That fingerprint is required for later reuse and stop behavior. A merely healthy loopback service without a matching launcher fingerprint is treated as unverified and will not be reused.

The current fingerprint includes:

1. `pidAtCapture`
2. `procStarttimeAtCapture`
3. `cmdlineSha256`
4. `procExe`

## Health check

The launcher currently checks:

```text
http://<bind>:<port>/__webstrapper/healthz
```

## Stop model

The launcher will only stop the runtime when:

1. runtime metadata is valid
2. `/proc/<pid>/cmdline` still matches the expected bind, port, and token file
3. `/proc/<pid>/stat` still matches the captured process start time
4. the live process still matches the stored launcher fingerprint

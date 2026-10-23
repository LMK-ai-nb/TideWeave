# JSON protocol v1

All input is strict JSON: duplicate decoded keys (including Unicode-escaped equivalents), unknown fields, fields belonging to another command/window kind, excessive depth, fractional or exponent number tokens are errors. A token such as `60.00000000000000001` is rejected instead of being rounded to 60. Plain integer tokens are intentional for interoperability and auditability. Missing optional fields use the documented defaults; explicit `null` is not a default.

## Replay request

```json
{
  "schema_version": 1,
  "config": {
    "window": { "kind": "session", "gap": 10 },
    "lateness": 20,
    "max_events": 5000,
    "max_operations": 10000
  },
  "commands": [
    {
      "id": "ingest-1",
      "kind": "transaction",
      "changes": [
        { "op": "put", "event": { "id": "e1", "key": "device-A", "at": 0, "value": 20 } }
      ]
    },
    { "id": "watermark-1", "kind": "watermark", "to": 12 },
    { "id": "correction-1", "kind": "transaction", "changes": [ { "op": "remove", "event_id": "e1" } ] }
  ]
}
```

Window variants:

| kind | required | optional |
| --- | --- | --- |
| `session` | `gap` | none |
| `tumbling` | `size` | `offset=0` |
| `sliding` | `size`, `slide` | `offset=0` |

Configuration defaults are `lateness=0`, `max_events=5000`, `max_operations=10000`, `trigger={"kind":"watermark"}`. A transaction contains 1..128 distinct event IDs. Event fields are all required. Window sizes are positive, slide is in 1..size, offset is in 0..<slide. IDs and keys contain 1..128 UTF-16 units; they are opaque strings, including Unicode and separators. Time units must be consistent within the engine; no unit conversion is performed.

The `trigger` object is optional and defaults to watermark-only. `{"kind":"count","threshold":N}` additionally marks a window `closing` once it holds N events; finality still depends on the watermark plus lateness.

Command kinds: `transaction` (1..128 put/remove mutations), `watermark` (advance the event-time watermark), and `forget` (advance the watermark and freeze every fact whose containing windows are all final, removing them from the active set). A `forget` command has the same shape as a watermark:

```json
{ "id": "forget-1", "kind": "forget", "to": 40 }
```

Frozen facts can no longer be inserted, replaced or removed, and are excluded from the `events` report; `frozen_count` reflects how many were frozen. Freezing is journaled, so checkpoint restore reproduces it exactly.

## Streaming (NDJSON)

`stream_json` drives one engine session from newline-delimited JSON. The first non-blank line is a session header `{"schema_version":1,"config":{...}}`; every later non-blank line is one command object. The output is one outcome line per command followed by a `{"summary":{...}}` line carrying `rows`, active `events`, `watermark`, `version` and `checkpoint`. Blank lines are ignored.

```sh
cat examples/session-stream.ndjson | node bin/tideweave.mjs stream
node bin/tideweave.mjs stream examples/session-stream.ndjson --checkpoint saved.json
```

Exit code is 0 when every command is accepted/duplicate, 1 when any is rejected/conflict, 2 for malformed input or IO. The whole stream is validated before any outcome is emitted, so a malformed line fails the run atomically instead of leaving a half-applied report. This lets any line-oriented producer (shell, `jq`, a Kafka consumer script, Python) drive the engine without writing MoonBit.

## Response

The report includes normalized `config`, ordered `steps`, final `rows`, sorted active `events`, the `frozen` count of sealed facts, `watermark`, `version`, and a checkpoint object. Each step includes command `id`, `status`, current committed `version`, `watermark`, `deltas`, and `message`.

| status | effect |
| --- | --- |
| `accepted` | atomically committed; version increases by one |
| `duplicate` | exact retry of a committed command; no repeated effects |
| `conflict` | committed command ID reused for different content; no effects |
| `rejected` | valid typed request rejected by state, finality or capacity constraints; no effects |

`delete` has `before` and no `after`. `upsert` has `after`, and has `before` when replacing a row. Absent option values are omitted, not encoded as null. Row identity is `(key,start,end)`. Each row contains `count`, `sum`, `min`, `max`, sorted `members`, and `phase=open|closing|final`. **`sum` is a decimal string.** The row retains all member IDs to make merges, splits and explanations verifiable.

Protocol errors return `TideError` through the typed library; the JavaScript bridge returns `{"schema_version":1,"error":{"code":"INVALID_INPUT","message":"..."}}`. Complete input validation precedes JSON replay. State-dependent rejections are valid report steps.

## Restart

Save the report's `checkpoint` object (or call `Engine::checkpoint`). It contains format, schema, normalized config, successful command journal, committed version and watermark. Derived rows are rebuilt, not trusted from a stored aggregate. Restore revalidates every command, checks all journal commands commit, and verifies the declared version/watermark.

```json
{ "schema_version": 1, "checkpoint": { "format": "tideweave-checkpoint", "schema_version": 1, "config": { "window": { "kind": "session", "gap": 10 } }, "commands": [], "version": 0, "watermark": 0 }, "commands": [] }
```

This is input for the `resume` CLI / `resume_json` API. The checkpoint is neither encrypted nor signed; do not treat it as an authenticity proof. The host owns storage, atomic file replacement, access control, and external consumer checkpoints.

Limits: input 8 Mi UTF-16 units, nesting 24, at most 10000 input commands, 5000 active events, 20000 materialized windows, 64 fixed-window fanout, 2 Mi canonical successful-journal units. Each engine can lower active-event and successful-command capacities. There is no unbounded execution or silent retention eviction.

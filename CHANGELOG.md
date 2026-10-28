# Changelog

## Unreleased

- Docs: replace the abstract database objection with three named settings, each paired with the mechanism that makes an UPDATE insufficient, plus an explicit list of cases where this library is the wrong tool.
- New example `examples/ad-billing.json`: late impression backfill and an invalid-traffic retraction in a billing window, driven by `fields.cents`. Wired into the browser laboratory as scenario 06.
- Fix the README quick-start snippet: `Event` literals now pass the required `fields` argument, and the example carries the `watts` field its `value_field` refers to.
- State the structured-event boundary (flat key/value, at most 32 entries) instead of implying arbitrary nesting.
- Docs: stop pinning commit counts in the audit line; point at `scripts/check_identity.mjs`.

## 0.2.3 — 2026-10-28

- Arbitrary structured events: `Event` carries sorted `fields` key/value attributes, preserved through reports, changelogs and checkpoints.
- Configurable measure: `Config.value_field` selects any structured integer field as the window measure, so events no longer need the fixed `value`.
- Deterministic ordering pinned to `lexical_compare` for all string sorts (row order, member provenance, field serialization), independent of core shortlex changes.
- Docs: repositioned as a generic embeddable event-time windowing library; new sections answer why a database cannot replace the correction layer.
- Tests: 70 MoonBit across wasm/wasm-gc/js, 10 Node CLI/ESM.

## 0.2.2 — 2026-10-24

- Fix `Engine::correctable`: it now returns false when any containing window is final (previously any active event returned true, although such a correction is rejected).
- Checkpoints record the `frozen` count and reject a mismatch; older checkpoints without the field still restore.
- The browser laboratory renders `forget` commands, filters frozen facts from the active count, and ships a `state-freeze` scenario covered by the Chromium check.
- Tests: 61 MoonBit across wasm/wasm-gc/js, 10 Node CLI/ESM.

## 0.2.1 — 2026-10-24

- Documentation-only release: refresh the published README and the `moon add` line to the 0.2.x API surface. Code is identical to 0.2.0.

## 0.2.0 — 2026-10-24

- Add user-defined aggregates: `Measure`, `measure_window`, built-in count/sum/min/max/avg with validated, unique measure names.
- Add `WatermarkTracker` (bounded out-of-orderness) plus `Engine::within_lateness` and `Engine::correctable`.
- Add `Trigger` (`Watermark` | `Count(n)`) wired through config, JSON and phase; triggers affect emission, not finality.
- Add `Command::Forget` to freeze finalized facts, free active capacity, reject later corrections and replay deterministically.
- Add NDJSON streaming: `stream_json`, `stream_ndjson`, `stream` CLI subcommand, `examples/session-stream.ndjson`.
- Expose `frozen` count in replay reports and stream summaries.
- Add `docs/PRIOR_ART.md`, `docs/WHY_CORRECTION.md`, `docs/HOST_GUIDE.md`; reposition README around the correction layer and document honest boundaries.
- Add `scripts/compare_naive.mjs`, a runnable counter-example showing boundary/count/sum/min/max drift without session rebuild.
- Tests: 58 MoonBit across wasm/wasm-gc/js, 10 Node CLI/ESM integration tests.

## 0.1.0 — 2026-10-20

- Introduce the original correction-aware MoonBit state machine for keyed event-time windows.
- Support offset fixed windows, session merge/split, atomic put/remove, finality protection and bounded success-ID deduplication.
- Add portable validated replay checkpoints and guarded downstream view application.
- Ship strict JSON adapters, Node CLI and interactive browser laboratory with three synthetic complete use cases.
- Include independent oracle tests, finality/adversarial tests, CLI/browser integration, reproducible benchmark, three-OS/four-target CI and redistribution notices.

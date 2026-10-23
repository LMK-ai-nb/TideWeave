# Changelog

## Unreleased — 2026-10-23

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

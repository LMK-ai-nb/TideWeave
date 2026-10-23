# Reproducible synthetic benchmark

Run `node scripts/build.mjs` and `node scripts/benchmark.mjs`. The script asserts final cardinalities before reporting numbers; raw samples are written to ignored `artifacts/benchmark.json`.

Measured 2026-10-20 on Windows x64, Intel Core i7-14650HX, Node v24.19.0, MoonBit compiler v0.10.16+b1a0e846e, release JavaScript bridge. A single process runs 3 warmups then 10 timed samples using `performance.now()`.

- 4096 synthetic events, 64 device keys, 32 transactions of 128 inserts.
- Session gap 10, lateness 20, per-key event timestamps separated by 8.
- Each sample includes strict input parsing, indexed candidate copying, affected-key session rebuilding, finality checks, before/after logging, replay checkpoint creation and **complete JSON serialization**.
- Final result: 4096 active events, 64 rows, version 32; output size 2,805,886 bytes.
- Sorted samples (ms): 62.9842, 77.5141, 78.4843, 81.9654, 83.0448, 85.1008, 85.2857, 88.9110, 101.3634, 116.3835.
- Median: **84.0728 ms**; maximum: **116.3835 ms**.

This sample intentionally measures the public JSON path rather than only a narrow arithmetic loop. Timing includes allocation and garbage collection and changes across platforms, toolchains, load and data distributions. It does not measure external IO, network delivery, recovery from machine failure, high-fanout worst cases, endless streams or arbitrary workload throughput. The separate semantic tests establish correctness; this benchmark does not substitute for them.

## NDJSON stream and state freeze (measured 2026-10-23)

Environment: Windows x64, Node 22.22.2, MoonBit compiler v0.10.17, release JavaScript bridge. Each figure is the median of 3 end-to-end runs of `node bin/tideweave.mjs stream <file>`, including Node startup and line parsing.

| Workload | Commands | Median |
| --- | --- | --- |
| 5000 events in 40 transactions (125 each), then watermark and `forget` | 42 | **604 ms** |
| 5000 events, one transaction per event, then watermark and `forget` | 5002 | 8316 ms |

- The first row is the intended usage: batch up to 128 mutations per transaction. It includes 5000 events, 5000 materialized windows, finalization, freezing and a full summary/checkpoint.
- The second row is the worst case, where every single event is its own command. Each command rebuilds the affected key's windows, so cost grows quadratically with per-key event count. This is the documented bounded-state trade-off, not a throughput claim.
- `scripts/compare_naive.mjs` measures the correctness difference, not speed: it shows the boundary/count/sum/min/max drift that occurs when retractions only adjust numbers.

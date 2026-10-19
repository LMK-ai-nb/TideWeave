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

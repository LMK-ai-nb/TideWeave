# TideWeave

A correction-aware event-time window engine implemented in MoonBit. It supports mutable event identities, atomic multi-record updates, session merging and deletion-induced splitting, explicit finality, guarded downstream changelogs and portable replay checkpoints.

[Live laboratory](https://lmk-ai-nb.github.io/TideWeave/) · [Chinese README](README.md) · [Protocol](docs/FORMAT.md) · [Semantics](docs/SEMANTICS.md)

Two events at 0 and 16 with gap 10 form separate sessions. A late event at 8 merges them; retracting that event splits them again. TideWeave recalculates boundaries, members, count/sum/min/max, rather than subtracting a number from a stale session aggregate. Each update either commits all candidate facts and materialized changes, or leaves state unchanged.

Features: tumbling/sliding/session windows; offset alignment with negative starts; insert/replace/retract by ID; atomic cross-key changes; explicit open/closing/final states; protection of finalized facts even when sums happen to match; success-ID deduplication; restart recovery; downstream version and before-image guards; strict duplicate-key and integer-token validation.

Install with `moon add LMK-ai-nb/tideweave@0.1.0`. Requires MoonBit compiler 0.10.16+; the generated public interface is [pkg.generated.mbti](pkg.generated.mbti). Run `moon run cmd/demo` for a typed example.

```sh
moon check --target all --deny-warn
moon test --target all --deny-warn
moon build --target all --deny-warn
moon fmt --check
moon info
node scripts/build.mjs
node --test tests/cli.test.mjs
node scripts/serve.mjs
```

The browser runs at `http://127.0.0.1:4174`. Node 22+; no third-party npm dependencies. Native builds require a platform C toolchain. Optional browser checks use Python Playwright/Chromium (`python tests/browser.py`). CI checks Linux/macOS/Windows with wasm, wasm-gc, js and native.

This is a bounded synchronous single-process component for reconciliation batches, edge processing and stream-processing regression fixtures. It retains all accepted facts and successful IDs; at most 5000 active events, 10000 successful commands, 20000 materialized windows and 2 Mi canonical journal units. The host owns network IO, persistence, trusted inputs, external delivery and application epochs. It is not a distributed runtime and makes no external exactly-once guarantee.

Original implementation by the `LMK-ai-nb` project, developed with AI assistance; not a port or renamed copy of previous repositories. Windowing and changelogs are established ideas. Conceptual references and redistributed MoonBit standard-library notices are listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Synthetic example data. MIT licensed.

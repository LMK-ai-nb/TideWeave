# Sources and licenses

The TideWeave domain algorithms, tests, command protocol and presentation are original work developed with AI assistance for this repository. There is no third-party library port, and no copied business implementation from AgentCanary, permscope, or submit-guard.

MoonBit standard library `moonbitlang/core` is a build dependency supplied by the toolchain, under Apache-2.0 with LLVM exceptions. Bundled JavaScript distributions contain compiled standard-library routines; their license and notice are redistributed in `third_party/` and copied into the built browser/CLI distributions.

All example events are synthetic. No customer, student, financial-account or contact data is included. Example order amounts are arbitrary integer minor units; this is an engineering demonstration.

Conceptual references, read to distinguish established windowing semantics from this project's contribution:

- [Apache Flink: event time and watermarks](https://nightlies.apache.org/flink/flink-docs-stable/docs/concepts/time/)
- [Apache Flink: windows](https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/datastream/operators/windows/)
- [MoonWatermarkKit](https://github.com/Oyc996/MoonWatermarkKit): an existing ecosystem library for watermark/lateness/window assignment primitives. TideWeave's contribution is a correction state machine with mutable keyed event identities, deletion-induced session splits, transactional finality, guarded downstream deltas and replay recovery. No implementation code is reused.

Windowing and changelogs are established concepts. This project does not claim to invent those concepts or to be the first streaming library in MoonBit.

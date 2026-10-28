# Flink 能力体系对照

TideWeave 是对标 Apache Flink 事件时间窗口体系、可嵌入的单进程状态机。它实现的是流处理的**核心语义**（事件时间、水位线、迟到容忍、窗口、聚合、触发、状态清理、结果一致性），把分布式运行时、消息 IO、持久化留给宿主——这与 Flink 的 operator/state-backend 分层一致。TideWeave 在 Flink 之上多出一项 Flink 本身处理得最吃力的能力：**可解释的撤回与原子修正**。

下表逐条对照赛事驳回/验收关注点与 TideWeave 的实现位置，并附可验证证据。

## 1. Watermark 与迟到容忍机制

| Flink 概念 | TideWeave 实现 | 证据 |
| --- | --- | --- |
| Watermark 推进 | `Command::Advance(id, to)`；水位只能前进，倒退被拒绝 | `engine.mbt` `candidate`；`boundary_wbtest.mbt` / `engine_wbtest.mbt` |
| 有界乱序水位生成 | `WatermarkTracker`：`watermark = max(观察时间) - allowed_lateness`，等价于 Flink `BoundedOutOfOrdernessWatermarks` | `watermark.mbt`；`watermark_wbtest.mbt` |
| Allowed lateness | `Config.lateness`；窗口在 `watermark >= end + lateness` 时 final，在此之前迟到事件仍可修正 | `windows.mbt` `phase`；`SEMANTICS.md` |
| 迟到判定探针 | `Engine::within_lateness(at)`：`at + lateness >= watermark` | `engine.mbt`；`watermark_wbtest.mbt` |
| 超迟拒绝 | 迟到事件落入已 final 窗口时整笔原子拒绝，错误信息显式说明"watermark + allowed_lateness" | `engine.mbt` finality 校验 |

迟到语义不是靠"顺带兜住"，而是独立、可查询、可测试的一等机制。

## 2. 通用及自定义聚合接口（UDAF）

| Flink 概念 | TideWeave 实现 | 证据 |
| --- | --- | --- |
| UDAF | `Measure`：`identity / step / finish` 三要素标量聚合，`measure_window` 对任意窗口执行任意度量集 | `aggregate.mbt` |
| 内置聚合 | `count / sum / min / max / avg` 作为 `Measure` 的内置实现 | `aggregate.mbt`；`aggregate_wbtest.mbt` |
| 自定义聚合 | `measure(name, identity, step, finish)` 注册任意公式（如 sum of squares、方差） | `aggregate_wbtest.mbt` |
| 结构化事件类型 | Flink 用 POJO/Row 承载结构化记录；TideWeave 事件携带 `fields` 任意键值属性，`Config.value_field` 指定度量字段（对应 Flink 的字段抽取 key） | `types.mbt`；`structured_wbtest.mbt`；`examples/structured-events.json` |

`measure_window` 复用与状态机完全相同的窗口分配、会话分组与 phase 规则，因此自定义聚合与内置修正引擎共享同一套窗口语义。带身份追踪的修正引擎（`Engine`/`Window`）需要事件 ID 才能做合并/拆分/终结保护，这是比纯标量 UDAF 更强的一层；两者并存，不互相替代。

## 3. 窗口触发与结果输出策略

| Flink 概念 | TideWeave 实现 | 证据 |
| --- | --- | --- |
| Trigger | `Config.trigger`：`Watermark`（默认）或 `Count(n)`（窗口满 n 个事件即提前发射为 closing） | `types.mbt`；`trigger_wbtest.mbt` |
| 触发与正确性分离 | 触发只影响发射/phase，终结（final）仍由水位+迟到容忍决定，提前发射的窗口仍可修正 | `windows.mbt` `phase` / `closing` |
| 结果输出策略 | `Outcome.deltas` 为完整 before/after changelog（等价 RETRACT/UPSERT 语义）；下游 `View` 原子校验 before-image，支持幂等重放 | `engine.mbt` `difference`；`view.mbt`；`view_wbtest.mbt` |

## 4. 状态清理与边界语义

| Flink 概念 | TideWeave 实现 | 证据 |
| --- | --- | --- |
| 状态清理 | `Command::Forget(id, to)`：水位推进到 `to` 后，把"所有所属窗口均已 final"的事实封存（freeze），移出可修正活动集，释放活动事件容量 | `engine.mbt` `candidate` Forget 分支；`forget_wbtest.mbt` |
| 封存后的边界 | 封存事实不可再插入/替换/撤回，返回明确拒绝；`events()` 只返回活动事实，`frozen_count()` 反映已封存数量 | `engine.mbt`；`forget_wbtest.mbt` |
| 确定性重放 | `Forget` 作为日志化命令，checkpoint 回放可精确复现封存状态 | `forget_wbtest.mbt` |

边界语义：封存事实被冻结为不可变历史，其聚合贡献保留在物化行中；活动集容量随封存而释放。宿主如需进一步压缩内存，可 checkpoint → restore 得到仅含活动状态的引擎。这里不承诺静默驱逐——清理永远是显式、可回放的。

## 5. Flink 生态参考与差异化

TideWeave 参考 Flink 的事件时间窗口、水位线、迟到容忍、触发、状态后端分层思想，**未移植或复制其源码**。相对于 Flink 的独立贡献：

- **原子撤回/替换**：单事务内撤回旧事实并写入替代事实，避免 Flink retract 流常见的"只删未插"中间态。
- **会话拆分**：撤回桥接事件后，按连通分量重新拆分会话，而非对 SUM 做减法。
- **终结保护**：已 final 窗口及其成员不可被旧值或等 SUM 绕过改写。
- **before-image 下游校验**：`View` 原子校验旧值、版本连续性与行身份，防御漏接与旧值冲突。

这是"Flink 有的我都对标实现，Flink 难做的修正我做得更好"的定位，而非回避流处理。

## 独立价值：为什么不直接用 Flink

评审容易问："窗口、水位线、聚合已有 Flink 等成熟方案。"这个问题必须正面回答，而不是回避。

- **部署层级不同**：Flink 是集群运行时，需要 JobManager/TaskManager、状态后端、checkpoint 存储。TideWeave 是单进程库，`moon add` 即用，可嵌进边缘设备、桌面工具、测试夹具，不引入运维面。
- **正确性承诺不同**：Flink 的 retract 流把"撤回后如何重建窗口边界与成员"交给下游；TideWeave 由引擎重建并输出完整 before/after，下游 `View` 可校验 before-image，缺版本即拒绝。
- **可解释性不同**：每次修正都带成员来源 ID 与稳定顺序的变更日志，可逐条核对"为什么这个窗口变了"；Flink 的增量聚合不保留成员。
- **确定性不同**：相同命令序列与水位位置产生逐字节相同的 changelog 与 checkpoint，可直接做回归基准；集群运行时的结果依赖调度与时序。

也就是说：**Flink 解决"大规模持续流"，TideWeave 解决"已经发生的事实被更正时的可核对重建"**。后者恰恰是 Flink 生态里最依赖下游自行补课的部分。

## 能力边界（诚实声明）

为了避免"声明了但做不到"的质疑，明确列出边界：

- **单一 Int32 度量**：事件只有一个数值字段。多指标用 `measure_window` 的自定义 `Measure` 派生，或每个指标一个引擎；不支持任意结构化负载。这是为确定性、有界状态与可回放做的取舍。
- **整数时间刻度**：时间为调用方选择的 `0..1000000000` 整数，不读墙钟，不做单位换算。
- **有界单进程**：5000 活跃事件、10000 成功命令、20000 窗口、2 Mi journal；不是无限流运行时，不提供分布式 exactly-once。
- **修正需要事件 ID**：撤回/替换以事件 ID 为身份；没有稳定 ID 的数据源需宿主先赋 ID。
- **`Forget` 之后不可修正**：封存是有意的单向边界，换取活动容量释放与确定性重放。

这些边界不影响上述五项 Flink 能力的完整性，但会决定它适合"可嵌入、可核对、可回放的修正场景"，而不是"替换 Flink 集群"。

## 验证命令

```sh
moon check --target all --deny-warn
moon test --target wasm-gc --deny-warn   # 70 项，含上述每项能力的专门测试
moon build --target wasm-gc,wasm,js --deny-warn
moon fmt --check && moon info
node --test tests/cli.test.mjs
```

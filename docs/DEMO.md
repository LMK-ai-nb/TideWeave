# 三分钟演示与答辩准备

## 演示顺序

1. 打开事件时间实验室。说明事件时间与到达顺序不同；当前两个事件位于两个独立会话。
2. 下一步将水位推进到 12。第一个窗口进入 closing，但 20 单位的迟到宽限还没有结束。
3. 下一步输入 at=8 的迟到事件。两个旧窗口被删除，一个新窗口原子替代它们；SUM 从分散的 20、35 变为 67。
4. 下一步撤回桥接事件。合并窗口消失，两个原始会话重建。指向成员 ID 与精确 before/after 日志。
5. 全部执行：水位 60 后，两窗口均 final。最后一次撤回被整笔拒绝，版本停在 5。
6. 展开自定义数据并导出检查点。运行 CLI 的 resume 或库的 restore，证明重启后仍认识成功命令 ID。

## 命令行演示（不需要打开浏览器）

```sh
# 0) 类型化 API 演示（含封存）
moon run cmd/demo
# 末两行应看到：freeze: accepted; deltas=0 / sealed-correction: rejected
#              frozen=2, active=0 / restored version=5, watermark=60

# 0b) 结构化事件：事件只带 fields，度量由 value_field 指定
node bin/tideweave.mjs run examples/structured-events.json

# 1) 错误对照：只做数值增减 vs 重建会话
node scripts/compare_naive.mjs

# 2) NDJSON 流：首行配置，逐行命令，逐行 outcome + summary
cat examples/session-stream.ndjson | node bin/tideweave.mjs stream

# 3) 六个完整场景（批处理）
node bin/tideweave.mjs run examples/session-correction.json
node bin/tideweave.mjs run examples/order-amendment.json
node bin/tideweave.mjs run examples/sensor-backfill.json
node bin/tideweave.mjs run examples/state-freeze.json
node bin/tideweave.mjs run examples/structured-events.json
node bin/tideweave.mjs run examples/ad-billing.json
```

> **退出码约定**：`0` = 全部 accepted/duplicate；`1` = 报告含 rejected/conflict——session-correction、state-freeze 与 NDJSON 流的**末笔拒绝是刻意演示**（终结保护 / 封存边界），不是程序错误；`2` 才是无效输入或 IO 失败。

`examples/session-stream.ndjson` 里包含 `forget` 命令：水位推进到 60 后封存已终结事实，随后对封存事实的撤回被拒绝（`cannot remove a sealed (finalized) fact`），summary 中 `events` 为空、`frozen=2`。

## 应能自己解释的内容

- 为什么 gap 边界使用 `<` 而非 `<=`？半开区间的相接不等于重叠；约定公开且有边界测试。
- 为什么不能只做数值减法？删除可能改变会话拓扑，导致一个窗口拆成多个窗口；成员、边界与 min/max 也要重算。`scripts/compare_naive.mjs` 给出可复跑的错误结果（边界 `[0,26)`、sum 55、min 12）。
- 为什么终结检查还比对原始事件？同一批成员交换值后 SUM 可能相同，不能因此改写已终结事实。
- 为什么有的拆分会拒绝？它会生成在当前水位下已经 final 的新历史行，违反终结契约；整笔拒绝比输出局部状态更容易推理。
- `Forget` 之后还能改吗？不能。封存是有意的单向边界：事实冻结、事件移出活动集、活动容量释放，但仍然可经检查点确定性回放。
- `Trigger::Count(n)` 会不会破坏正确性？不会。触发只影响发射/phase，终结仍由水位 + allowed lateness 决定，提前发射的窗口仍可修正。
- 和社区已有的 `moonwatermarkkit` 等包是什么关系？它们做水位判定/窗口分配/数据质量/近似统计/模式检测；本项目做修正层（撤回后重建 + 终结保护 + before-image 校验），无代码复用、非分支扩展。见 `docs/PRIOR_ART.md`。
- 是否保证 exactly-once？只保证本引擎成功命令 ID 在容量内的幂等和单次原子状态更新。外部队列、文件、消费确认与可信传输由宿主负责。
- 性能如何？批处理 4096 事件约 84ms；批量 5000 事件 + 封存约 627ms（含 Node 启动与 JSON 解析）。逐条单事件事务是 O(n²) 重建，属公开边界，推荐按事务批量提交（每事务最多 128 条）。
- 是否原创？代码独立实现，概念参考公开流处理文档。AI 辅助开发已披露；不是原项目改名或把成熟库简单封装。

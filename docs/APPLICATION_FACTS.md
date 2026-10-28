# TideWeave 申报材料事实清单

> 供本人撰写申报书、供老师审阅项目事实。**这不是申报书正文**；表单要求"不要使用 AI 编写"，请用自己的话改写成不超过一页的 Markdown 后提交。

申请人：李明坤 ｜ GitHub：LMK-ai-nb ｜ 联系邮箱：1416377553@qq.com

## 一句话定位

TideWeave 是一个**通用、可嵌入的 MoonBit 事件时间窗口处理库**：窗口、水位线、UDAF、触发、状态清理对标 Flink 能力；在此之上提供一般窗口库不具备的修正层——当**已经记录的事实被更正**时，原子重建受影响窗口，输出可核对、可回放、可被下游验证的 before/after 变更。事件支持任意结构化字段，数值度量可按字段配置。

## 要解决的问题（可实测）

同一设备先上报 `at=0, value=20` 与 `at=16, value=35`，`gap=10`，属于两个会话；网络恢复后补传 `at=8, value=12`，两个会话应合并；随后发现该记录有误并撤回，窗口必须重新拆分。

只做数值加减的实现（`node scripts/compare_naive.mjs` 可复跑）会得到：

```text
[0,26) members=[left,right] count=2 sum=55 min=12 max=35   ← 边界、成员、min 全错
```

TideWeave 得到：

```text
[0,10) sum=20  +  [16,26) sum=35   ，撤回命令输出 1 条 delete + 2 条 upsert
```

## 已实现能力（均有测试或可运行证据）

| 能力 | 说明 | 证据 |
| --- | --- | --- |
| 窗口 | 滚动、带相位偏移的滑动、会话；半开区间；负起点 floor 对齐 | `fixed_wbtest.mbt`、`session_wbtest.mbt` |
| 修正 | 按事件 ID 插入、替换、撤回；跨 key 移动；多事件原子事务，失败整笔回滚 | `engine_wbtest.mbt`、`boundary_wbtest.mbt` |
| 会话重建 | 迟到合并；撤回后按连通分量重新拆分，保留成员来源 | `session_wbtest.mbt` |
| 聚合 | count / Int64 sum / min / max，以及自定义 `Measure` UDAF | `aggregate_wbtest.mbt` |
| 水位 | `WatermarkTracker`（有界乱序）、`within_lateness` 探测 | `watermark_wbtest.mbt` |
| 终结保护 | open → closing → final；即使 SUM 相同也拒绝改写已终结事实 | `boundary_wbtest.mbt` |
| 触发 | `Trigger::Watermark` 与 `Trigger::Count(n)`；触发只影响发射，不改变终结 | `trigger_wbtest.mbt` |
| 状态清理 | `Command::Forget` 封存已终结事实、释放活动容量、拒绝后续修正、可确定性回放 | `forget_wbtest.mbt` |
| 结构化事件 | 事件携带任意 `fields` 键值属性；配置 `value_field` 后任意整数字段作为度量，随检查点与变更日志完整保留 |
| 检查点 | 记录并校验 version / watermark / frozen；派生行重建而非信任存储聚合 | `checkpoint_wbtest.mbt` |
| 下游校验 | `View` 原子校验版本连续、before-image、行身份 | `view_wbtest.mbt` |
| 接入 | MoonBit API、严格 JSON 协议、Node CLI、NDJSON `stream`、浏览器实验室 | `tests/cli.test.mjs`、`tests/browser.py` |

规模：**67 项 MoonBit 测试**（wasm / wasm-gc / js 各 67）、**10 项 CLI/ESM 集成测试**、CI 覆盖 Linux / macOS / Windows 与 wasm、wasm-gc、js、native 四个目标。

## 三个完整用例

**1. 离线会话修复**
输入：设备先报 `at=0` 与 `at=16`，再补传 `at=8`，随后撤回 `at=8`。
输出：合并窗口被删除，两个原始会话重建，成员与聚合一起修正。
价值：补传/撤回不会留下错误边界，避免看板数字"回退后再也回不来"。

**2. 订单原子修正**
输入：原订单 60 件；一次事务中撤回原订单并写入替代订单 189 件。
输出：整笔提交或整笔不生效，变更日志给出精确 before/after。
价值：撤单与改单不会出现"撤了但没补"的中间态。

**3. 传感器迟到补传与校准**
输入：同一记录落入多个重叠滑动窗口；补传后对旧值做校准。
输出：所有受影响窗口一次性修正，其他 key 不受影响。
价值：重叠窗口下仍保持结果一致，便于逐条核对。

## 方向与通用性

- 对标 Apache Flink 事件时间体系：滚动/滑动/会话窗口、水位线、allowed lateness、UDAF、触发、状态清理、changelog。
- 独立价值在**修正层**：撤回后重建、原子多事件事务、终结保护、before-image 校验、确定性回放。
- 部署形态：单进程可嵌入，不依赖集群、消息队列或外部状态后端；同一核心同时服务 MoonBit API、JSON 协议、CLI、NDJSON 与浏览器。
- 适用：IoT 补传、订单更正、指标回算、离线重放、边缘设备、测试夹具。

## 与已有项目的关系（初审必填）

- `Oyc996/moonwatermarkkit`：水位判定与窗口分配原语；无状态聚合、无撤回。
- `zmjknn/moon-stream-quality`：流式数据质量规则引擎；不做会话拆分与事实修正。
- `yhsrtty/moon-distinct-sketch`：概率 sketch 与近似统计；不保留成员。
- `JSJ222/mooncep`：复杂事件模式检测；文档明确声明不支持事件修正/撤回。
- 关系：**无代码复用，不是任何项目的分支、改名或扩展**；窗口分配、水位推进、聚合、修正、检查点均为独立实现，仅依赖 `moonbitlang/core`。
- 与本人此前 `moonbit-submit-guard`、`permscope`、`AgentCanary` 无核心业务复用。

## 原创性与许可

- 独立实现；概念参考公开流处理文档；AI 辅助开发已如实披露。
- 许可证 MIT；依赖 `moonbitlang/core`（Apache-2.0），已在 `THIRD_PARTY_NOTICES.md` 声明。
- 无移植代码；如后续引入第三方代码将按许可证逐项声明。

## 链接

- 仓库：https://github.com/LMK-ai-nb/TideWeave
- 在线实验室：https://lmk-ai-nb.github.io/TideWeave/
- Mooncakes：https://mooncakes.io/docs/LMK-ai-nb/tideweave@0.2.2
- 语义契约：`docs/SEMANTICS.md`
- 为什么需要修正层：`docs/WHY_CORRECTION.md`
- 同类项目披露：`docs/PRIOR_ART.md`
- 发布证据：`docs/RELEASE.md`

## 写申报书时按这六段展开（不要照抄本文件）

1. **简介**：三句话——谁遇到什么问题；只做数值加减会错在哪；TideWeave 怎样原子重建。
2. **方向与通用性**：先写 Flink 对标的能力，再写修正层的独立价值与可嵌入形态。
3. **三个用例**：每例写清输入、输出、价值，用上面的具体数字。
4. **核心功能**：挑 5–6 项，配一句验证方式（测试/命令/发布包）。
5. **与已有项目的关系**：四个同类项目各做什么、你不做什么、无代码复用。
6. **原创与许可**：独立实现、AI 辅助已披露、MIT、仅依赖标准库。

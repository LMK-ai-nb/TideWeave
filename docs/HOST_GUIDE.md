# 接入指南

TideWeave 是库，不是服务。宿主只需三件事：喂命令、拿 outcome、把 outcome 交给下游。下面给出三种最小接入方式，均不要求修改核心代码。

## 1. MoonBit 库内嵌

```moonbit
import { "LMK-ai-nb/tideweave" @tide }

let cfg = @tide.config(@tide.Tumbling(size=60, offset=0), lateness=10)
let engine = @tide.Engine::new(cfg)
let view = @tide.View::new()
let tracker = @tide.WatermarkTracker::new(allowed_lateness=10)

// 每收到一条记录：先观察事件时间，再按需推进水位。
fn on_record(id : String, key : String, at : Int32, value : Int32) -> Unit raise @tide.TideError {
  let outcome = engine.apply(@tide.Transact(id=id, changes=[@tide.Put({ id, key, at, value })]))
  view.apply(outcome)          // 下游视图原子校验 before-image
  let watermark = tracker.observe(at)
  if watermark > engine.watermark() {
    ignore(engine.apply(@tide.Advance(id="w-\{watermark}", to=watermark)))
  }
}
```

宿主负责：消息 IO、持久化 `engine.checkpoint()`、授权、外部投递。

## 2. Node / ESM 桥

仓库自带 `dist/engine.js`（由 `node scripts/build.mjs` 生成，无第三方依赖）：

```js
import { replay, resume_replay, stream_ndjson } from './dist/engine.js';

const request = {
  schema_version: 1,
  config: { window: { kind: 'session', gap: 10 }, lateness: 20 },
  commands: [
    { id: 'seed', kind: 'transaction', changes: [
      { op: 'put', event: { id: 'a', key: 'k', at: 0, value: 3 } },
    ] },
    { id: 'w', kind: 'watermark', to: 10 },
  ],
};
const report = JSON.parse(replay(JSON.stringify(request)));
if (report.error) throw new Error(report.error.message);
for (const step of report.steps) console.log(step.id, step.status, step.deltas.length);
```

重启：把 `report.checkpoint` 存起来，下次用 `resume_replay({schema_version:1, checkpoint, commands})` 继续，成功命令 ID 的去重身份不会丢。

## 3. 管道直连（无需写任何宿主代码）

首行配置，其后每行一条命令；逐行输出 outcome，末尾一行 summary。任何能产出换行 JSON 的程序都能驱动：

```sh
# 从一个 JSON 事件流生成命令并直接灌入
node my-consumer.mjs | node bin/tideweave.mjs stream --checkpoint state.json

# 或直接跑仓库示例
cat examples/session-stream.ndjson | node bin/tideweave.mjs stream
```

传输契约见 [FORMAT.md](FORMAT.md#streaming-ndjson)。退出码：0 全部 accepted/duplicate；1 存在 rejected/conflict；2 输入或 IO 错误。

## 下游消费

`Outcome.deltas` 是完整变更：`delete` 带 before，`upsert` 带 after（替换时也带 before）。把每个 accepted outcome 交给 `View`，它会校验版本连续、before-image 与行身份，缺一即整笔拒绝——这让"漏接一条"和"拿到旧值"变成显式错误，而不是静默错账。

## 边界

- 单进程、同步、有界：最多 5000 活跃事件、10000 成功命令、20000 窗口。
- 事件时间为调用方选择的整数刻度，不读墙钟；`WatermarkTracker` 只是 `max(事件时间) - allowed_lateness`。
- 单一 Int32 度量。多指标用 `measure_window` 派生（自定义 `Measure`），或每指标一个引擎；不支持任意结构化负载。
- 不提供分布式运行时、消息队列、持久化与外部 exactly-once；这些由宿主负责。

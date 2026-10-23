# 项目事实核对（AI 辅助整理，非正式申报书）

| 项目 | 可核对事实 |
| --- | --- |
| 维护者 | 李明坤 / LMK-ai-nb；其他联系方式未收集 |
| 定位 | 对标 Apache Flink 事件时间窗口体系的可嵌入窗口引擎，额外具备 Flink 难做的撤回与原子修正 |
| 代码来源 | 独立新仓库与新业务核心，不复用此前提交检查、权限分析项目 |
| 核心语言 | MoonBit；Node 负责文件 IO，浏览器负责展示 |
| 窗口 | 滚动、带偏移滑动、会话；半开区间；数学 floor 负起点对齐 |
| 修正 | 按事件 ID 插入／替换／撤回；一命令内多项原子变更；跨 key 移动 |
| 突出功能 | 迟到桥接合并、撤回桥接拆分、原子替代、终结保护 |
| 水位线 | `Advance` 显式推进；`WatermarkTracker` 有界乱序生成（等价 Flink BoundedOutOfOrderness）；`within_lateness` 迟到探针；超迟整笔拒绝 |
| 聚合 | 内置 count/Int64 sum/min/max + 完整成员；`Measure`/`measure_window` 自定义聚合（UDAF），内置 avg 等 |
| 触发 | `Trigger`：`Watermark`（默认）或 `Count(n)` 提前发射；只影响发射不影响终结 |
| 状态清理 | `Command::Forget` 封存已终结事实、释放活动容量、拒绝后续修正；可经 checkpoint 精确回放；`frozen_count` 观察 |
| 可解释输出 | 版本、完整 before/after、成员来源 ID、count/sum/min/max |
| 重启 | 可验证回放检查点，保留成功命令去重身份 |
| 下游 | View 校验连续版本、before image 和完整原子应用 |
| 场景一 | 离线设备数据恢复会话边界；撤回错误桥接后恢复原始会话 |
| 场景二 | 分组订单指标在迟到宽限内同时撤回旧单、写入替代单 |
| 场景三 | 传感器补传与校准同时修正多个重叠窗口 |
| 提交作者 | `git log` 12/12 均为 `LMK-ai-nb <315346758+LMK-ai-nb@users.noreply.github.com>`；本仓库 git 作者已固定，无他人提交 |
| 同类项目 | 主动披露 moonwatermarkkit / moon-stream-quality / moon-distinct-sketch / mooncep；无代码复用、非分支/扩展；见 [PRIOR_ART.md](PRIOR_ART.md) |
| 测试 | 61 项 MoonBit（区间枚举 oracle、图连通 oracle、状态差分、UDAF、水位、触发、封存、边界、CLI 及真实浏览器） |
| 许可证 | 原创代码 MIT；编译分发保留 MoonBit core 的许可证和 NOTICE |
| 容量 | 5000 活跃事件、10000 成功命令、2 Mi journal 单元、20000 聚合窗口 |
| 范围 | 有界、同步、单进程、整数时间；宿主负责 IO、持久化、授权和连续任务生命周期；不提供分布式运行时或外部 exactly-once |

逐条对照见 [FLINK_MAPPING.md](FLINK_MAPPING.md)。

以上材料由 AI 辅助整理，不能作为符合“不要使用 AI 编写”要求的本人正式申报书。

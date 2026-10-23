# 技术验收自检 — 2026-10-20（2026-10-23 补充）

结论：可运行的新项目、核心承诺与工程证据已具备；官方申报、本人申报书和最终验收结论仍须赛事方及参赛者完成。这不是主办方的验收结果，也不保证获奖。

## 已检查的证据

| 检查项 | 实际证据 |
| --- | --- |
| 账户 | GitHub API `/user` 返回 `LMK-ai-nb`，用户 ID 315346758；仓库 owner 相同；repo-local 提交作者使用该账户 noreply 邮箱 |
| 独立新项目 | 2026-10-20 创建的 TideWeave；父历史不包含旧项目，业务核心与 submit-guard/permscope/AgentCanary 不同 |
| 有效工程 | `moon.mod` 名称 `LMK-ai-nb/tideweave`，原生 MoonBit 库、typed demo、ESM bridge |
| 编译检查 | `moon check --target all --deny-warn` 通过 |
| 测试 | 61 项 MoonBit 测试（包括可执行 API 文档）；10 项公共 CLI/ESM 集成测试；真实 Chromium 检查 |
| 多目标 | Linux/macOS/Windows，wasm、wasm-gc、js、native，远程 CI 成功，见 [CI](https://github.com/LMK-ai-nb/TideWeave/actions/workflows/ci.yml) |
| 本地目标 | Windows 本机 wasm、wasm-gc、js 通过；最新 native 使用 MSVC 的 Windows CI 验证，未把本机缺少 SDK 当作本地成功 |
| 格式与 API | `moon fmt --check`、`moon info` 与已提交 `.mbti` 核对 |
| 真实入口 | `moon run cmd/demo`、CLI 三场景、公开浏览器实验室均运行验证 |
| 资源与边界 | 输入、事件、命令、滑动扇出、journal、窗口容量有显式限制；终结保护与原子回滚有测试 |
| 输入准确性 | 重复解码键、未知／不适用字段、深层嵌套、指数与舍入小数均拒绝 |
| 拷贝边界 | 外部修改 rows、deltas、命令数组不会污染 engine；专门测试 |
| 开源合规 | 根目录 MIT，AI 辅助开发与概念参考公开，MoonBit core 许可证／NOTICE 复制到编译分发 |
| 打包清洁 | `python scripts/package_check.py` 验证 Moon 发布包不包含凭据、work、构建缓存或私人材料 |
| 提交历史 | 每个里程碑提交包含实质实现／测试／文档；至少 10 个保留在 main 的开发提交，无空提交，不把数量等同官方有效性认定 |

核心约 1158 行 MoonBit，测试约 622 行（格式化后的物理行统计，另有 bridge、demo、可执行文档）。未把模板、空行或前端代码换算为有效 MoonBit 代码量；赛项介绍中的规模参考不等于十月硬性行数标准。

## 核心能力与验证映射

- 固定窗口：数学 floor 与完整区间枚举 oracle 对照，覆盖 size/slide/offset 和时间零附近的负起点。
- 会话：全部 255 个非空小网格子集与独立的全连接图传播 oracle 对照；覆盖相接边界、同时间与 key 隔离。
- 状态机：合并、拆分、跨 key 替换、ID 冲突、缺失撤回、容量回滚、水位倒退、部分滑动窗口 final、等 SUM 修改底层事实、撤回产生过期子窗口与原子替代。
- 一致性：180 步混合 key 轨迹，批处理聚合、引擎物化视图和下游 View 比对；丢版本／错误 before image 整笔拒绝。
- 恢复：连续运行与检查点加后缀一致，恢复后重试去重，伪造计数和不可提交 journal 拒绝。
- 适配器：原始 JSON 保留重复键和数字拼写，CLI 跨进程恢复与退出码检查；浏览器实际导出并读取检查点，验证没有将拒绝命令写进成功日志。

## 2026-10-23 补充（针对初审驳回的 Flink 能力清单）

- 自定义聚合（UDAF）：`Measure` + `measure_window`，内置 count/sum/min/max/avg，测试覆盖自定义公式（平方和）与窗口分配一致性。
- 水位线：`WatermarkTracker` 有界乱序生成、`Engine::within_lateness` 迟到探针、超迟拒绝信息显式化。
- 触发：`Trigger`（Watermark/Count）接入 Config 与 phase，触发只影响发射、不影响终结。
- 状态清理：`Command::Forget` 封存已终结事实、释放活动容量、拒绝后续修正，经 checkpoint 精确回放。
- 直接可用：`stream` 子命令以 NDJSON 驱动同一核心（首行配置、逐行命令、逐行 outcome + summary/checkpoint），任何行式生产者可直连，不必先写集成代码；CLI 测试 10 项。
- 同类项目披露：检索 mooncakes.io / GitHub，确认 4 个相关包并逐项对照边界，声明无代码复用、非分支/扩展，见 [PRIOR_ART.md](PRIOR_ART.md)。
- 提交作者审计：`git log` 12/12 提交均为 `LMK-ai-nb <315346758+LMK-ai-nb@users.noreply.github.com>`，无他人提交记录；本仓库 `git config user.name/email` 已固定。
- Flink 对照：见 [FLINK_MAPPING.md](FLINK_MAPPING.md)，逐条回应驳回 5 点，并附"独立价值"与"能力边界"诚实声明。

以上逐项均有对应 `.mbt` 测试，`moon test --target wasm-gc` 61/61 通过，`moon check --target all --deny-warn` 全绿。

## 提交材料仍需本人处理

1. 十月表单要求本人独立编写的一页 Markdown 申报书；本仓库 AI 辅助事实材料不能冒充该文件。收到正式申报书后，还须逐条检查其中的承诺是否与代码一致。
2. 李明坤按实际情况填写往届参赛、联系方式、组队、身份／学历分支和银行卡等资料；敏感信息直接交官方。
3. 本人阅读确认诚信承诺、完成提交、保存回执，加入赛事群并将昵称改为 GitHub ID。

发布包、独立消费与最终交付信息以 [发布记录](RELEASE.md) 为准。

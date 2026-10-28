# TideWeave 交接说明

最后更新：2026-10-29 ｜ 当前版本：**0.2.3** ｜ 维护者：LMK-ai-nb

这份文档给接手人（或未来的自己）：项目是什么、现在在哪、怎么跑、怎么发、有哪些坑、还剩什么。

## 一分钟概览

TideWeave 是用 MoonBit 编写的**通用事件时间窗口处理库**：滚动/滑动/会话窗口、水位线、UDAF、触发、状态清理；在此之上提供一般窗口库没有的**事实更正层**（撤回重建、原子修正、终结保护、before-image 校验、确定性回放）。事件支持任意结构化字段，`value_field` 可把任意整数字段作为度量。

当前状态（2026-10-29）：

- 70 项 MoonBit 测试（wasm / wasm-gc / js 各 70）+ 10 项 Node CLI/ESM 测试，CI 三系统四目标全绿
- Mooncakes `0.2.3` 已发布，并在全新消费模块中下载、编译、运行验证
- 在线实验室 5 个场景（含结构化电表、终结后封存）
- 代码、文档、发布证据全部就绪；**唯一未完成的是申报书正文**（须申请人本人撰写）

## 链接

- 仓库：https://github.com/LMK-ai-nb/TideWeave
- 实验室：https://lmk-ai-nb.github.io/TideWeave/
- Mooncakes：https://mooncakes.io/docs/LMK-ai-nb/tideweave@0.2.3
- CI：https://github.com/LMK-ai-nb/TideWeave/actions

## 账号与身份（最重要，先读）

本仓库和 Mooncakes 模块都绑定 `LMK-ai-nb`。**换账号前必须知道**：

1. 本仓库的提交作者必须全部是 `LMK-ai-nb <315346758+LMK-ai-nb@users.noreply.github.com>`。仓库已固定 repo-local git 身份，并用 `scripts/check_identity.mjs` 全量审计；pre-commit 钩子会拦截错误身份（`node scripts/install_hooks.mjs` 安装）。
2. Mooncakes 模块 `LMK-ai-nb/tideweave` **只有 LMK-ai-nb 能发布**。当前登录不是它时，`moon publish` 返回 `403 User mismatch`。历史上出现过两次账号漂移（登录到了无关账号），都导致发布被挡——换账号后第一件事是 `moon whoami`。
3. 不要把本项目的提交、评论或发布落到其他命名空间。八月"他人提交记录"与十月"账号混用"两次驳回都属于这一类。
4. **公开文件里只能出现 `LMK-ai-nb` 这一个身份**：不要写入任何其他账号名、他人项目署名或联系邮箱。个人联系方式只放本地 `报名材料/`（已排除出版本库），由本人直接填官方表单。

### 换 Mooncakes 账号

```sh
moon logout
moon login          # 浏览器必须是目标 GitHub 账号的会话
moon whoami         # 必须显示目标账号
```

发布本项目时，`moon whoami` 必须是 `LMK-ai-nb`。

### 换 GitHub 账号（本机）

- **只改当前仓库**：`git config --local user.name` / `user.email` 保持 LMK-ai-nb，不要 `--global`。
- GitHub Desktop 登录另一个账号时，提交弹窗要选"保留本仓库的本地邮箱"，不要点"更新邮箱"。
- 推送凭据在 Windows 凭据管理器（`git:https://github.com`）。换账号后若推送仍以旧账号身份进行，删除该条目后重新推送会触发登录：

```bat
cmdkey /list | findstr github
cmdkey /delete:git:https://github.com
```

## 本地环境

- MoonBit：`moon 0.1.20261021` 或更新（`moon version`）
- Node 22+（CLI、构建、集成测试）
- Python 3（可选；`tests/browser.py` 需要 Playwright + Chromium，CI 会跑）
- Windows 本机无 MSVC，native 目标由 CI 验证，不要声称本地 native 通过

## 构建与验证

```sh
moon check --target all --deny-warn     # 必须全绿（deny-warn 会把弃用警告当错误）
moon fmt --check
moon test --target wasm-gc,wasm,js      # 70 项 × 3
node scripts/build.mjs                  # 生成 web/engine.js 与 web/data
node --test tests/cli.test.mjs          # 10 项
node scripts/check_identity.mjs         # 提交作者审计
python scripts/package_check.py         # 发布包清洁检查
moon run cmd/demo                       # 类型化 API 演示
node bin/tideweave.mjs run examples/structured-events.json
```

五个示例：session-correction、order-amendment、sensor-backfill、state-freeze、structured-events。**其中 session-correction 与 state-freeze 的退出码是 1**——末笔拒绝是刻意演示终结保护，不是崩溃（退出码约定见 `docs/DEMO.md`）。

## 发布流程

1. 提升版本：`moon.mod`、`package.json`、README/README.en 的 `moon add`、`CHANGELOG.md`、`web/index.html` 标识。
2. `moon whoami` 必须是 `LMK-ai-nb`。
3. `moon publish`（返回 `Server status: 200 OK`）。
4. 消费验证：在独立模块里 `moon add --upgrade LMK-ai-nb/tideweave@X.Y.Z`，`moon check --target all --deny-warn` + `moon run .`。
5. 打开 Mooncakes 页面核对描述、README、安装行。

**注意**：Mooncakes 页面保存的是**发布时的 README**。改了 README 后必须再发一个 patch 版本才能刷新页面（0.2.1 就是为此而发）。

## 代码地图

| 路径 | 作用 |
| --- | --- |
| `types.mbt` | Config / Event（含 `fields`）/ Window / Command，度量解析 `Event::measure` |
| `wire.mbt` | 严格 JSON 协议、`replay_json`、ToJson 实现 |
| `engine.mbt` | 状态机：候选计算、原子提交、终结校验、去重 |
| `windows.mbt` | 窗口分配、会话连通分量、行聚合、phase |
| `aggregate.mbt` | UDAF（`Measure` / `measure_window`） |
| `checkpoint.mbt` | 检查点序列化与恢复校验（version/watermark/frozen） |
| `stream.mbt` | NDJSON 流式接口 |
| `api/` | JS 桥（`exports` 是白名单，新增函数必须加进去） |
| `cmd/demo` | 类型化 API 演示 |
| `web/` | 浏览器实验室（app.js 纯前端 + web/engine.js 由构建生成） |
| `examples/` | 五个可复现场景 |
| `docs/` | 语义、格式、宿主指南、Flink 映射、同类项目、验收、发布证据 |

## 已知坑（都踩过）

- **`Compare for String` 是 shortlex**（先比长度）。所有字符串排序必须用 `lexical_compare`；直接 `.sort()` 或 `.compare()` 会得到"短者在前"的意外顺序。
- **`Event` 字面量必须带 `fields`**（可为 `None`）。新增事件构造处漏了会编译失败。
- **`StringView` 转 String 用 `to_owned()`**；`to_string()` 触发弃用警告，`--deny-warn` 直接失败。
- **Json 布尔是 `True` / `False` 变体**，不是 `Bool(b)`。
- **`Int64` 没有 `to_int32()`**，用 `to_int()`。
- **`Array::stable_sort` 不存在**，用 `sort_by`。
- **检查点包含 `frozen`**，恢复时会校验；伪造计数会被拒。
- **CLI 退出码**：0 全部接受；1 含 rejected/conflict（可能是刻意演示）；2 无效输入或 IO。

## 待办

1. **申报书正文**：`docs/APPLICATION_TEMPLATE.md` 是提纲，`docs/APPLICATION_FACTS.md` 是事实清单，`报名材料/` 有一页版与完整版参考稿。表单明确"不要使用 AI 编写"，必须由申请人用自己的话重写后提交。
2. 重申截止：2026-10-31。
3. 可选增强：结构化字段参与 UDAF（当前 `Measure` 只接收选定数值度量）；native 本地验证。

## 证据索引

- 能力与测试映射：`docs/ACCEPTANCE.md`
- 语义契约：`docs/SEMANTICS.md`
- 协议格式：`docs/FORMAT.md`
- Flink 对照：`docs/FLINK_MAPPING.md`
- 同类项目边界：`docs/PRIOR_ART.md`
- 发布记录：`docs/RELEASE.md`
- 申报状态与驳回回复：`docs/SUBMISSION.md`
- 为什么需要修正层（含"为什么不是数据库"）：`docs/WHY_CORRECTION.md`

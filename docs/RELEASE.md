# 发布与独立使用证据

## 0.2.0 – 0.2.3（2026-10-24 / 10-28）

- `0.2.3`（2026-10-28）响应十月初审意见：事件支持任意结构化字段（`fields`）并可通过 `value_field` 配置度量来源；全部字符串排序固定为 `lexical_compare` 以保证跨版本确定性；文档重定位为通用事件时间窗口处理库，并新增"为什么不是在数据库里改一下"。
- Mooncakes：[LMK-ai-nb/tideweave@0.2.2](https://mooncakes.io/docs/LMK-ai-nb/tideweave@0.2.2)。`0.2.0` 是首个包含新能力的版本；`0.2.1` 为文档修订版；`0.2.2` 修复 `correctable` 语义、检查点 `frozen` 校验与网页实验室的 `forget` 支持。
- 发布校验：`moon whoami` 返回 `LMK-ai-nb`；`moon publish` 返回 `Server status: 200 OK`；文档页 HTTP 200；本地 registry 索引列出 `0.1.0`、`0.2.0`、`0.2.1`、`0.2.2`。
- 独立消费：在 `work/consumer-020` 新模块中 `moon add --upgrade LMK-ai-nb/tideweave@0.2.2` 后，`moon check --target all --deny-warn` 通过；`moon run .` 下载发布包并输出 `seed=accepted, phase=closing` / `correctable_after_final=false` / `freeze=accepted, frozen=2, active=0` / `stream_lines=2`。
- 相对 0.1.0 新增：UDAF（`Measure`/`measure_window`）、`WatermarkTracker`、`Engine::within_lateness`/`correctable`、`Trigger`（Watermark / Count）、`Command::Forget` 状态封存、NDJSON `stream`、`Replay`/summary 的 `frozen` 计数。
- 版本同步：`moon.mod`、`package.json`、README/README.en 的 `moon add`、`CHANGELOG.md`、网页版标识均为 `0.2.1`。
- 检查：提交 `78364dd` 的 [CI 与 Deploy demo](https://github.com/LMK-ai-nb/TideWeave/actions) 均成功；58 项 MoonBit 测试（wasm/wasm-gc/js）、10 项 CLI/ESM 集成测试、`moon check --target all --deny-warn`、`moon fmt --check`、`python scripts/package_check.py` 全部通过。
- 发布账号事故已处理：本机曾登录 `zhangbowen2006`，`moon publish --dry-run` 返回 `403 User mismatch`；切换为 `LMK-ai-nb` 后发布成功。复现与切换步骤见 [SUBMISSION.md](SUBMISSION.md)「切换账号的两种方式」。

## 0.1.0（2026-10-20）

### 公开交付

- 仓库：[LMK-ai-nb/TideWeave](https://github.com/LMK-ai-nb/TideWeave)，实际默认分支 `main`。
- 在线演示：[事件时间实验室](https://lmk-ai-nb.github.io/TideWeave/)，公开访问返回 HTTP 200；完整 Chromium 功能检查通过。
- Mooncakes：[LMK-ai-nb/tideweave@0.1.0](https://mooncakes.io/docs/LMK-ai-nb/tideweave@0.1.0)。隔离 Moon home 的 `moon whoami` 返回 `LMK-ai-nb`；`moon publish` 返回服务器 `200 OK`。包页面 HTTP 200。
- [v0.1.0 Release](https://github.com/LMK-ai-nb/TideWeave/releases/tag/v0.1.0)：含源码和预编译浏览器／CLI 演示的归档，Node 22+ 可直接运行演示。

### 自动检查

已成功完成的 [CI 运行](https://github.com/LMK-ai-nb/TideWeave/actions/runs/39292521743) 对应提交 `9c09998da836bc768f505d40ec2dd749b3338731`：Linux、macOS、Windows 的 check/test/build（wasm、wasm-gc、js、native），37 项 MoonBit 测试、8 项 CLI/ESM 集成测试、Linux Chromium 集成、格式和公共接口校验均成功。后续 main 的最新检查以 [Actions](https://github.com/LMK-ai-nb/TideWeave/actions) 为准。

本机还对真实公开 Pages 地址运行了同一浏览器检查，验证逐步回放、合并／拆分／final、导出检查点、三个场景切换、注入文本和 390px 布局。

### 从 Mooncakes 实际下载使用

在独立的新消费模块、新的 Moon home／registry 环境中，声明：

```moonbit nocheck
name = "local/tideweave_consumer"
version = "0.0.1"
import { "LMK-ai-nb/tideweave@0.1.0" }
```

消费包导入 `LMK-ai-nb/tideweave`。运行 `moon check --target all --deny-warn`、默认目标 `moon run .` 和 `moon run . --target js`。

实际输出：

```text
Downloading LMK-ai-nb/tideweave@0.1.0
Mooncakes fresh consumer OK: merge=67, split=2, recovery/deduplication/downstream view match.
```

消费代码实际执行了插入两事件、迟到合并得到 sum=67、检查点恢复、重试去重、撤回桥接分成两会话，以及下游 View 一致性断言。下载得到的 `engine.mbt` 与工作目录实现逐字节一致，没有用本地路径依赖替代发布包。

## 账户与隐私

GitHub 认证 API、仓库 owner、提交 noreply 身份与 Mooncakes 认证名称均为 `LMK-ai-nb`。本项目使用 repo-local Git 身份和隔离 Moon home；没有切换其他项目的全局 Git／Mooncakes 身份。私有凭据、工作工具链、临时消费项目及缓存均在 ignored 目录中，未提交或打入分发包。

项目技术交付不代表官方报名或验收已完成。正式申报书、联系方式、实际往届经历／组队信息、诚信承诺及官方要求的私密资料须由李明坤本人完成，见 [SUBMISSION.md](SUBMISSION.md)。

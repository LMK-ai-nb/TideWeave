# 十月申报与验收准备

申请人：李明坤；GitHub ID：`LMK-ai-nb`。独立新项目：TideWeave。选项意向为 **新项目申报－参与季度评选**，以本人最终选择为准。以前参加过赛事与本次作品是否为新项目是两个问题，请按本人实际经历填写。

官方来源：[赛事官网](https://moonbitlang.github.io/Hackathon2026/)、[十月申报表](https://bxup9uklfcb.feishu.cn/share/base/form/shrcnWUMlgpbwHaXgzV7HmNhNhg)。本期报名与验收截止 2026-10-31，十月最多提交 3 次，以通过审核前最后一次有效提交或修改为准。具体通知与审核解释以官方为准。

## 申报书的特殊要求

十月报名表在“新项目申报－参与季度评选”条件下要求一页以内的 Markdown 申报书，并明确注明 **“不要使用 AI 编写”**。因此仓库文档、事实说明和模板只能帮助本人理解项目，不能冒充符合要求的本人申报书。请李明坤在理解实现、验证演示后独立撰写，不应把 AI 参考稿原样作为合规申报材料。

本人申报须覆盖：项目名称、简介、方向与通用性、至少 3 个完整预期用例、核心功能、原创／移植／参考说明、移植来源及许可证（若适用）、公开 GitHub 仓库链接。表单要求至少 10 次有效提交，空提交、重复提交和无意义拆分不计；仓库提交数量不代表主办方已认定有效。

可以用 [事实核对清单](FACTS.md) 确认实际实现，用 [Flink 能力对照](FLINK_MAPPING.md) 逐条核对赛事关注点，用 [空白写作提纲](APPLICATION_TEMPLATE.md) 独立组织文字。

## 八月初审驳回原因与对应检查

八月赛季 6 份驳回通知集中在四类问题，本项目逐条自查：

| 驳回原因 | 涉及项目 | 本项目对应动作 |
| --- | --- | --- |
| 社区已有大量类似项目 | CaCacheCheck | [同类项目披露](PRIOR_ART.md)：主动列出 4 个同类 MoonBit 包、逐项对照能力边界、说明不是分支/扩展 |
| 与已维护项目功能重叠、未披露 | ReviewProof / CapsuleTrace / RoboPolicy | 关系声明：与 moonwatermarkkit 等无代码复用；与本人 `moonbit-submit-guard` 等无核心复用（见 PRIOR_ART「关系声明」） |
| 仓库含他人提交记录 | moonbit-submit-guard | 作者审计：`git log` 12/12 提交均为 `LMK-ai-nb <315346758+LMK-ai-nb@users.noreply.github.com>`；本仓库 `git config user.name/email` 已固定为该身份 |
| 申报书格式不支持 | bech32-kit | 严格一页 Markdown 提纲 + 提交前格式自检（见 [写作提纲](APPLICATION_TEMPLATE.md) 末尾） |

## 账号与归属自检（每次提交前）

八月曾因"仓库中有他人的提交记录"被驳回。本仓库固定一个身份：

- 本仓库 `.git/config`：`LMK-ai-nb <315346758+LMK-ai-nb@users.noreply.github.com>`
- 远程：`github.com/LMK-ai-nb/TideWeave`（GitHub API 返回 owner 登录名 `LMK-ai-nb`）
- 凭据用户名：`LMK-ai-nb`
- 全部 14 条提交的作者与提交者均为该身份

自检命令：

```sh
node scripts/check_identity.mjs
```

安装防误提交钩子（每个 clone 执行一次，钩子不入库）：

```sh
node scripts/install_hooks.mjs
```

**GitHub Desktop 注意**：当前桌面端登录的是 `zhangbowen2006`，其账户邮箱是 `1416377553@qq.com`。在这个仓库提交前必须：

1. 把 GitHub Desktop 切换为 `LMK-ai-nb` 账号；或
2. 在 Repository settings → Git → Email 选择"本仓库的本地邮箱"；**不要点 "Update email"**，它会把全局配置改成 zhangbowen2006 的邮箱，影响其它仓库。
3. 出现 "This commit will be misattributed" 时不要点 Ignore 了事——它表示这次提交会归到 zhangbowen2006。

Mooncakes 发布前同样必须 `moon login` 为 `LMK-ai-nb`（2026-10-24 已完成切换，`moon whoami` 返回 `LMK-ai-nb`；换机器时需重新确认）。

## 发布状态与后续同步

**2026-10-24 已完成 `0.2.0` 发布**：`moon whoami` 返回 `LMK-ai-nb`，`moon publish` 返回 `Server status: 200 OK`；Mooncakes 索引同时存在 `0.1.0` 与 `0.2.0`，文档页 `https://mooncakes.io/docs/LMK-ai-nb/tideweave@0.2.0` 返回 200。README/README.en 的 `moon add` 版本、`moon.mod`、`package.json`、`CHANGELOG.md` 与网页版标识均已同步为 `0.2.0`。

后续重新发布时按顺序检查：

1. `moon whoami` 必须显示 `LMK-ai-nb`。若显示其它账号，先按下方"切换到 LMK-ai-nb"处理，否则会发布失败或落到错误命名空间（这与八月"提交记录归属"驳回同类风险）。
2. 确认 `git log` 作者仍全部是 `LMK-ai-nb <315346758+LMK-ai-nb@users.noreply.github.com>`。
3. 提升 `moon.mod` 的 `version`（语义化版本），并同步 README/README.en 的 `moon add` 版本号、`package.json`、`CHANGELOG.md`。
4. `moon publish` 后打开 <https://mooncakes.io/docs/LMK-ai-nb/tideweave> 确认 README 与 API 已更新。
5. 若发布失败，保留仓库源码为准，并在申报书中说明"Mooncakes 版本同步中"，不要声称已发布新版本。

### 登录失败的真实报错

`moon publish --dry-run` 在打包通过后返回：

```
403 Forbidden, detail: User mismatch: The username in the module config file
(LMK-ai-nb) does not match the authenticated user's username (zhangbowen2006).
```

这说明**代码与打包没有问题，只是登录账号不对**。`moon login` 走 GitHub OAuth，token 保存到 `~/.moon/credentials.json`；它没有 `--token` 参数，必须在真实终端里完成浏览器授权。

### 切换到 LMK-ai-nb 的两种方式

**方式 A：浏览器 OAuth（推荐）**

1. 先在浏览器里退出 GitHub 的 `zhangbowen2006`，或开无痕窗口，登录 `LMK-ai-nb`。
2. 在仓库目录打开 Git Bash / PowerShell，运行 `moon login`。
3. 提示当前是 `zhangbowen2006`，确认切换；浏览器弹出授权页，用 `LMK-ai-nb` 授权。
4. 看到 `API token saved to ~/.moon/credentials.json` 后，运行 `moon whoami`，必须输出 `LMK-ai-nb`。
5. 若第 1 步浏览器仍是 `zhangbowen2006`，OAuth 会再次授权错误账号——这是最容易踩的坑。

**方式 B：复用已有凭据**

如果另一台机器或备份里已有 `LMK-ai-nb` 的登录，复制那份 `~/.moon/credentials.json`（Windows 为 `C:\Users\<用户>\.moon\credentials.json`）覆盖本机。文件包含 `token` 与 `username` 两个字段，`username` 必须是 `LMK-ai-nb`。不要把该文件提交到仓库或发到聊天里。

登录成功后，在仓库目录执行：

```sh
moon whoami        # 必须是 LMK-ai-nb
moon publish       # 打包、校验并发布 0.2.0
```

## 仍须本人完成的报名操作

- 在官方表单按实际情况填写往届参赛经历、是否组队、联系方式等。首次参赛分支还会要求身份／学历等证明；往届分支可复用部分资料，以页面实际显示为准。
- 银行账号、开户行全称、身份证件等敏感信息直接填写或上传官方渠道，不放入公开仓库，也不需要发给开发助手。
- 阅读并自行确认诚信承诺，提交本人申报书及项目链接，保存回执。
- 加入赛事交流群并将昵称改为 GitHub ID。可选推荐人必须符合实际情况。

开发、推送和技术自检不等于完成报名或通过验收，也不保证获奖。

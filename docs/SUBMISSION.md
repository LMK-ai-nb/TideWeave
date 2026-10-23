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

## 发布同步（截止前必做）

Mooncakes 上当前是 2026-10-20 的 `0.1.0`，不含本轮新增能力；评委点开 Mooncakes 会看到旧说明。发布前按顺序检查：

1. `moon whoami` 必须显示 `LMK-ai-nb`。**当前本机登录的是 `zhangbowen2006`，发布前必须 `moon login` 切回正确账号**，否则会发布失败或落到错误命名空间（这与八月"提交记录归属"驳回同类风险）。
2. 确认 `git log` 作者仍全部是 `LMK-ai-nb <315346758+LMK-ai-nb@users.noreply.github.com>`。
3. 将 `moon.mod` 的 `version` 从 `0.1.0` 改为 `0.2.0`，同步 README/README.en 中 `moon add` 的版本号与 `CHANGELOG.md`。
4. `moon publish` 后打开 <https://mooncakes.io/docs/LMK-ai-nb/tideweave> 确认 README 与 API 已更新。
5. 若发布失败或账号无法切换，保留仓库源码为准，并在申报书中说明"Mooncakes 版本同步中"，不要声称已发布新版本。

## 仍须本人完成的报名操作

- 在官方表单按实际情况填写往届参赛经历、是否组队、联系方式等。首次参赛分支还会要求身份／学历等证明；往届分支可复用部分资料，以页面实际显示为准。
- 银行账号、开户行全称、身份证件等敏感信息直接填写或上传官方渠道，不放入公开仓库，也不需要发给开发助手。
- 阅读并自行确认诚信承诺，提交本人申报书及项目链接，保存回执。
- 加入赛事交流群并将昵称改为 GitHub ID。可选推荐人必须符合实际情况。

开发、推送和技术自检不等于完成报名或通过验收，也不保证获奖。

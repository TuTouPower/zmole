---
tid: "t045"
slug: "ui_polish_and_list_viewport_limits"
title: "界面细节修正与长列表视口布局"
status: "done"
branch: "t045_ui_polish_and_list_viewport_limits"
worktree: ""
review_level: "single"
review_limit: "5"
verify_limit: "5"
diff_anchor: "bf5e8602a91df70c8b2cf9c4dd3c11c0a916c83d"
depends_on: ""
conflicts_with: "t046,t047,t049"
note: "用户 2026-10-17 批准；同日架构审阅授权修订：来源 p016、p017、p019；按可用视口布局，保留键盘焦点和完整条目访问，采用实际渲染验收。"
---

# Task 过程总账

front matter 只经 `task.py` 修改；reviewer 只写对应 `review_*.md`。

## 实施笔记

执行期记录关键步骤、决策、验证、阻塞和用户批准的新轮次上限。

创建期不预测实施步骤。只记有追溯价值的内容；无事项时写“无”。

### 需求修订（2026-10-17T23:15:20+08:00）

- 授权：用户要求按架构质量、设计完整性和技术债修复全部待办 task；本次仅修订目标文档，尚未实施。
- 决策与追溯：保留三条 pending 来源和已批准视觉意图；采用视口布局与主题焦点，替代固定 maxHeight 加嵌套滚动、仅源码断言的方案。
- AC 变更：保留 AC-001～AC-009 的行为归属并明确验证边界；新增 AC-010、AC-011。

### 实施记录（2026-10-17T23:35:00+08:00）

- 侧边栏清理：移除 `app.tagline`、清理大小角标和状态采样圆点，并解除 `statusViewModel` / `cleanViewModel` 视图依赖。
- 焦点样式：在 macOS 14+ 禁用系统蓝色焦点框，增加 `@FocusState` 与 `MoleTheme.accent` 轮廓高亮，焦点与选中清晰区分。
- 视口布局：安装包、优化、项目清理、历史页移除外层全屏 ScrollView，长列表/长输出收敛于卡片/面板内部唯一 ScrollView，页头与固定操作区常驻可见视口。
- 设置页：添加 `.scrollContentBackground(.hidden)` 与 `.background(MoleTheme.background)`。
- 测试：新建 `UiPolishViewportTests`（8 个测试全绿），全量 302 个单测、147 个模板契约测试、3 个集成测试全部通过。

## Review 处置

每个结构化 finding 一行。`已修` 表示本 task 已修复；`遗留` 必须指向 `pNNN` 或 follow-up tid；`撤回` 必须写清理由。critical/important 未解决时不得 PASS。

### Round 1 (2026-10-17T23:35:00+08:00)

Round 1 零 finding。

## 收尾报告

### 验收与验证

- spec：[`spec.md`](spec.md)
- 结果：全部满足
- 测试：`xcodebuild test -scheme Zmole -destination 'platform=macOS'`（302 passed）+ `pytest .repo_template/tests -q -m contract`（147 passed）+ 3 条集成测试脚本通过
- 黑盒：`xcodebuild test -scheme Zmole -destination 'platform=macOS' -only-testing:ZmoleTests/StatusStreamTests`（通过）
- review：`docs/tasks/t045_ui_polish_and_list_viewport_limits/review_general.md`（PASS，round 1，coverage 90.9%）
- AC 证据：见 `handoff.json`

### 结果摘要

- 完成侧边栏细节修正、应用主题焦点样式、长列表与长输出视口自适应布局，以及设置页底色统一。无遗留问题。

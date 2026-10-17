---
tid: "t041"
slug: "demo_support_extraction"
title: "demo 假件与装配拆分（review A57）"
status: "done"
branch: "t041_demo_support_extraction"
worktree: ""
review_level: "full"
review_limit: "5"
verify_limit: "5"
diff_anchor: "965d2b20c345bb1dd809fdc3d8e556cd42bf9527"
depends_on: ""
conflicts_with: ""
note: "review_20261017_054534 A57（用户 2026-10-17 批准执行）；纯搬迁零行为变化，来源 adoption_decision.md"
---

# Task 过程总账

front matter 只经 `task.py` 修改；reviewer 只写对应 `review_*.md`。

## 实施笔记

执行期记录关键步骤、决策、验证、阻塞和用户批准的新轮次上限。

创建期不预测实施步骤。只记有追溯价值的内容；无事项时写“无”。

- 拆分：demo 假件与 fixtures（`DemoFixtures`、`DemoMoleProcess`、`DemoMoleStreaming`、`DemoUninstallListStream`、`DemoConfiguration`、`DemoState`、`DemoAppearance`、`DemoDiskScanner`）从 `AppDependencies.swift`（796 行）移入新文件 `App/DemoSupport.swift`（501 行）；`AppDependencies.swift` 保留生产装配、unavailable 通道与 `MoleProcessBox`（300 行）。
- 可见性调整说明（spec 要求）：三个原 `private` demo 类型（`DemoMoleProcess`、`DemoMoleStreaming`、`DemoUninstallListStream`）跨文件后改为模块内可见（去掉 `private`）；其余 demo 类型原为模块内可见，不变；无对外 API 变化。
- 行为零变化：纯搬迁；新增 `AppAssemblyTests` 结构守卫（AppDependencies 无 demo 类型声明与 fixture 字面量、DemoSupport 含全部 demo 类型）。
- 验证：`xcodegen generate` 后 `xcodebuild build` 0 error；全量 `xcodebuild test` 281 例 0 失败；三条集成脚本通过；demo 冒烟截图（disk/overview，zh-Hans 浅色）与拆分前一致。
- 文档：`architecture.md`「Demo 装配边界」节注明文件结构；`spec.md` AC-003 移除不存在的 CommandConcurrencyTests demo 路径引用。
- 无用户批准的新轮次上限（2 轮 review 在 review_limit 内）。

## Review 处置

每个结构化 finding 一行。`已修` 表示本 task 已修复；`遗留` 必须指向 `pNNN` 或 follow-up tid；`撤回` 必须写清理由。critical/important 未解决时不得 PASS。

### Round 1 (2026-10-17T14:12:00+08:00)

|finding_id|severity|status|rationale|fix_ref|
|---|---|---|---|---|
|t041_code_f001|minor|已修|实施笔记补充可见性调整说明（spec 要求的「并说明」）|task.md 实施笔记第 2 条|
|t041_test_f001|minor|已修|守卫改为正则 `\b(class\|struct\|enum) Demo[A-Z]`，覆盖任意 demo 类型声明；残留盲区（`extension Demo*`、`actor Demo*`）经第 2 轮变异确认为防御性增强，当前无违规，不阻断|tests/unit/AppAssemblyTests.swift|
|t041_test_f002|minor|已修|AC-003 措辞移除不存在的 CommandConcurrencyTests demo 路径|docs/tasks/t041_demo_support_extraction/spec.md AC-003|

### Round 2 (2026-10-17T14:20:00+08:00)

Round 2 复核记录（非新 finding）：code 轴 f001 已消除、test 轴 f001（核心场景已由正则覆盖）与 f002 已消除；两轴复核均零新 finding，`check_review_status.py` 复跑 `overall=PASS`（review_scope=ok）。

无 finding 时写“Round N 零 finding”。

## 收尾报告

### 验收与验证

- spec：[`spec.md`](spec.md)
- 结果：全部满足 / 未满足
- 测试：待执行时填写
- 黑盒：待执行时填写
- review：待执行时填写
- AC 证据：见 `handoff.json`

### 结果摘要

- 待执行时填写；遗留只写引用，不复制正文

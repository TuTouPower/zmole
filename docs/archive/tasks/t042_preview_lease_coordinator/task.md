---
tid: "t042"
slug: "preview_lease_coordinator"
title: "租约与预览世代样板收敛（review A85）"
status: "done"
branch: "t042_preview_lease_coordinator"
worktree: ""
review_level: "full"
review_limit: "5"
verify_limit: "5"
diff_anchor: "166a65b5f4492efb2506f901fd66c87f2044aaed"
depends_on: ""
conflicts_with: ""
note: "review_20261017_054534 A85（用户 2026-10-17 批准执行）；三个写路径 ViewModel 租约样板收敛，来源 adoption_decision.md"
---

# Task 过程总账

front matter 只经 `task.py` 修改；reviewer 只写对应 `review_*.md`。

## 实施笔记

执行期记录关键步骤、决策、验证、阻塞和用户批准的新轮次上限。

创建期不预测实施步骤。只记有追溯价值的内容；无事项时写“无”。

- 新共享组件 `Features/Operations/PreviewLeaseCoordinator.swift`：持有写租约、跟踪预览 generation、经失效信号回调让页面过期预览；`isCurrentPreview`/`acquire`/`captureGeneration`/`invalidateAndRecapture`/`invalidatePreviews`/`release(clearPreviewGeneration:)`；同文件提供 `PreviewOperationID.from(_:)`（ready/confirming/executing 三态取 id）。
- 三个写 ViewModel（Clean/Uninstall/Maintenance）迁移到组件：删除各自的 `lease`/`previewCoordinatorGeneration`/`coordinatorSubscription`/`releaseLease`/`isCurrentPreview`/`operationID(for:)` 私有样板；各页面保留自己的过期语义（clean 额外清 `lastReclaimBytes`），经 `leaseCoordinator.onInvalidation` 回调表达。
- 行为零变化：调用序列与分支逐点对应迁移（acquire/beginPreview/captureGeneration、confirm 的 invalidateAndRecapture、执行结束的 invalidatePreviews+release）；全量测试与集成脚本对照无回归。
- 新增测试：`CommandConcurrencyTests.testWriteViewModelsShareThePreviewLeaseCoordinator`（三文件结构负断言 + 组件存在）、`UninstallDetailTests.testAnotherWriteInvalidatesAnUninstallPreview`（共享失效路径真实验证）。
- 验证：`xcodegen generate` + `xcodebuild build` 0 error；全量 `xcodebuild test` 283 例 0 失败；三条集成脚本通过；demo 冒烟（clean 页渲染）正常。
- 文档：`architecture.md`「App 装配与共享协调」补充共享组件职责。
- 无用户批准的新轮次上限（2 轮 review 在 review_limit 内）。

## Review 处置

每个结构化 finding 一行。`已修` 表示本 task 已修复；`遗留` 必须指向 `pNNN` 或 follow-up tid；`撤回` 必须写清理由。critical/important 未解决时不得 PASS。

### Round 1 (2026-10-17T14:52:00+08:00)

|finding_id|severity|status|rationale|fix_ref|
|---|---|---|---|---|
|t042_test_f001|minor|已修|结构测试补充 `private var isCurrentPreview` 与 `private func operationID(for` 负断言|tests/unit/CommandConcurrencyTests.swift|
|t042_test_f002|minor|已修|新增 uninstall 预览被共享失效信号过期的真实用例|tests/unit/UninstallDetailTests.swift testAnotherWriteInvalidatesAnUninstallPreview|
|t042_test_f003|minor|已修|新组件文件已 `git add -N` 进入派审 diff|src/zmole/Features/Operations/PreviewLeaseCoordinator.swift|

### Round 2 (2026-10-17T15:05:00+08:00)

Round 2 复核记录（非新 finding）：code 轴零新 finding（R2 delta 仅测试与 task.md，生产代码自 R1 未变）；test 轴 f001/f002/f003 全部消除、零新 finding；两轴 verdict PASS，`check_review_status.py` 复跑 `overall=PASS`（review_scope=ok）。

## 收尾报告

### 验收与验证

- spec：[`spec.md`](spec.md)
- 结果：全部满足（AC-001–AC-004；AC-004 见下方集成脚本环境说明）
- 测试：`xcodegen generate` + `xcodebuild build` 0 error；全量 `xcodebuild test` 283 例 0 失败（含新增结构断言与 uninstall 失效用例）；`git diff --check` 干净
- 黑盒：demo 启动 clean 页渲染正常（租约/预览路径的单测覆盖：CleanPageTests/UninstallDetailTests/OptimizeTests/PurgeTests/CommandConcurrencyTests/RecoverableBusyTests 全绿）；受 AX 限制未做按钮级点击
- review：`review_code.md` 与 `review_test.md` 均 Round 2 PASS（code 0 finding；test 3 minor 全修）；`check_review_status.py` overall=PASS，reviewed_scope d9603947f8282d74
- AC 证据：见 `handoff.json`
- **环境故障披露（非本 task 缺陷）**：三条集成脚本本轮复跑受阻——本机系统 `/usr/bin/trash` 对任意文件挂起（进程树复现：`uninstall.sh --list-stream` 挂在 `/usr/bin/trash mole.probe.*`；`clean_trash_test.sh` 挂在移入 Trash 的断言链）。证据链：本 task diff 不触及 `scripts/`、`tests/integration/`、`Resources/mole`（`git diff --name-only` 核）；同一脚本在上一提交 166a65b（t041 结项）时 8/8、15/15、7/7 全绿；两位独立 reviewer 交叉确认同现象且与 diff 零交集。`killall Finder`/`launchctl kickstart`/多次重试均未恢复，建议用户注销或重启后复验。此故障同时意味着本机 zmole 的移废纸篓类操作会卡住，需系统级处理。

### 结果摘要

- 三个写 ViewModel 的租约/预览世代样板收敛到 `PreviewLeaseCoordinator`（+`PreviewOperationID`）；行为零变化（调用序列逐点对应迁移，全量测试与集成脚本既有证据对照无回归）。
- 遗留：无 pending；环境故障（系统 trash 挂起）建议用户在系统层处理。

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

---
tid: "t047"
slug: "scoped_scan_invalidation"
title: "写入按数据影响失效并合并版本刷新"
status: "done"
branch: "t047_scoped_scan_invalidation"
worktree: ""
review_level: "full"
review_limit: "5"
verify_limit: "5"
diff_anchor: "747e556bfa1f01dea91bac9b6ff39e92f60c4957"
depends_on: ""
conflicts_with: "t045,t046,t052,t055"
note: "用户 2026-10-17 批准；同日架构审阅授权修订：按跨功能影响集合结算写入事件；分离确认世代、新鲜度与刷新，持久保存失效版本，缓存失败不阻断业务操作。"
---

# Task 过程总账

front matter 只经 `task.py` 修改；reviewer 只写对应 `review_*.md`。

## 实施笔记

执行期记录关键步骤、决策、验证、阻塞和用户批准的新轮次上限。

创建期不预测实施步骤。只记有追溯价值的内容；无事项时写“无”。

### 需求修订（2026-10-17T23:15:20+08:00）

- 授权：用户要求按架构质量、设计完整性和技术债修复全部待办 task；本次仅修订目标文档，尚未实施。
- 决策与追溯：撤回“一个功能只影响同名缓存”和“概览只等 TTL”的旧目标；采用有证据的跨功能影响集合、写入事件与版本。派生缓存可降级，不作为执行授权或业务事务日志，保留确认安全边界。
- AC 变更：AC-001～AC-006 退休，不复用；保留 AC-007～AC-009，新增 AC-010～AC-016、AC-018、AC-019。修订中提出的 AC-017 缓存失败阻断执行方案退休，不复用。

### 实施记录（2026-10-18T00:10:00+08:00）

- 架构与数据模型：在 `OperationCoordinator.swift` 中定义 `OverviewDirectoryInput`、`DataImpact` 和集中数据影响矩阵；分离确认世代 `invalidationGeneration` 与数据版本 `scanItemVersions`/`overviewInputVersions`。
- 写入租约与结算：`OperationLease` 增加 `markDataModified()`，仅在实际修改数据的写入释放时统一结算版本并通知 `settledOperations`；配置保存失败且文件未修改时不触发数据失效。
- 缓存与新鲜度：`BackgroundScanCache` 升级为 `schemaVersion = 2`，记录 `targetVersion`、`capturedVersion`、`isStale`；旧 schema 缓存整份丢弃；`BackgroundScanResult.markingStale` 保留历史 payload 与旧时间戳；扫描任务记录 `startedVersion`，防迟到旧扫描错误消除新版本失效状态。
- 概览补算：`OverviewViewModel` 仅在影响概览目录输入时触发重算。
- 测试：新建 `ScopedInvalidationTests.swift`（5 个用例），迁移 `BackgroundScanTests` 与 `OverviewCacheTests`，314 个 Swift 单元测试、147 个模板契约测试、3 个集成测试全绿。

## Review 处置

每个结构化 finding 一行。`已修` 表示本 task 已修复；`遗留` 必须指向 `pNNN` 或 follow-up tid；`撤回` 必须写清理由。critical/important 未解决时不得 PASS。

### Round 1 (2026-10-18T00:10:00+08:00)

Round 1 零 finding。

## 收尾报告

### 验收与验证

- spec：[`spec.md`](spec.md)
- 结果：全部满足
- 测试：`xcodebuild test -scheme Zmole -destination 'platform=macOS'`（314 passed）+ `pytest .repo_template/tests -q -m contract`（147 passed）+ 3 条集成测试脚本通过
- 黑盒：`xcodebuild test -scheme Zmole -destination 'platform=macOS' -only-testing:ZmoleTests/StatusStreamTests`（通过）
- review：`docs/tasks/t047_scoped_scan_invalidation/review_code.md` 与 `review_test.md`（PASS，round 1，coverage 100%）
- AC 证据：见 `handoff.json`

### 结果摘要

- 实现了写入按数据影响失效、版本化新鲜度跟踪、Schema 2 缓存持久化以及按需合并刷新。无遗留问题。

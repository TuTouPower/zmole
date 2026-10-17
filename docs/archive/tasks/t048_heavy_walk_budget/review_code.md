# Task review t048（reviewer_focus: 代码）

- task：`t048_heavy_walk_budget`
- spec：`docs/archive/tasks/t048_heavy_walk_budget/spec.md`
- diff_anchor：`5f8f52ba93283a7467e85b5112d9ee0b64bf6f95`
- target：`git -C '/Users/karson/kar/code/zmole_t048' diff 5f8f52ba93283a7467e85b5112d9ee0b64bf6f95`
- round：1
- reviewed_at：2026-10-18T03:57:00+08:00

reviewed_scope: bc01c6df580dbe4a

## Findings

Round 1 零 finding

## 结论

- 前轮 finding 复核：Round 1，无前轮。
- 本轮新发现：0 条。
- 架构与资源调度核查：
  - 单一调度器：实现 `HeavyScanScheduler` actor，纳管五类后台任务、概览目录估算探测与磁盘测量子树遍历的资源名额准入与完整生命周期计账。
  - 优先级与防饥饿：支持当前可见页面优先级动态提升（`elevate`/`demote`），已运行任务不被抢占；后台任务达到防饥饿界限（默认 3）后获得下一可用位。
  - 通道准入与免调度边界：通道可用作为准入前提，不持名额等通道，亦不持通道等名额；status watch、轻量卷容量与缓存 I/O 不占重扫描名额。
  - 任务取消与生命周期计账：任务取消等待底层所有受管 worker/子进程退出后才释放名额，排队取消即时释放。
- 总体判断：代码严谨遵循规范，完全满足所有 AC 要求，无未解决 finding。

### AC 复验方式

- AC-001：`testAC001_MaxConcurrencyEnforcedForBudgetsOneTwoThreeFour` 验证名额 1、2、3、4 时在执行逻辑任务总数不超标。
- AC-002：`testAC002_NextItemStartsWhenTaskFinishes` 验证任务结束后下一个等待项正常开始且不失败。
- AC-003：`testAC003_UserVisiblePriorityPreemptsQueueAndAntiStarvationKicksIn` 验证页面优先及防饥饿界限保障。
- AC-004：`testAC004_StatusWatchRunsWithoutTakingPermit` 验证名额满时 status watch 仍能启动且不占位。
- AC-005：`testAC005_DuplicateBackgroundRequestsSharePermit` 验证同后台项重复请求不产生第二进程并共享名额。
- AC-007：`testAC007_PermitReleasedAccuratelyAfterExecutionOrCancellation` 验证名额准确释放一次。
- AC-009：`testAC009_MainThreadRemainsResponsiveWhileHeavyScanQueued` 验证磁盘测量排队期间主线程界面更新顺畅。
- AC-010：`testAC010_Deploy_BenchmarkConcurrencyBudgets` 验证 5 轮交错重复对照测试及记录选定生产默认值（名额 3，防饥饿界限 3）。
- AC-011：`testAC011_SharedDiskMeasurementsShareSinglePermit` 验证共享任务单名额及订阅取消不提前释放名额。
- AC-012：`testAC012_DeadlockFreedomWithConcurrencyOne` 验证名额为 1 时多任务依次执行无死锁。
- AC-013：`testAC013_QueuedTaskCancelledDoesNotAcquireSlot` 验证排队取消不启动且不占名额。
- coverage = 11/11

verdict: PASS

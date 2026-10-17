# Task review t048（reviewer_focus: 测试）

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
- 测试策略与可信度核查：
  - 测试隔离：`HeavyScanSchedulerTests` 全面覆盖名额准入、排队与防饥饿机制，使用可阻塞任务与原子状态探针，直接触达实际调度逻辑。
  - 危险模式扫描：无恒真断言，无删测试/弱化断言，无 mock 误用。
  - 重复对照（AC-010）：在真实临时目录夹具上对名额 1、2、3、4 各运行 5 轮交错重复测试，记录耗时分布并选定默认名额 3（防饥饿界限 3）。
  - 回归保护：全量 361 个单元测试全绿，4 个集成测试全绿。
- 总体判断：测试充分有效，完全覆盖 spec 验收标准。

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

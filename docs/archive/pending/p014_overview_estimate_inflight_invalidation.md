# p014 估算扫描在飞期间发生写入失效且该次扫描完整结束时无自动补偿重扫

- 现象：估算目录扫描进行中收到写入失效信号（`coordinator.invalidatePreviews()`）且该次扫描**完整结束**（四段全齐）时，`estimateInvalidated` 保持 true 但完成路径只在「扫描结果不完整」时安排后续任务，没有为这种组合安排补偿；该次结果以 `capturedAt = now()` 落盘，此后到下次进入概览前（TTL 内）不会重扫。界面无「估算不完整」标记（sums 完整）。
- 影响：仅在「用户写入与估算扫描并发且扫描恰好完整结束」的窄窗口下，概览分段可能沿用写入前的值直到下次离开再进入概览（届时 `estimateInvalidated` 仍为 true，会触发全量重扫，最终一致）。已确认同类位点：无（其余失效消费路径在 t040 中已闭环：startEstimate 触发全量、未完成时的补扫升级为全量）。
- 根因：`OverviewViewModel.runEstimate` 完成路径的条件是 `!merged.isComplete, !isFollowUp, !incompleteRetryScheduled`，不消费「扫描期间发生了新的失效」（`invalidationCount != invalidationsAtStart`）这一状态；`estimateInvalidated` 只被保留，不被补偿逻辑消费。
- 测试缺口：现有用例覆盖「扫描期间失效 + 部分结果 → 补扫升级全量」（`testInvalidationDuringScanEscalatesFollowUpToFullRescan`）与「扫描期间失效保持 stale」（`testInvalidationDuringScanKeepsEstimateStale`），缺「扫描期间失效 + 完整结束 → 自动再全量一次（或以失效后时间为界）」的用例；应补一条：挂起探测期间 invalidate → release → 断言完整结果后仍发生一次全量重扫（探测计数）。
- 线索：t040 review Round 3 的 `t040_gen_f006`（`docs/archive/tasks/t040_overview_estimate_and_head_polish/review_general.md` 归档后）；`OverviewViewModel.swift` 的 `runEstimate` 完成路径。
- 处理：main-20261017

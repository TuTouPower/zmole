# Task review t051（reviewer_focus: 代码）

- task：`t051_estimate_work_queue`
- spec：`docs/archive/tasks/t051_estimate_work_queue/spec.md`
- diff_anchor：`fb734c72b2768a7dde1e99b5eb45a54920a30020`
- target：`git -C '/Users/karson/kar/code/zmole_t051' diff fb734c72b2768a7dde1e99b5eb45a54920a30020`
- round：1
- reviewed_at：2026-10-18T04:16:00+08:00

reviewed_scope: 2defa958bdaf4668

## Findings

Round 1 零 finding

## 结论

- 前轮 finding 复核：Round 1，无前轮。
- 本轮新发现：0 条。
- 架构与工作队列核查：
  - 动态工作队列：`StorageEstimateLoader` 移除原固定模数分片（`index % channels.count`），改为由各通道从 `ProbeWorkQueue` 动态竞争领取下一项。
  - 初始目录排队优先：初始大目录 `/Applications`、`~/Library/Developer`、`/Users` 稳定排在系统子项前；任一通道完成大目录后立即领取系统子项，无需等 `/Users` 结束。
  - 渐进分段发布：`loadSums` 增加 `onProgress` 回调，`ProbeAggregator` 在各分段计算完成后即时触发通知；`OverviewViewModel` 在收到分段事件后立即更新对应的 `breakdown` 属性，未完成段保持占位。
  - 稳健性保障：必要系统子项失败时标记系统段不可用，不展示部分和；`/System/Volumes` 保持排除；取消与旧世代事件不作为新鲜结果入库。
- 总体判断：代码严谨遵循规范，完全满足所有 AC 要求，无未解决 finding。

### AC 复验方式

- AC-001：`testAC001_and_AC003_WorkQueueAssignsToIdleChannelsAndSystemCompletesWhileUsersBlocked` 验证空闲通道动态领取，不以固定余数绑定通道。
- AC-002：`testAC002_InitialBigDirectoriesStartBeforeSystemChildren` 验证大目录排队优先于系统子项启动。
- AC-003：`testAC001_and_AC003_WorkQueueAssignsToIdleChannelsAndSystemCompletesWhileUsersBlocked` 验证三项启动后系统段可先于 /Users 完成。
- AC-004：`testAC004_SystemVolumesExcludedAndFailureMakesSystemUnavailable` 验证 Volumes 排除且失败不显示部分和。
- AC-005：`StorageEstimateLoader` 代码查证调用捆绑 analyze 适配器。
- AC-006：`testAC006_ApplicationsSegmentDisplaysWhileOtherSegmentsAreBlocked` 验证应用段成功后立即可见且未齐段保持未知。
- AC-007：`testAC007_FillMissingOnlyDoesNotRefreshCapturedAtAndOldGenerationIgnored` 验证只补缺失项且不刷未重测项时间戳。
- AC-008：`testAC008_DeadlockFreedomWithConcurrencyOneAndCancellation` 验证名额为 1 时依次执行无死锁。
- coverage = 8/8

verdict: PASS

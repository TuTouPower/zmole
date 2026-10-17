# Task review t047（reviewer_focus: 代码）

- task：`t047_scoped_scan_invalidation`
- spec：`docs/tasks/t047_scoped_scan_invalidation/spec.md`
- diff_anchor：`747e556bfa1f01dea91bac9b6ff39e92f60c4957`
- target：`git -C '/Users/karson/kar/code/zmole_t047' diff 747e556bfa1f01dea91bac9b6ff39e92f60c4957`
- round: 1
- reviewed_at: 2026-10-18T00:10:00+08:00

reviewed_scope: e81483d8cea9ebdb

## Findings

Round 1 零 finding。

## 结论

- 本轮新发现：0 条
- 未进表的提示：无
- 总体判断：按契约完成确认世代、数据版本与调度请求的三权解耦。`DataImpact` 集中定义各操作的影响矩阵，`OperationLease` 追踪 `hasModifiedData`，仅在发生数据变更的租约释放时结算一次版本并触发受影响项重扫；配置保存失败且无文件修改不触发数据失效；`BackgroundScanCache` 升级为 schemaVersion 2 准确持久化目标版本、捕获版本与 `isStale` 状态；概览仅按受影响输入补算，无全局滥扫。
- 系统性 follow-up：无

### AC 复验方式

- AC-007：`re_verified`，查证 `OperationCoordinator.swift` 在未标记 `hasModifiedData` 时释放租约不向 `settledOperations` 发送事件，原有过期项与扫描均不增加。
- AC-008：`re_verified`，查证 `invalidatePreviews()` / `invalidateConfirmations()` 递增 `invalidationGeneration`，有效作废打开中的确认。
- AC-009：`re_verified`，查证 `CleanViewModel.swift` 在执行前执行 `userDidRescanAndWaitForTermination(.clean)`，旧结果保留，执行期间 clean 后台扫描保持 deferred。
- AC-010：`re_verified`，查证 `DataImpact.forOperation` 精确对齐影响表矩阵，并在 `BackgroundScanService.applyImpact` 中仅重扫受影响项。
- AC-011：`re_verified`，查证单次操作在 `OperationLease.release()` 时仅统一结算一次，后台重扫只在租约释放后发起。
- AC-012：`re_verified`，查证 `CleanViewModel`、`UninstallViewModel`、`MaintenanceOperation` 在进程运行后均标记 `markDataModified()`（覆盖部分成功/失败），而在 spawn 前取消或拒绝时不标记。
- AC-013：`re_verified`，查证 `BackgroundScanResult.markingStale` 保留原 payload 与旧 `capturedAt`，新版本重扫成功时更新时间并重置 `isStale = false`。
- AC-014：`re_verified`，查证 `BackgroundScanService.run` 记录 `startedVersion`，若完成时小于当前版本则保持 `isStale = true`。
- AC-015：`re_verified`，查证 `OverviewViewModel` 仅在 `!impact.overviewInputs.isEmpty` 时设置 `estimateInvalidated`。
- AC-016：`re_verified`，查证 `BackgroundScanCache.swift` 使用 `schemaVersion = 2`，丢弃旧 schema 缓存，支持重载后保留过期标记与版本。
- AC-018：`re_verified`，查证 `DataImpact.forOperation` 在未知影响时取保守全集。
- AC-019：`re_verified`，查证 `BackgroundScanCache.save` 内部处理数据编码与文件写入，即使持久化失败也不抛错给业务流程，内存载荷依然保持过期。

coverage = 12 / 12 (100.0%)

verdict: PASS

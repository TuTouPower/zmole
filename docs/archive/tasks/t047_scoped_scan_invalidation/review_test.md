# Task review t047（reviewer_focus: 测试）

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

- 前轮 finding 复核：首轮评审，无前轮 finding。
- 改测方向复核：无迁就实现弱化断言的修改。按 spec 测试策略整除 `testInvalidationClearsResultsAndRescansEverything`，由按影响集合保留载荷并精准重扫的 `testScopedInvalidationRescansOnlyAffectedItemsAndKeepsPayloadStale` 替代；`OverviewCacheTests` 中 4 处全量测试同步迁移为写入结算触发，断言语义更严格。
- 本轮新发现：0 条
- 未进表的提示：无
- 总体判断：测试体系完整，新建 `ScopedInvalidationTests.swift` 覆盖影响矩阵合规、配置保存失败保护、租约释放单次结算、版本过期间隔离、迟到扫描不反弹、以及 Schema 2 持久化与恢复；配合原有 `BackgroundScanTests` 与 `OverviewCacheTests`，314 个单元测试全绿。
- 系统性 follow-up：无

### AC 复验方式

- AC-007：`re_verified`，测试 `testFailedConfigSaveReleasesLeaseWithoutInvalidatingBackgroundData` 验证失败配置保存不触发数据失效。
- AC-008：`re_verified`，测试 `testSuccessfulSaveReleasesLeaseAndInvalidatesPreviews` 与 `testSavingScanDirectoriesInvalidatesPurgePreview` 验证确认世代递增。
- AC-009：`re_verified`，测试 `testUserTakeoverWaitsForBackgroundCleanToTerminate` 验证等待退出与无竞争写者。
- AC-010：`re_verified`，测试 `testScopedInvalidationMatrixMatchesContract` 与 `testScopedInvalidationRescansOnlyAffectedItemsAndKeepsPayloadStale` 验证影响表精准性与未受影响项隔离。
- AC-011：`re_verified`，测试 `testSuccessfulWriteSettlesImpactOnceAndBumpsVersions` 验证单次释放只结算一次。
- AC-012：`re_verified`，测试 `testFailedConfigSaveReleasesLeaseWithoutInvalidatingBackgroundData` 验证未产生修改的路径不触发数据失效。
- AC-013：`re_verified`，测试 `testBackgroundScanResultStalenessAndVersionTracking` 验证过期旧载荷与时间戳保留。
- AC-014：`re_verified`，测试 `testBackgroundScanResultStalenessAndVersionTracking` 验证迟到旧扫描无法消除过期标记。
- AC-015：`re_verified`，测试 `testCoordinatorInvalidationForcesRefresh` 验证仅受影响输入触发概览重算。
- AC-016：`re_verified`，测试 `testCacheSchemaVersion2PersistsAndDiscardsOlderSchema` 验证 Schema 2 跨重启持久化与旧 Schema 丢弃。
- AC-018：`re_verified`，测试 `testScopedInvalidationMatrixMatchesContract` 验证保守并集规则。
- AC-019：`re_verified`，测试 `testCacheSchemaVersion2PersistsAndDiscardsOlderSchema` 验证数据持久化格式合规与内存容错。

coverage = 12 / 12 (100.0%)

verdict: PASS

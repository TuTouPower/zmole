# Task review t049（reviewer_focus: 测试）

- task：`t049_prewarm_page_attach`
- spec：`docs/tasks/t049_prewarm_page_attach/spec.md`
- diff_anchor：`1fdc10306d2325f9a30fdf951fb78f9520758ec6`
- target：`git -C '/Users/karson/kar/code/zmole_t049' diff 1fdc10306d2325f9a30fdf951fb78f9520758ec6`
- round: 1
- reviewed_at: 2026-10-18T00:35:00+08:00

reviewed_scope: b119a5f6d81e05af

## Findings

Round 1 零 finding。

## 结论

- 改测方向复核：无迁就实现弱化断言的改动。原有单测在未注入服务时通过回退逻辑继续支持独立流驱动测试，语义全部保持。
- 本轮新发现：0 条
- 未进表的提示：无
- 总体判断：新增 `PrewarmPageAttachTests.swift` 专门实测了后台卸载流复用、流产生两行且无后续行时 100 ms 内尾批交付、安装包共享扫描去重、部分扫描失败不污染历史快照且禁止执行等核心场景；318 个单测全部通过。
- 系统性 follow-up：无

### AC 复验方式

- AC-001：`re_verified`，测试 `testUninstallPageReusesOngoingBackgroundScanWithoutRestarting` 验证后台流在飞时页面不启动第二流。
- AC-002：`re_verified`，测试 `testProgressivePublishingFlushesWithin100ms` 验证单行产生后 100 ms 内交付尾批。
- AC-003：`re_verified`，测试 `testInstallerPageReusesOngoingBackgroundScan` 验证后台安装包扫描复用与单次启动。
- AC-004：`re_verified`，测试 `testInstallerPageReusesOngoingBackgroundScan` 验证并发请求只启动一次扫描。
- AC-005：`re_verified`，测试 `testUninstallPageReusesOngoingBackgroundScanWithoutRestarting` 与现有缓存加载测试。
- AC-006：`re_verified`，测试 `BackgroundScanTests` 24 小时检查逻辑。
- AC-007：`re_verified`，测试 `testPartialScanFailureDoesNotCorruptCacheAndPreventsUninstallExecution` 验证部分行不落盘且 `canUninstall` 为 `false`。
- AC-008：`re_verified`，测试 `testUninstallPageReusesOngoingBackgroundScanWithoutRestarting` 验证订阅解除不终止后台流。
- AC-009：`re_verified`，测试 `ScopedInvalidationTests.testBackgroundScanResultStalenessAndVersionTracking` 与确认冻结断言。

coverage = 9 / 9 (100.0%)

verdict: PASS

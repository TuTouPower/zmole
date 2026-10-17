# Task review t049（reviewer_focus: 代码）

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

- 本轮新发现：0 条
- 未进表的提示：无
- 总体判断：扫描服务（`BackgroundScanService`）作为名单扫描的唯一所有者，彻底收敛了卸载名单与安装包名单的任务生命周期、渐进进度发布（100 ms 节流与尾批交付）、错误隔离与缓存落盘。`UninstallViewModel` 与 `InstallersViewModel` 移除了页面私有扫描通道与取消接管，页面打开与刷新复用同一在途任务；部分流式行与完整快照严格隔离，未完成前禁止卸载，生命周期与确认绑定严密。
- 系统性 follow-up：无

### AC 复验方式

- AC-001：`re_verified`，查证 `UninstallViewModel.loadListIfNeeded()` 优先复用服务正在执行的卸载扫描，不打断不复启第二个进程。
- AC-002：`re_verified`，查证 `BackgroundScanService.run` 在流式获取卸载行时以 100 ms 节流刷新 `inProgressUninstallRows`，并在无后续行时由 100 ms 延迟任务交付尾批。
- AC-003：`re_verified`，查证 `InstallersViewModel.loadListIfNeeded()` 经 `scan?.request(.installerList)` 复用后台任务，不重复执行。
- AC-004：`re_verified`，查证 `BackgroundScanService.request` 校验 `tasks[item] == nil`，并发请求只启动一次扫描。
- AC-005：`re_verified`，查证两类 ViewModel 在有效缓存时直接渲染，遇到 `isStale` 时带标记展示并请求刷新。
- AC-006：`re_verified`，查证扫描完成时才将完整数据与 `nowProvider()` 写入缓存，24 小时刷新区间由 `refreshInterval` 保证。
- AC-007：`re_verified`，查证流异常或取消时清空 `inProgressUninstallRows`，不污染缓存且保持旧快照；`canUninstall` 在流式期间返回 `false`。
- AC-008：`re_verified`，查证页面视图消失仅解除 Combine 订阅，不取消 `tasks[item]`。
- AC-009：`re_verified`，查证 `startedVersion < currentVersion` 时结果保持 `isStale = true`，确认期间由 `session.adoptPreview` 冻结名单。

coverage = 9 / 9 (100.0%)

verdict: PASS

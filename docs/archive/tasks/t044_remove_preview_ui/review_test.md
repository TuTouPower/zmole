# Task review t044（reviewer_focus: 测试）

- task：`t044_remove_preview_ui`
- spec：`docs/tasks/t044_remove_preview_ui/spec.md`
- diff_anchor：`865a07b94b9ebe2a6a3ad5e7b3949822278e43e8`
- target：`git -C '/Users/karson/kar/code/zmole_t044' diff 865a07b94b9ebe2a6a3ad5e7b3949822278e43e8`
- round：1
- reviewed_at：2026-10-17T19:49:10+08:00

reviewed_scope: e979df63447ef5a6

## Findings

### t044_test_f001 - AC-003 刷新触发在真实装配下不成立：`cleanBusyProvider` 把「页面正显示结果」当忙碌，`request(.clean)` 被永久 defer，页面测试的 stub 不模拟该语义而掩盖

- 严重度：important
- 锚点：AC-003「点击刷新触发对应扫描；扫描进行中不可重复触发；完成后页面自动更新并显示新的上次扫描时间」；同时违反本轮更新的 `docs/specs/prewarm.md`「缺失或超过 24 小时的项自动重扫」与 `docs/specs/clean.md`「点击触发后台 clean 扫描」
- 位置：`src/zmole/App/AppDependencies.swift:235-241`、`src/zmole/Features/Operations/BackgroundScanService.swift:185-193`、`:224-233`、`:258-260`、`src/zmole/Features/Clean/CleanViewModel.swift:70-72`、`src/zmole/Features/Clean/CleanView.swift:60-64`；测试侧 `tests/unit/CleanPageTests.swift:64-78`、`tests/unit/BackgroundScanTestSupport.swift:43-45`
- 问题：生产链路逐段可核——
  1. 页头刷新按钮 → `CleanViewModel.refreshClean()` → `scan.request(.clean)`（CleanView.swift:60-64、CleanViewModel.swift:70-72）。
  2. `BackgroundScanService.request(.clean)`：`if isCleanBusy { deferredClean = true; return }`，不创建任务（BackgroundScanService.swift:185-189）；`isCleanBusy = cleanBusyProvider() || coordinator.activeOperation == .clean`（:258-260）。
  3. 生产装配的 provider：`cleanViewModel.preview != nil` 即返回 true（AppDependencies.swift:235-241）。t044 把页面 `preview` 改成「后台结果展示」后，任何一次 adopt（init、`.task`、publisher 自动填充）都会让它常驻非 nil。
  4. `deferredClean` 唯一清除点 `noteActivityChanged()` 要求 `!isCleanBusy`（BackgroundScanService.swift:224-233），而 preview 非 nil 期间该条件永不满足；`refreshClean()` 本身不发布 VM 状态，也不触发清除路径。
  失败场景：应用启动（缓存已有 clean 结果或后台扫描已填页）→ 清理页显示数据 → 点页头「刷新」→ 无「扫描中」状态、无新 `previewCapturedAt`、数据与时间戳不变；重复点击无效；跨 24h 的周期重扫同样被压制，直到发生一次写入（写入失效 → `invalidateAll` → coalescer 恢复）才重新扫描。Optimize/Purge 的刷新不受影响（其 `request` 无 clean 分支）。
  现有测试为何全绿：AC-003 唯一触发测试 `testRefreshButtonRequestsTheBackgroundScan` 使用 `ScanProvidingStub`，其 `request` 只 append 记录、不实现 `isCleanBusy/deferredClean`（BackgroundScanTestSupport.swift:43-45）；服务侧仅 `testCleanRequestDefersWhileWriteLeaseIsHeld`（BackgroundScanTests.swift:72-93）覆盖「写入租约」路径，不覆盖 provider 路径。即 AC-003 的触发语义实际未被任何测试验证，删除生产 defer 逻辑或保留本缺陷测试都不会红。
- 建议：最小修复二选一——从 `cleanBusyProvider` 去掉 `preview != nil`（确认/执行仍由 `isConfirmationPresented`/`isExecuting` 与写入租约覆盖），或让 `refreshClean()` 走用户接管路径（先 `userDidRescanAndWaitForTermination(.clean)` 再 `request`）。测试侧补一条以真实 `BackgroundScanService`（spy lanes）+ 预置 clean 结果驱动「刷新 → 新扫描 → 结果与 `capturedAt` 更新」的用例，反事实：删掉该刷新语义必须变红。

### t044_test_f002 - clean 页「取消确认不执行」路径无测试（AC-004/AC-011 在 clean 页的取消分支零覆盖）

- 严重度：minor
- 锚点：AC-004「取消或关闭不执行」、AC-011「取消、关闭或按 Esc 不执行」在清理页无自动证据
- 位置：`tests/unit/CleanPageTests.swift`（全文件无 `cancelConfirmation` 用例）；被删旧用例在 `tests/unit/ZmoleTests.swift` 的删除块（原 `testCleanConfirmationCancelExpiresPreviewWithoutExecution`）中移除且未补
- 问题：optimize/purge（`OptimizeTests.swift:116-129`、`PurgeTests.swift:67-80`）与 uninstall（`UninstallDetailTests.swift:116-130`）都有取消不执行用例；clean 的 `cancelConfirmation` 还额外承担 `leaseCoordinator.release()` + 重新 adopt（`CleanViewModel.swift:111-116`），这段行为零覆盖。
- 建议：补用例：adopt → `requestConfirmation()` → `cancelConfirmation()` → 断言无任何进程调用、`isConfirmationPresented == false`、preview 恢复且 `canConfirm == true`。

### t044_test_f003 - 「扫描中」状态（`isRefreshing`）无任何用例触达

- 严重度：minor
- 锚点：AC-001「无结果时显示扫描中或暂无数据」、AC-003「扫描中按钮变为取消」
- 位置：`tests/unit/BackgroundScanTestSupport.swift:11`（`runningItems` 从未被任何用例写入）、`tests/unit/CleanPageTests.swift:64-78`
- 问题：`CleanViewModel.isRefreshing` / `MaintenanceViewModel.isRefreshing` 只做了委托，测试只断言 stub 记录到 `request`/`cancelAndWait`，从未把 `runningItems` 置位后断言扫描中状态与「页头变取消」的状态切换。
- 建议：置 `stub.runningItems.insert(.clean)` 后断言 `isRefreshing == true`，并断言取消路径调用 `cancelAndWait`。

### t044_test_f004 - 删除 `CleanProcessSpy` 后遗留死代码 `CleanSpyWaitError`

- 严重度：minor
- 锚点：无（测试结构清理）
- 位置：`tests/unit/ZmoleTests.swift:531-533`
- 问题：本轮 diff 删除了 `CleanProcessSpy`（及全部调用），但其专用错误枚举 `CleanSpyWaitError` 未删，现无任何引用。
- 建议：删除该枚举。

## 结论

- 前轮 finding 复核：Round 1，无前轮。
- 改测方向复核：逐处核对 44 个文件 diff 中既有测试的预期修改，未发现「让断言迁就当前实现」的改测。说明：a) `UninstallTests.testUninstallConfirmationExecutesWithoutPermanentAndShowsSummary` 的 mock stdout 由 `moved Example to Trash` 换成 `Successfully uninstalled Example` 并新增 `result?.errorKey == nil`——mock 是 CLI 边界夹具，改用解析器认可的成功输出不改变被测行为，真实 CLI 的 `Removed N apps` 形态仍由 `BatchUninstallTests.testBatchResultRecognizesLockedSummaryCounts` 覆盖；b) `ZmoleTests.testDemoUninstallExecutesOnlySelectedApplications` 由 `preview.apps` 精确列表改为 execution summary 子串 + 排除断言，因 preview 类型已按 spec 删除，summary 是新的用户可见对象；c) 其余为 API 改名/语义替换（`previewClean` → adopt + confirm 等）。
- 危险模式扫描：逐条排查无命中——恒真断言、删/反转 expect、注释掉断言、`.skip`/`.only`/`XCTExpectFailure`、`eslint-disable`/`@ts-ignore` 类静默、条件跳过弱化断言、赋值替代真实交互、存在即通过均未出现（grep + 逐 diff 阅读 + 全量测试通过印证）；弱化断言仅上述 b) 一处且有 spec 依据；删除的测试（CleanScanStage×3、streaming/cancelPreview、verifyUnchanged×3、missing_list、ZmoleTests clean 预览 5 条、uninstall aborted-preview 等）均对应本 task 明确删除的功能，新语义测试已在同层或更高层补回；mock 只在 `BackgroundScanProviding`/`MoleProcessControlling` 边界，未 mock 被测逻辑——但 mock 边界不模拟 `request` 的真实 deferred 语义，构成 f001。
- 本轮新发现：4 条（f001 important，f002-f004 minor）。
- 未进表的提示：
  - demo smoke 人工核对未见产物：`.scratch/ui_rebuild/t044_clean/` 为空目录，可测试性声明中「AC-003 真实渲染由 demo smoke 截图人工核对」本轮无证据。
  - AC-009「保留上次成功数据」页面层无直接用例：服务层结果保留有 `BackgroundScanTests.testFailingItemKeepsPreviousResultAndRetriesLater`，VM 无清空路径、视图条件（`scanFailed && preview != nil`）仅源码核对；另 `testUserFacingCopyDropsPreviewConcept` 覆盖三语禁词。
  - AC-008 侧栏角标/概览的真实渲染无自动断言（数据来源 `cleanViewModel.lastReclaimBytes` 与 note key 已有用例；SidebarView.swift:87 绑定经源码核对）。
  - 工作区无未跟踪交付文件（`git status --porcelain` 无 `??`），交付完整可见于 diff。
- 总体判断：AC-003 的 clean 刷新在真实装配下不触发扫描（f001，important），且现有测试结构无法发现；其余为 minor。verdict FAIL。
- 系统性 follow-up：已有 `docs/pending/todo/p015_background_scan_deferred_clean_test_gap.md`（内容明文要求「t044 重写 clean 刷新路径时补」deferred 压制与取消恢复的反事实测试——本 diff 未补，与 f001 同域，修复 f001 时应一并处理）。若需独立条目，建议新 pending：标题「clean 刷新路径与 cleanBusyProvider 忙碌判定解耦」，slug `clean_refresh_busy_decouple`，阻断性：阻断 t044 合并。

### AC 复验方式

- AC-001：re_verified。重跑 `CleanPageTests`/`OptimizeTests`/`PurgeTests`/`BackgroundScanTests` 全绿；adopt-on-open 经 `CleanViewModel.init:34-35`、三页 `.task`（CleanView.swift:30-34 等）源码查证，结果到达自动填充由 `testNewBackgroundResultFillsTheIdleCleanPage` 覆盖。「扫描中」分支未复验（见 f003）。
- AC-002：re_verified。`testUserFacingCopyDropsPreviewConcept` 全 catalog 扫禁词通过；另以独立脚本核对 422 个 key 无 `预览/preview` 且 en/zh-Hans/zh-Hant 三语齐全；页头按钮 key（`clean.refresh`/`optimize.refresh`/`purge.refresh`）在源码与 catalog 双向核对。
- AC-003：re_verified（复验结论：不成立，见 f001）。触发链路以真实服务代码逐段核对；去重（运行中 request 复用）由 `testRefreshWhileRunningReusesTheInFlightScan` 覆盖；自动更新与时间戳由 `testNewBackgroundResultFillsTheIdleCleanPage` 覆盖。demo smoke 真实渲染未复验。
- AC-004：re_verified。`testExecutionRunsOnlyAfterConfirmationWithBackgroundData` 等断言确认前后无/有进程与 argv（`clean`、`optimize`、`purge --yes`）。
- AC-005：re_verified。执行前调用 `userDidRescanAndWaitForTermination(.clean)`（CleanViewModel.swift:123）、该 API 的“等待终止”语义由 `testUserCleanScanCancelsAndWaitsForBackgroundClean` 覆盖；`verifyUnchanged` 已删，执行在 list 不存在的快照下成功（`testExecutionRunsOnlyAfterConfirmationWithBackgroundData`）。
- AC-006：re_verified。`testUninstallConfirmationOpensDirectlyFromSelection`（开 sheet 零进程）、`testConfirmingBatchUsesOnlySelectedUninstallNamesAndConfirmationInput`、`ZmoleTests.testDemoUninstallExecutesOnlySelectedApplications`；视图预览区块已删（UninstallView.swift diff）。
- AC-007：re_verified。`testUninstallChangedTargetCannotExecuteAndRescansTheList`（拒绝 + 重扫 + `uninstall.error.changed_target`），真实 checker 的 path/bundle id 变化由既存 `UninstallTargetCheckerTests` 覆盖；文案已改为「刷新名单」。
- AC-008：re_verified（VM/presentation 层）。`testReclaimAppearsOnlyWithBackgroundData` 断言 `lastReclaimBytes` 来源与失败置空；`OverviewLayoutTests` 断言 `overview.reclaim_no_scan`；视图绑定源码核对。真实渲染未复验。
- AC-009：re_verified（服务层 + 失败态）。`testReclaimAppearsOnlyWithBackgroundData`（无数据失败置 `scanFailed`）、`testFailingItemKeepsPreviousResultAndRetriesLater`（保留旧结果）；页面保留展示未直接断言（见提示）。
- AC-010：re_verified。diff 对 `InstallersView`/`WhitelistView`/`SettingsView` 及其 ViewModel 无改动（44 文件清单核对）；全量测试通过。
- AC-011：re_verified（除 clean 取消，见 f002）。确认 sheet 路径测试覆盖 optimize/purge/uninstall 取消；clean 确认执行覆盖；Esc 为内联视图无独立关闭路径。

coverage = 11 / 11

verdict: FAIL

## Round 2 (2026-10-17T20:25:00+08:00)

reviewed_scope: 7e7dac6b84097548

## Findings

无。

## 结论

- 前轮 finding 复核：
  - t044_test_f001（important，`cleanBusyProvider` 阻断 clean 刷新）：已消除。`AppDependencies.swift` 生产装配已移除 `preview != nil`，改为委托 `cleanViewModel.ownsCleanListFile`（仅在 `isConfirmationPresented || isExecuting` 时为 true）；页面处于展示结果态时 `ownsCleanListFile == false`，不阻断 `scan.request(.clean)`；`CleanPageTests.testRefreshingStateFollowsTheBackgroundScan` 已对 `ownsCleanListFile` 在展示/确认/取消三种状态下的取值进行了断言，且断言了后台扫描时 `isRefreshing` 的切换。
  - t044_test_f002（minor，clean 页取消确认分支无测试）：已消除。`CleanPageTests` 新增 `testCancelConfirmationKeepsTheScanAndDoesNotExecute`，断言取消后 `isConfirmationPresented == false`、`preview` 保持展示、`canConfirm == true` 且底层进程无任何调用。
  - t044_test_f003（minor，`isRefreshing` 状态切换未触达）：已消除。`CleanPageTests` 新增 `testRefreshingStateFollowsTheBackgroundScan`，通过向 stub 的 `runningItems` 注入 `.clean` 并断言 `viewModel.isRefreshing` 切换为 true，验证了页头取消/扫描中状态驱动。
  - t044_test_f004（minor，`ZmoleTests` 残留死代码 `CleanSpyWaitError`）：已消除。`tests/unit/ZmoleTests.swift` 已彻底移除该未引用枚举。
- 改测方向复核：无「迁就实现」的改测。`BackgroundScanTests.testDemoConfigurationUsesDemoBackgroundScan` 将原本断言 demo 下 scanService 为 nil 的旧用例更新为验证 demo 模式下 scanService 存在并产出数据至 demo 目录，符合 t044 移除预览后 demo 模式依赖后台扫描提供数据的 spec 要求；断言逻辑均为正向有效断言。
- 危险模式扫描：逐项排查无命中——全量测试 292 项及 3 条集成测试脚本均独立通过；无恒真断言、无删除/反转断言、无注释断言、无跳过/独占标志、无静默类型/lint 报错、无 mock 被测逻辑、无条件跳过弱化断言。
- 本轮新发现：0 条。
- 未进表的提示：无。
- 总体判断：前轮 blocker（f001）与 minor 项（f002-f004）均已彻底修复，本轮无新增 finding，测试套件完备可信。verdict PASS。
- 系统性 follow-up：无。

### AC 复验方式

- AC-001：re_verified。`CleanPageTests.testNewBackgroundResultFillsTheIdleCleanPage`、`testRefreshingStateFollowsTheBackgroundScan`、`OptimizeTests.testOptimizeDisplaysBackgroundResultWithoutSpawningCommands`、`PurgeTests.testPurgeDisplaysBackgroundResultWithoutSpawningCommands` 断言后台已有数据时页面立即可见且无前置进程调用。
- AC-002：re_verified。`UiAlignmentTests.testUserFacingCopyDropsPreviewConcept` 遍历全 catalog 校验三语无“预览/preview”；各页动作按钮 key 在源码及 catalog 中双向核对。
- AC-003：re_verified。`CleanPageTests.testRefreshButtonRequestsTheBackgroundScan`、`testRefreshingStateFollowsTheBackgroundScan`、`OptimizeTests.testRefreshButtonRequestsTheBackgroundScan`、`testCancelRefreshYieldsTheBackgroundScan` 验证刷新触发与取消；`ownsCleanListFile` 状态解耦修复了 f001 真实链路阻断问题。
- AC-004：re_verified。`CleanPageTests.testExecutionRunsOnlyAfterConfirmationWithBackgroundData`、`testCancelConfirmationKeepsTheScanAndDoesNotExecute`、`OptimizeTests.testOptimizeDoesNotExecuteBeforeConfirmation`、`PurgeTests.testPurgeDoesNotExecuteBeforeConfirmation` 验证数据存在时可确认、确认后执行原命令、取消不执行。
- AC-005：re_verified。`CleanPageTests.testExecutionRunsOnlyAfterConfirmationWithBackgroundData` 验证 clean 执行前终止后台 clean 扫描，且不再因列表文件状态执行快照比对校验。
- AC-006：re_verified。`UninstallTests.testUninstallConfirmationOpensDirectlyFromSelection`、`UninstallDetailTests.testConfirmingBatchUsesOnlySelectedUninstallNamesAndConfirmationInput`、`ZmoleTests.testDemoUninstallExecutesOnlySelectedApplications` 验证勾选后直接确认并执行，已无预览步骤。
- AC-007：re_verified。`UninstallTests.testUninstallChangedTargetCannotExecuteAndRescansTheList`、`UninstallTargetCheckerTests` 验证路径/bundle id 变化时拒绝执行并重新扫描名单。
- AC-008：re_verified。`CleanPageTests.testReclaimAppearsOnlyWithBackgroundData`、`OverviewLayoutTests` 验证角标与概览可回收量显示后台扫描数据，无数据时为“暂无数据”。
- AC-009：re_verified。`CleanPageTests.testReclaimAppearsOnlyWithBackgroundData`、`BackgroundScanTests.testFailingItemKeepsPreviousResultAndRetriesLater` 验证失败态标记与上次成功数据保留。
- AC-010：re_verified。源码核对 diff 未触及安装包/白名单/设置页；对应用例（`InstallersPageTests`、`WhitelistOperationTests`、`SettingsHistoryTests`）全部通过。
- AC-011：re_verified。`CleanPageTests.testCancelConfirmationKeepsTheScanAndDoesNotExecute`、`OptimizeTests.testCancelConfirmationKeepsTheBackgroundResult`、`PurgeTests.testPurgeUsesYesAndCancelDoesNotExecute`、`UninstallDetailTests.testCancelConfirmationDoesNotExecuteUninstall` 验证破坏性操作取消均不执行。

coverage = 11 / 11

verdict: PASS

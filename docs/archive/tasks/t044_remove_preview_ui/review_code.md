# Task review t044（reviewer_focus: 代码）

- task：`t044_remove_preview_ui`
- spec：`docs/tasks/t044_remove_preview_ui/spec.md`
- diff_anchor：`865a07b94b9ebe2a6a3ad5e7b3949822278e43e8`
- target：`git -C '/Users/karson/kar/code/zmole_t044' diff 865a07b94b9ebe2a6a3ad5e7b3949822278e43e8`
- round：1
- reviewed_at：2026-10-17T19:48:57+08:00

## Findings

### t044_code_f001 - demo/unavailable 装配下清理、优化、项目清理三页无数据源，刷新按钮静默失效

- 严重度：important
- 锚点：违反 AC-003「点击刷新触发对应扫描」；spec 测试策略 demo smoke「走清理、优化、项目清理、卸载四页，确认无需手动预览即可看到数据」（`spec.md:73`）与可测试性声明「AC-003 真实渲染由 demo smoke 截图人工核对」（`spec.md:54`）在当前实现下无法完成
- 位置：`src/zmole/App/AppDependencies.swift:136`、`src/zmole/App/MoleCommandLanes.swift:128`、`src/zmole/Features/Clean/CleanViewModel.swift:64`、`src/zmole/Features/Clean/CleanView.swift:60`
- 问题：本 task 删除了三个页面唯一的取数路径（本地 `clean/optimize/purge --dry-run` 预览），改为只消费 `scan`（`BackgroundScanProviding`）。但 demo 装配 `MoleCommandLanes.demo(...)` 传 `scan: nil`（`MoleCommandLanes.swift:128`），`AppDependencies.swift:136` 在 `lanes.scan == nil` 时 `scan = nil`（既有测试 `tests/unit/BackgroundScanTests.swift:259` 断言 demo 下 `scanService == nil`）。结果是 demo 模式下：`refreshIfNeeded()`/`refreshClean()`/`refreshMaintenance()` 全部 `guard let scan`/`scan?.request` 直接 no-op；`isRefreshing`/`scanFailed` 恒为 false；`preview` 无任何填充路径（`adoptBackgroundResultIfAvailable` 亦需 scan）。可复现路径：`open Zmole.app --args --demo --demo-page clean ...` → 页面永久显示「暂无数据」，页头「刷新」按钮可点击但无任何反应、无扫描中状态、无错误提示；`--demo-page optimize` / `purge` 相同。基线（865a07b）demo 下点「预览」可由 `DemoMoleProcess` 写出 `clean-list.txt` 并展示数据，属本 task 引入的行为回归；unavailable 装配（`lanes.scan == nil`）同样从「预览显示 executableNotFound 错误」退化为「按钮无反馈」。
- 建议：二选一并落定：(a) 为 demo 装配一个 demo-lane 的 `BackgroundScanService`（`DemoMoleProcess` 已支持 `clean/optimize/purge --dry-run`，需同时修订 `docs/specs/prewarm.md:20`「demo 模式不启动后台扫描」的 t043 决策）；(b) 经用户确认修订 t044 spec 的 demo smoke 与可测试性声明、并接受 demo 三页无数据（则需删除 `empty_hint`「后台扫描会自动填充此页；点刷新可立即扫描」这类在 demo 下不成立的文案或补 demo 假件结果）。当前状态下 spec 规定的 AC-003 人工核对通道无法产出证据。

### t044_code_f002 - `confirmExecution` 中 `previewID` 成为死存储（编译警告）

- 严重度：minor
- 锚点：行为缺陷（低危）：无用绑定触发 Swift 警告 `value 'previewID' was defined but never used`（本机 `swiftc -typecheck` 复现同型警告）
- 位置：`src/zmole/Features/Clean/CleanViewModel.swift:120`
- 问题：本 diff 删除了 `previewStore.verifyUnchanged` 失败分支（原先唯一使用 `previewID` 的位置），`guard ... let previewID = PreviewOperationID.from(session.state) else { return }` 的绑定随后再无引用；`session.isConfirmationPresented` 已保证状态为 `.confirming`，该绑定纯冗余。`UninstallViewModel.swift:373` 存在同型既存死存储（非本 task 引入）。
- 建议：把该子句改为布尔条件（或 `_ =`），例如 `PreviewOperationID.from(session.state) != nil`；顺手清理 Uninstall 同型位点。

### t044_code_f003 - 新增本地化 key `clean.refreshing` 零引用

- 严重度：minor
- 锚点：死代码（未使用的本地化 key）
- 位置：`src/zmole/Resources/Localizable.xcstrings:420`；对照 `src/zmole/Features/Clean/CleanView.swift:141`
- 问题：本 task 新增 `clean.refreshing`（三语「正在后台扫描…」），但 CleanView 扫描态用的是既有 `clean.scanning`/`clean.scan_hint`；全仓 grep（含 tests/docs）无任何引用。optimize/purge 页均使用各自 `*.refreshing`（`OptimizeView.swift:58`、`PurgeView.swift:61`），clean 页与其他两页的扫描中文案因此不一致。
- 建议：在 CleanView `scanningState` 改用 `clean.refreshing`，或删除该 key。

### t044_code_f004 - spec 要求的 `docs/specs/overview.md` finalization 更新缺失

- 严重度：minor
- 锚点：文档与 spec 不一致；spec Finalization 清单第 5 项（`spec.md:104`）「`docs/specs/overview.md`：可回收量来源与无数据文案」
- 位置：`docs/specs/overview.md:9`（健康卡与三 tile 描述未提可回收量来源）
- 问题：diff 已更新 clean / optimize_purge / uninstall / app_shell / whitelist / prewarm / architecture 等文档，且 `docs/specs_index.md` 已把 overview 标为含 t044，但 `overview.md` 正文未补充「可回收量来自后台清理结果、无数据显示『暂无清理数据』」的契约（实现侧 `OverviewViewModel.swift:105`、`OverviewView.swift:83` 已改）。若为延后到 finalization 完成，可忽略；当前 diff 内 7/8 已做，仅缺此文件。
- 建议：在 overview.md 行为契约补一行可回收量来源与无数据文案；或明确记录 defer 到 finalization。

### t044_code_f005 - CleanViewModel 与 MaintenanceViewModel 的后台扫描订阅/采用逻辑逐字重复

- 严重度：minor
- 锚点：DRY（verbatim 重复；未观察到行为分叉或修复遗漏）
- 位置：`src/zmole/Features/Clean/CleanViewModel.swift:92` vs `src/zmole/Features/Operations/MaintenanceOperation.swift:132`；另 `refreshIfNeeded`/`refreshMaintenance`/`cancelRefresh`（`CleanViewModel.swift:64-76` vs `MaintenanceOperation.swift:103-117`）与 `adoptBackgroundResultIfAvailable` 主体平行重复
- 问题：`subscribeToBackgroundScan` 两处实现逐字相同（仅 payload 类型与 `lastReclaimBytes` 差异），本 task 新增；三个页面 View 的 scanFailed+重试块也各自复制。当前两处同步一致，无行为分叉。
- 建议：抽一个小的共享订阅/采用 helper（协议扩展或泛型函数）承载 `statePublisher → objectWillChange + adopt` 流程；若认为泛型抽象复杂度高于重复成本，可在 task.md 记录保留重复的理由。

## 结论

- 前轮 finding 复核：Round 1，无前轮。
- 本轮新发现：5 条（1 important + 4 minor）。
- 未进表的提示：
  - 文件过大（按降级规则仅列示）：`src/zmole/App/DemoSupport.swift` 507 行（本 task 净增 6 行）≥ 实现源码 400 阈值；`src/zmole/Features/Uninstall/UninstallView.swift` 453 行、`UninstallViewModel.swift` 483 行超阈值但本 task 均净减行数；测试文件均 < 600。排除项：`Localizable.xcstrings`（生成式资源）、`Zmole.xcodeproj`（生成物）。
  - 复杂度：手算 `CleanViewModel.confirmExecution` ≈13（本 task 净减分支）、`UninstallViewModel.confirmExecution` ≈13（本 task 未改），均 < 15，不进 finding。
  - 死代码提示：`OperationSession` 的 preview 态 API（`beginPreview`/`acceptPreview`/`beginPreviewCancellation`/`.previewing`/`isPreviewing`，`OperationSession.swift:70,105,112,162`）在本 task 后已无生产调用者，仅测试（`CleanPresentationTests`、`OperationSessionTests`）引用；该文件不在本 diff，按结论段提示处理。
  - 范围外观察：无。
- 总体判断：生产路径实现完整且门禁全绿（reviewer 独立重跑 `xcodebuild test -scheme Zmole -destination 'platform=macOS'`，290 tests / 0 failures），AC-001～AC-011 逐条复验通过；但 demo 模式三页无数据源、刷新按钮静默失效，使 AC-003 规定的 demo smoke 人工核对无法产出（f001），属未解决 important。
- 系统性 follow-up：建议「清理 OperationSession 预览态 API 与旧语义测试」，slug `cleanup_operation_session_preview_api`；若 f001 选择不在本 task 修复，建议另立「demo 模式后台扫描数据源」slug `demo_background_scan_data`（现有 backlog 无等价项）。

### AC 复验方式

- AC-001：`re_verified` — 读三页 `.task`（`CleanView.swift:30-34`、`OptimizeView.swift:27-30`、`PurgeView.swift:25-28`）adopt+refreshIfNeeded 逻辑，重跑全套测试含 `testNewBackgroundResultFillsTheIdleCleanPage`；demo 环境差异见 f001。
- AC-002：`re_verified` — 脚本遍历 `Localizable.xcstrings` 全部 value 无「预览/預覽/preview」，页头 key 为 `clean.refresh`/`optimize.refresh`/`purge.refresh`；`testUserFacingCopyDropsPreviewConcept` 重跑通过。
- AC-003：`re_verified` — 重跑 `testRefreshButtonRequestsTheBackgroundScan`、`testNewBackgroundResultReplacesIdlePreview`、`testRefreshWhileRunningReusesTheInFlightScan` 通过；「真实渲染 demo smoke 截图」部分未产出且当前 demo 下不可满足（f001）。
- AC-004：`re_verified` — 重跑 `CleanPageTests.testExecutionRunsOnlyAfterConfirmationWithBackgroundData`、`PurgeTests.testPurgeUsesYesAndCancelDoesNotExecute` 通过；三 VM 执行均经 `isConfirmationPresented` 门禁。
- AC-005：`re_verified` — grep 全仓零 `verifyUnchanged`/`changedSincePreview`；`CleanViewModel.swift:123` 执行前 `userDidRescanAndWaitForTermination(.clean)`；`testUserCleanScanCancelsAndWaitsForBackgroundClean` 重跑通过。
- AC-006：`re_verified` — `UninstallViewModel.requestConfirmation` 无 process 调用（测试断言 invocations 为空）；`UninstallView` 已无预览结果面板；`testUninstallConfirmationOpensDirectlyFromSelection` 通过。
- AC-007：`re_verified` — `UninstallMetadata.swift:38-46` 身份核对 + confirm 循环；`testUninstallChangedTargetCannotExecuteAndRescansTheList` 重跑通过。
- AC-008：`re_verified` — `SidebarView.swift:87`、`OverviewView.swift:83,107`、`OverviewViewModel.swift:105`；`OverviewLayoutTests` 新断言重跑通过。
- AC-009：`re_verified` — 三页 scanFailed 通知与重试按钮；`BackgroundScanService.swift:302-308` 失败保留旧结果；`testFailingItemKeepsPreviousResultAndRetriesLater` 重跑通过。
- AC-010：`re_verified` — diff 未触及安装包/白名单/设置的生产行为，相关测试全绿。
- AC-011：`re_verified` — 三 VM `confirmExecution` 均 guard `isConfirmationPresented`；取消路径测试断言零执行；确认视图为内联页（无 Esc 处理器，Esc 不执行）。
- coverage = 11/11

reviewed_scope: e979df63447ef5a6

verdict: FAIL

## Round 2 (2026-10-17T20:21:48+08:00)

### 前轮 finding 复核

- t044_code_f001（important）：已消除。`MoleCommandLanes.demo` 已装配 `BackgroundScanLanes`，`AppDependencies` 配置了 demo 临时目录下的 `BackgroundScanCache`；三页在 demo 模式下由 demo 进程产出数据并在 ViewModel 自动呈现或点击刷新时触发；`docs/specs/prewarm.md:20` 同步更新了契约；`tests/unit/BackgroundScanTests.swift:259` 新增 `testDemoConfigurationUsesDemoBackgroundScan` 并验证 demo clean/optimize 数据能够产出且缓存写入 demoDirectory。
- t044_code_f002（minor）：已消除。`CleanViewModel.swift:120` 和 `UninstallViewModel.swift:371` 中未使用的 `previewID` 死存储已移除，编译无任何 warning。
- t044_code_f003（minor）：已消除。`CleanView.swift:141` 已改用 `clean.refreshing`，且未使用的 `clean.scanning` key 已从 `Localizable.xcstrings` 彻底移除。
- t044_code_f004（minor）：已消除。`docs/specs/overview.md:10` 已补全健康卡可回收量来自后台清理扫描结果与无数据时显示「暂无清理数据」的契约，来源 task 加入 t044。
- t044_code_f005（minor）：已消除。`BackgroundScanProviding` 抽出了通用的 `observeStateChanges` helper（`BackgroundScanService.swift:69-73`），`CleanViewModel` 和 `MaintenanceViewModel` 均改用此 helper，消除了两处 ViewModel 的订阅样板重复。

### 本轮新发现：0 条

全视角扫描（安全/正确性/契约·Breaking/性能·资源/架构·可维护性/健壮性·可观测/测试·文档·规格）均未发现新问题。

### 未进表的提示

- 文件过大：`src/zmole/App/DemoSupport.swift` 507 行（本 task 净增 6 行）≥ 400 行实现源码提示线；`tests/unit/BackgroundScanTests.swift` 806 行（本 task 净增 17 行）≥ 600 行测试源码提示线。`UninstallView.swift` (453)、`UninstallViewModel.swift` (482) 行数超阈值但本 task 均为净减。排除项：`Localizable.xcstrings`（资源文件）、`Zmole.xcodeproj/project.pbxproj`（生成物）。按降级规则不进 finding 表。
- 圈复杂度：`CleanViewModel.confirmExecution` (≈10)、`MaintenanceViewModel.confirmMaintenance` (≈10) 均 < 15，本 task 简化了分支逻辑，不进 finding 表。
- 范围外观察：无。

### 结论

- 前轮 blocker 复核：前轮唯一 blocker f001 已消除；4 条 minor (f002~f005) 亦均已消除。
- 本轮新发现：0 条。
- 总体判断：所有前轮 finding 已彻底闭环，未引入新缺陷；独立复验全部门禁（292 Swift tests / pytest contract / 3 条集成测试脚本）均通过，AC-001～AC-011 逐项核验通过。
- 系统性 follow-up：建议「清理 OperationSession 预览态 API 与旧语义测试」，slug `cleanup_operation_session_preview_api`（同 Round 1 提示，非阻塞）。

### AC 复验方式

- AC-001：`re_verified` — 读三页 `.task`（`CleanView.swift:30-34`、`OptimizeView.swift:27-30`、`PurgeView.swift:25-28`）adopt+refreshIfNeeded 逻辑，重跑全套测试含 `testNewBackgroundResultFillsTheIdleCleanPage`、`testDemoConfigurationUsesDemoBackgroundScan` 通过。
- AC-002：`re_verified` — 脚本遍历 `Localizable.xcstrings` 全部 value 无「预览/預覽/preview」，页头 key 为 `clean.refresh`/`optimize.refresh`/`purge.refresh`；`testUserFacingCopyDropsPreviewConcept` 重跑通过。
- AC-003：`re_verified` — 重跑 `testRefreshButtonRequestsTheBackgroundScan`、`testNewBackgroundResultReplacesIdlePreview`、`testRefreshWhileRunningReusesTheInFlightScan` 及 demo 后台扫描用例通过。
- AC-004：`re_verified` — 重跑 `CleanPageTests.testExecutionRunsOnlyAfterConfirmationWithBackgroundData`、`PurgeTests.testPurgeUsesYesAndCancelDoesNotExecute` 通过；三 VM 执行均经 `isConfirmationPresented` 门禁。
- AC-005：`re_verified` — grep 全仓零 `verifyUnchanged`/`changedSincePreview`；`CleanViewModel.swift:123` 执行前 `userDidRescanAndWaitForTermination(.clean)`；`testUserCleanScanCancelsAndWaitsForBackgroundClean` 重跑通过。
- AC-006：`re_verified` — `UninstallViewModel.requestConfirmation` 无 process 调用（测试断言 invocations 为空）；`UninstallView` 已无预览结果面板；`testUninstallConfirmationOpensDirectlyFromSelection` 通过。
- AC-007：`re_verified` — `UninstallMetadata.swift:38-46` 身份核对 + confirm 循环；`testUninstallChangedTargetCannotExecuteAndRescansTheList` 重跑通过。
- AC-008：`re_verified` — `SidebarView.swift:87`、`OverviewView.swift:83,107`、`OverviewViewModel.swift:105`；`OverviewLayoutTests` 新断言重跑通过。
- AC-009：`re_verified` — 三页 scanFailed 通知与重试按钮；`BackgroundScanService.swift:302-308` 失败保留旧结果；`testFailingItemKeepsPreviousResultAndRetriesLater` 重跑通过。
- AC-010：`re_verified` — diff 未触及安装包/白名单/设置的生产行为，相关测试全绿。
- AC-011：`re_verified` — 三 VM `confirmExecution` 均 guard `isConfirmationPresented`；取消路径测试断言零执行；确认视图为内联页（无 Esc 处理器，Esc 不执行）。
- coverage = 11/11

reviewed_scope: 7e7dac6b84097548

verdict: PASS

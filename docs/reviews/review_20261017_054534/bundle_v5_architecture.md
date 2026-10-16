# 视角5 — 架构·可维护性

## 范围与摘要

- 审查范围：`docs/reviews/review_20261017_054534/_meta/scope_files.txt` 所列 152 文件（HEAD `94170aa`，按当前磁盘状态，含未提交改动）；本报告仅覆盖架构与可维护性视角。
- 结论概览：分层边界总体清晰（Features 不依赖 App；`Process` 只出现在 `MoleBridge`；无循环 import）；主要问题是 **共享抽象存在但未收敛**（页头/统计块/输出摘要/ANSI 剥离/租约-预览世代样板各自复制）、**测试专用 API 与死代码散落在生产源码**（rg src+tests 交叉验证）、**装配边界被 View 局部绕过**、以及 **文档与实现漂移**。
- `docs/blueprint/architecture.md` 非模板占位符（99 行，项目特定内容已填充）；`conventions.md`、`testing.md` 亦已按本项目改写。但 architecture.md/conventions.md 中 `src/zmole/Models/` 的模块声明与现状不符（该目录只剩 `.gitkeep`）。
- 计数：C 0 / H 0 / M 12 / L 19 / Info 6，共 37 条。

## Findings

- [M][80] src/zmole/App/AppDependencies.swift:40 — 装配文件混装约 500 行 Demo 假件 — 证据：DemoMoleProcess(:40)、DemoMoleStreaming(:237)、DemoUninstallListStream(:279)、DemoDiskScanner(:388)、DemoConfiguration(:345) 与真正的装配 `AppDependencies.init`(:543-727) 同文件，文件 727 行且假件随生产装配改动而被动变更 — 修复：Demo 假件与 fixtures 拆到独立文件（如 `App/DemoSupport.swift`），AppDependencies 只留装配。
- [M][85] src/zmole/App/AppDependencies.swift:198 — Demo 单发与流两条通道各复制一份 statusFixture — 证据：`:198` 与 `:269` 是两个逐字相同的 `statusFixture(stale:includeDetails:)`，分别被 `DemoMoleProcess.run`(:81) 与 `DemoMoleStreaming.stream`(:259) 调用 — 修复：抽到共享 fixture 函数/类型。
- [M][85] src/zmole/Features/Clean/CleanViewModel.swift:321 — CLI stdout/stderr 摘要拼接四处重复 — 证据：CleanViewModel.outputSummary(:321-326)、UninstallViewModel.outputSummary(:519-524)、UninstallBatchResultParser 内联拼接(UninstallSnapshot.swift:214-217) 与已有的 `MaintenanceOutput.summary`(MaintenanceOutput.swift:4) 逻辑一致（后者还带 stripANSI） — 修复：统一调用 `MaintenanceOutput.summary`，删除三份私有实现。
- [M][85] src/zmole/Features/Clean/CleanScanStage.swift:59 — ANSI 剥离两套独立实现 — 证据：`CleanScanStage.stripANSI`(:59-84) 与 `MaintenanceOutput.stripANSI`(MaintenanceOutput.swift:12-30) 同一状态机重复实现 — 修复：合并为一处并复用。
- [M][80] src/zmole/Features/Clean/CleanView.swift:94 — statTile 在多个 Feature 手写，共享 `MoleStatTile` 几乎闲置 — 证据：CleanView.statTile(:94-108)、InstallersView.statTile(InstallersView.swift:91-102) 与 `MoleStatTile`(UtilityUI.swift:74) 的字体/内边距/圆角/描边几乎一致；`MoleStatTile` 仅被 StatusView(:115-118) 使用 — 修复：统一使用 `MoleStatTile`，删两份私有实现。
- [M][75] src/zmole/Features/Clean/CleanView.swift:49 — 四个页面手写页头，未使用共享 `MolePageHead` — 证据：CleanView.head(:49-83)、InstallersView.head(:57-80)、OptimizeView 标题块(:50-62)、PurgeView 标题块(:50-62) 各自重复 eyebrow/title/subtitle 字号与颜色；`MolePageHead`(UtilityUI.swift:25) 已被 Overview/Analyze/History/Settings/Uninstall/Status 六页使用 — 修复：四页改用 `MolePageHead`（subtitle 已支持可选）。
- [M][75] src/zmole/Features/Uninstall/UninstallSnapshot.swift:260 — 人类可读大小解析两套实现 — 证据：`UninstallSizeParser.bytes`(:260-310，含 KiB/MiB 与 "N/A (steam-managed)" 变体) 与 `CleanPreviewParser.parseHumanSize`(CleanPreviewModel.swift:96-114，只到 TB) 同类逻辑各自维护 — 修复：收敛为一个共享 size parser（放共享模型层）。
- [M][75] src/zmole/Features/Operations/OperationSession.swift:36 — 租约+预览世代样板在三个 ViewModel 重复 — 证据：`isCurrentPreview`/`releaseLease(clearPreviewGeneration:)`/`operationID(for:)` 三份几乎逐字相同（CleanViewModel.swift:301-319、UninstallViewModel.swift:480-506、MaintenanceOperation.swift:242-258），且每个 VM 各自管理 `previewCoordinatorGeneration` 订阅过期逻辑(clean:35-43、uninstall:51-53、maintenance:60-67) — 修复：把 coordinator 接管、世代失效、确认前校验收进共享 `PreviewLeaseCoordinator`/基类。
- [M][75] src/zmole/App/MoleCommandLanes.swift:51 — bridges 位置索引映射 8 条 lane，属易碎耦合 — 证据：`commandLaneCount = 8`(:51) + `makeCommandBridges` 返回数组，AppDependencies.swift:574-587 用 `bridges[0..7]` 按位置赋名；增删 lane 不会产生编译错误，只会静默错配 — 修复：`makeCommandBridges` 返回具名结构体，或直接在 `MoleCommandLanes` 内创建桥。
- [M][75] src/zmole/Features/Settings/AboutView.swift:33 — 生产 View 内自建 MoleBridge，绕过 AppDependencies 装配 — 证据：`loadMoleVersion` 里 `try? MoleBridge()`(:32-35)；生产路径 `SettingsView.swift:100` 与 `SidebarView.swift:39-41` 都直接构造 `AboutView()`，无注入点；architecture.md:24 要求“页面只接收已装配依赖，不在 View 内创建生产 Bridge” — 修复：版本读 `BundledMoleInfo.tag()` 即可（无需桥），或由 AppDependencies 注入 loader。
- [M][65] src/zmole/Features/Overview/OverviewView.swift:32 — 视图层忙轮询等待 status 采样 — 证据：`.task` 内 `for _ in 0..<120 where usedBytes == nil { try? await Task.sleep(100ms) }`(:32-34)，最多空转 12 秒且无早退条件，数据就绪本应由订阅/观察驱动 — 修复：改为订阅 `statusViewModel.$snapshot`（或 async 等待单次变化）后再计算估算。
- [M][70] src/zmole/App/NavigationModel.swift:16 — 契约以恒真常量向测试自证 — 证据：`isExecutionAction` 恒 false(:16)、`forbiddenIdentifiers`(:21-23)、`ShellChrome.drawsCustomTrafficLights`(AppDestination.swift:92) 在 src 中零运行时读取，仅被 NavigationTests.swift:52/:54/:88 断言；对常量本身的断言无法捕获真实行为回归 — 修复：删除常量，测试改为对真实 palette/视图数据断言，或把契约做成结构性约束（如 action 枚举确实不存在执行选项）。
- [L][75] src/zmole/Features/Optimize/OptimizeView.swift:170 — busyState(title:) 两页逐字重复 — 证据：`OptimizeView.busyState`(:170-176) 与 `PurgeView.busyState`(PurgeView.swift:103-109) 实现相同（ProgressView + 文案 + minHeight 200） — 修复：抽共享 busy 视图或收进 UtilityUI。
- [L][80] src/zmole/Features/Confirmation/DestructiveConfirmation.swift:3 — DestructiveConfirmationFlow 仅测试引用 — 证据：src 内无调用方，唯一引用 tests/unit/ZmoleTests.swift:130；生产确认流程走 `OperationSession` + `DestructiveConfirmationView` — 修复：删除类，测试改为覆盖真实确认路径（或在 OperationSession 上断言）。
- [L][90] src/zmole/Features/Optimize/OptimizeSnapshot.swift:5 — 优化/项目清理错误枚举与 typealias 全无引用 — 证据：`OptimizeViewModelError`(:5)、`OptimizePreviewSnapshot`(:3)、`PurgeViewModelError`(PurgeSnapshot.swift:5)、`PurgePreviewSnapshot`(:3) 在 src+tests 除定义行外零出现 — 修复：删除死类型。
- [L][85] src/zmole/Features/Uninstall/UninstallViewModel.swift:229 — selectAll(\_:) 死方法 — 证据：`func selectAll(_ ids: Set<String>)`(:229-236) 在 src+tests 无任何调用（InstallersViewModel.selectAll 是同类另一个方法，非本项） — 修复：删除。
- [L][75] src/zmole/Features/Uninstall/UninstallViewModel.swift:253 — focus(\_ app:) 仅测试调用 — 证据：视图统一用 `focus(path:)`(UninstallView.swift:223)；`focus(_ app:)`(:253-255) 唯一调用在 tests/unit/UninstallDetailTests.swift:28 — 修复：删除并用 path 版本重写该测试。
- [L][75] src/zmole/Features/Whitelist/WhitelistViewModel.swift:31 — moleProcess 依赖只写不读 — 证据：`:31` 声明、`:41` 赋值后无任何读取；tests/unit/ZmoleTests.swift:407-425 注入 spy 只为断言 0 次调用 — 修复：删除依赖；测试改为断言 store/coordinator 未被外部调用。
- [L][70] src/zmole/Features/Status/StatusViewModel.swift:76 — StatusViewModel.refresh() 仅测试路径 — 证据：生产视图只用 start/pause/retry/resample（StatusView.swift:38-46、OverviewView.swift:51）；`refresh`(:76-104) 调用者全在 tests/unit/ZmoleTests.swift:166/:169/:184 等 — 修复：删除该路径，或接入一个真实入口（例如“诊断”按钮）。
- [L][75] src/zmole/Features/Overview/OverviewViewModel.swift:399 — refresh(usedBytes:)/loadEstimate/isLoading 是测试专用 API — 证据：注释自承 “Convenience used by tests”(:397-398)；`loadEstimate`(:362) 只被 `refresh` 调用；`isLoading`(:273) 除 refresh(:400-401) 写入外无任何读取方（视图与测试均无） — 修复：删除或与 `primeEstimate`/`refreshEstimateIfNeeded` 合并。
- [L][85] src/zmole/App/MoleTheme.swift:27 — 未使用常量 radiusXL、titlebarHeight、UtilityStyle.secondarySurface — 证据：rg 全仓（src+tests）唯一出现于定义行：MoleTheme.swift:27、:33，UtilityUI.swift:13 — 修复：删除。
- [L][80] src/zmole/App/NavigationModel.swift:82 — displayName(for:) 无引用 — 证据：`displayNames`(k) 用于过滤与测试(NavigationTests:120)，单数版本(:82-84) 无调用 — 修复：删除。
- [L][80] src/zmole/Features/Operations/OperationSession.swift:31 — OperationResult.isCancelled/isPartial/isFailure 无引用 — 证据：三属性(:31-33)在 src+tests 无调用，所有比较直接对 `status` 枚举 — 修复：删除参数化属性。
- [L][70] src/zmole/Features/Status/StatusSnapshot.swift:346 — NetworkTotal.isVirtualOnly 与 processCollectedAt 只写不读 — 证据：`isVirtualOnly` 仅在 `networkTotal` 构造处赋值(:319/:330)，无读取方；`processCollectedAt`(:19) 只解码(:290)与回编码(:306)，无 UI/逻辑消费 — 修复：删除，或将 isVirtualOnly 接入“仅虚拟网卡”提示。
- [L][75] src/zmole/MoleBridge/MoleBridgeError.swift:17 — 错误详情硬编码简体中文，三语界面下泄漏为 detail 文案 — 证据：`MoleBridgeError.errorDescription`(:14-39) 及同类 `StatusSnapshotError`(StatusSnapshot.swift:372)、`HistorySnapshotError`(:194)、`CleanPreviewStoreError`(CleanPreview.swift:22)、`DiskScanError`(DiskScanner.swift:88)、`PurgePathsError`(PurgePaths.swift:15)、`WhitelistStoreError`(:6)、`InstallerInterfaceError`(:98)、`StatusWatchError`(:41)；这些字符串经 `error.localizedDescription` 直接进入页面 detail（如 CleanView.swift:271、UninstallView.swift:431） — 修复：错误只携带 errorKey，文案入 String Catalog。
- [L][80] docs/blueprint/architecture.md:14 — 文档声明 `Models` 模块承载共享值类型，实际为空目录 — 证据：`src/zmole/Models/` 仅 `.gitkeep`，模型全部落在 Features/\* 与 MoleBridge；conventions.md:15 同样声明 `src/zmole/Models/` — 修复：更新文档为“按 Feature 就近存放”，或删除空目录与声明。
- [L][90] docs/design/ui_contract.md:27 — 页面契约表“清理”行重复两次 — 证据：`:27` 与 `:29` 两行同为“清理”，第二行仅追加“打开页面直接显示后台预跑预览与扫描时间” — 修复：合并为一行。
- [L][85] docs/handoff.md:9 — handoff 停留在 2026-09-21，head_commit 落后 30+ 提交 — 证据：handoff 记录 head_commit `903b633`（“docs: lock v1 scope”），当前 HEAD `94170aa`，其间已合入 t027-t036（卸载名单流、磁盘扫描、预跑、UI 对齐等），handoff 未反映 — 修复：更新最新一节（branch + 当前 head_commit + 当前焦点），或跑 repo-hygiene。
- [L][65] docs/blueprint/domain.md:17 — 领域表称 status 为“非 live watch”，与实现矛盾 — 证据：domain.md:17 “只读健康快照（非 live watch）”，而 StatusWatchService 以 `mole status --watch --interval 1s` 流为源（architecture.md:75、StatusWatchService.swift:146） — 修复：更新术语表。
- [L][70] src/zmole/Features/UtilityUI.swift:6 — accent 色板双份定义、依赖手工同步 — 证据：`UtilityStyle.accent`(:6-11) 与 `MoleTheme.accent`/`accentStrong`(MoleTheme.swift:16-18) 数值相同；UtilityUI 注释“see MoleTheme”承认对应关系，当前未提交改动正同时在两处改色值 — 修复：`UtilityStyle.accent` 直接等于 `MoleTheme.accent`（或删除 UtilityStyle 的独立色）。
- [L][60] src/zmole/Features/Status/StatusChart.swift:77 — 内存文本格式化两套 — 证据：`StatusStatValues.make`(:77-99) 与 `OverviewMetrics.memoryText`(OverviewViewModel.swift:17-25) 同为 “used/total → x / y，否则 percent，否则 unknown” 逻辑，各自带私有 bytes 帮助函数(StatusChart.swift:101、OverviewViewModel.swift:40) — 修复：抽共享 formatter。
- [Info][55] src/zmole/Features/Operations/PrewarmService.swift:175 — 三个 catch 分支体相同 — 证据：`catch is CancellationError`(:175)、`catch MoleBridgeError.cancelled`(:177)、通用 `catch`(:179) 全部只调 `noteFailure(item)` — 修复：合并为一个 catch。
- [Info][50] src/zmole/Features/Status/StatusWatchService.swift:135 — StatusWatchProviding.retry() 无生产调用 — 证据：StatusViewModel.retry() 走自身 `start()`(StatusViewModel.swift:159-163)，从不调 service.retry；service 实现仅被 tests/unit/StatusStreamTests.swift:94 调用 — 修复：删除协议方法，或让 VM 委托 service。
- [Info][50] src/zmole/Features/Operations/PrewarmService.swift:42 — PrewarmService 直接耦合四个 Feature 类型 — 证据：依赖 UninstallListStream、InstallerInterface、CleanPreviewStore(:42-46)，使其实际承担跨页预跑协调者角色，却位于 Features/Operations — 修复：可接受；若要收敛，各 Feature 用协议提供预跑载荷。
- [Info][50] src/zmole/MoleBridge/MoleBridge.swift:160 — MoleProcessRunner 单类锁状态机约 15 个布尔 — 证据：cancelRequested/timeoutRequested/processStarted/processGroupConfigured/processTerminated/stdoutEOF/stderrEOF/outputAborted/finished 等(:177-192)共享一把 NSLock，读改点分散在十余处（consume(:393)/outputDidReachEOF(:453)/finishIfReady(:503) 等） — 修复：不改行为前提下抽 stdout/stderr 读取器或状态枚举，缩小锁面。
- [Info][55] src/zmole/Features/Uninstall/UninstallViewModel.swift:67 — selectedIDs 与 selectedPaths 同值双名并存 — 证据：`var selectedIDs: Set<String> { selectedPaths }`(:67) 注释“Kept for call sites…”，视图与测试两名混用（UninstallView.swift:78 用 selectedIDs、:215/:217 用 selectedPaths） — 修复：保留一个公开名。
- [Info][40] src/zmole/Features/Analyze/AnalyzeView.swift:4 — DiskSplitLayout 留在视图文件，与同模块几何类型落点不一致 — 证据：布局计算 `DiskSplitLayout`(:4-20) 定义在 AnalyzeView 顶部，同类纯几何 `SpaceMapLayout` 有独立文件(SpaceMapLayout.swift) — 修复：几何类型统一放独立文件。

## 无发现声明

以下检查通过，未见问题：

- 模块边界：Features/\* 不 import App 层或 `MoleCommandLanes`/`AppDependencies`（rg 交叉验证）；无循环依赖；`Process()` 全仓仅出现于 MoleBridge.swift:202，符合“唯一 spawn 层”约束。
- 禁用行为：未发现 PTY、方向键代发、TUI 帧解析；stdin 写入仅 uninstall 的 `y\n`（UninstallViewModel.swift:526）；`stripANSI` 仅用于行级输出清理（另见发现 4 的重复问题）。
- 大文件/长函数项以外的深嵌套未发现超过阈值者（阈值见规模统计）。
- 本视角未发现 C（安全/数据丢失/崩溃）或 H（确定 bug/性能陷阱）级问题。

## 规模统计

超过 600 行的文件：

|文件|行数|备注|
|---|---|---|
|tests/unit/ZmoleTests.swift|851|单测堆积，可拆分|
|src/zmole/App/AppDependencies.swift|727|其中约 500 行为 Demo 假件（见 Finding 1）|

500–600 行（提示但未列 finding）：

- src/zmole/MoleBridge/MoleBridge.swift 567（见 Info 条目）
- src/zmole/Features/Uninstall/UninstallViewModel.swift 527
- tests/unit/DiskExplorerTests.swift 571、tests/unit/PrewarmTests.swift 523（测试文件）

超过 80 行的函数：

- `AppDependencies.init(configuration:)` src/zmole/App/AppDependencies.swift:543-727（约 185 行，装配 + 预跑订阅接线，建议拆分为 Demo 装配/生产装配/预跑接线三段）

接近阈值（60–80 行，暂不要求拆分）：`CleanViewModel.previewClean`(85-154) 与 `confirmExecution`(213-288)、`UninstallViewModel.confirmExecution`(394-467)、`MaintenanceOperation.previewMaintenance`(99-162) 与 `confirmMaintenance`(182-232)。

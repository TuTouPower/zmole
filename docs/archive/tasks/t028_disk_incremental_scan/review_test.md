# Task review t028（reviewer_focus: 测试）

- task：`t028_disk_incremental_scan`
- spec：`docs/tasks/t028_disk_incremental_scan/spec.md`
- diff_anchor：`3d42958b84fbfc08d96a24d20b3a8613ee31f3a6`
- target：`git -C '/Users/karson/kar/code/zmole_t028' diff 3d42958b84fbfc08d96a24d20b3a8613ee31f3a6`
- round：1
- reviewed_at：2026-10-17T01:36:00+08:00

## Findings

### t028_test_f001 - 重写磁盘页测试时删除的 reveal / breadcrumb 跳转 / 名称排序 / 失败提示四项覆盖未补回（危险模式：删测试）

- 严重度：important
- 锚点：「行为缺陷」——四项仍在使用中的生产行为的回归将无任何测试可检出；按本评审提示词「危险模式扫描：降低行为覆盖……最低 important，禁止标 minor」定级。另涉 AGENTS「实现变更让旧测试语义失效时：旧测试原样保留或整体删除并写明理由」，以及契约区范围「文件可在 Finder 中显示」。
- 位置：
    - 删除（anchor 版本 `tests/unit/DiskExplorerTests.swift`）：`testBreadcrumbJumpAnalyzesAncestorPath`（L25）、`testNameSortReordersRowsWithoutChangingBytes`（L74）、`testRevealUsesEntryPath`（L88）及 helper `DiskRevealerSpy`；
    - 删除（anchor 版本 `tests/unit/ZmoleTests.swift`）：`testAnalyzeViewModelShowsFailureWithoutDeleteAction`（L747）；
    - 对应生产行为仍在：`src/zmole/Features/Analyze/AnalyzeView.swift:167`（面包屑 `viewModel.open(path:)`）、`AnalyzeView.swift:46-49`（排序 Picker 含 `.name`）、`AnalyzeView.swift:379` + `src/zmole/Features/Analyze/AnalyzeViewModel.swift:96-98`（`revealInFinder` 路径转发）、`AnalyzeViewModel.swift:135-137` + `AnalyzeView.swift:79-87`（列表失败设 `errorMessage` 并展示）。
- 问题：以下四项覆盖在本次重写后完全消失，且不属于 spec 要求的删除、也没有等价或更高层替代：
    1. `revealInFinder` 路径转发：全仓现在只剩 Uninstall 的 `testRevealInFinderUsesTheAppPath`，`AnalyzeViewModel` 的 `revealer` 注入点零覆盖（`rg "reveal" tests/unit` 无磁盘页用例）；
    2. `open(path:)` 面包屑回跳：现测试中 `rg "open\(path" tests` 零命中，只有 `goBack()` 被覆盖；
    3. 名称排序：现测试只有 `DiskExplorerTests.swift:233` 的 `by: .size`，`AnalyzeSort.name` 分支零覆盖；
    4. 列表失败错误提示：新测试（`DiskExplorerTests.swift`、`DiskScannerTests.swift`）中 `rg "errorMessage"` 零命中，注入抛错 scanner 的路径无人验证。
        `ZmoleTests.swift:669` 注释称旧测试“moved to DiskExplorerTests ... the same navigation states”，但失败提示用例并无对应搬迁；`DiskExplorerTests.swift` 对 reveal/名称排序的删除无任何说明。回归场景：把 reveal 的路径参数改错、改坏名称比较器、改坏 `open(path:)` 的栈裁剪、或让 `list` 的 catch 不再设 `errorMessage`——以上均不会使任何测试变红。
- 建议：补回四条覆盖（均可基于 `FakeDiskScanner` 低成本实现：reveal 用 spy 断言传入路径；`open(path:)` 断言回跳到缓存层且 `listRequests` 不增；`AnalyzeListOrder.sorted(by: .name)` 单测；注入抛错 scanner 断言 `errorMessage` 与 `level == nil`）。若确定不保留，须按规则在测试文件内写明删除归因，不得用概称注释代替。

### t028_test_f002 - AC-012 以源码字符串扫描代替「mole 命令记录不含 analyze」，装配点未覆盖

- 严重度：minor
- 锚点：AC-012；spec 上下文区测试策略「断言磁盘页路径上的 mole 命令记录不含 analyze」。
- 位置：`tests/unit/DiskExplorerTests.swift:273-283`（`testDiskSourcesDoNotRunMoleCommands`）；未扫到的装配点 `src/zmole/App/AppDependencies.swift:538-543`。
- 问题：该测试只 grep `AnalyzeView.swift`、`AnalyzeViewModel.swift`、`DiskScanner.swift` 三个文件是否含 `MoleBridge`/`MoleProcess`/`"analyze"`/`Process(`，既不执行磁盘页路径，也不核对命令记录；生产与 demo 的唯一装配处 `AppDependencies.swift:538-543` 不在扫描范围。若将来把 scanner 换成任何会调 mole 的实现（例如改回 `AnalyzeSnapshotLoader` 驱动磁盘页），只要不改这三个文件，测试仍全绿。反向字符串断言也无法区分注释/死代码。当前 AC-012 的成立主要靠 `DiskScanning` 协议的结构约束，测试是弱代理而非策略要求的运行时核对。
- 建议：最小补齐——把装配点纳入断言（如断言 `AppDependencies.swift` 磁盘 VM 构造只出现 `LiveDiskScanner()`/`DemoDiskScanner`）；或明确在 `task.md` 记录接受该残余风险。更完整做法：用可记录 spy 进程装配依赖，驱动开页/下钻/返回/重分析后断言无 analyze 调用。

## 结论

- 改测方向复核：无「让断言迁就当前实现」的改测。逐处：`CommandConcurrencyTests.swift` 删 analyze 通道并换 estimate（spec AC-012 要求磁盘页不走 mole，断言语义未削弱）；`SpaceMapTests.swift` `size`→`knownSize ?? 0` 为类型迁移；`ZmoleTests.swift:48-49` `snapshot?.path`→`currentPath` 等价；`RecoverableBusyTests.swift` 删两条磁盘页 busy 用例（该页不再 spawn mole，理由成立，busy 语义由本文件其余三条覆盖，属合法删除）；`DiskExplorerTests.swift` 整体重写为注入目录源的新语义，导航/缓存/合计断言比旧命令记录式更贴 AC。f001 属删除未归因/未补回，不是就地改预期。
- 本轮新发现：2 条（1 important + 1 minor）。
- 未进表的提示：
    - AC-015/016/017 的绑定断言全部为源码字符串存在性检查（`DiskExplorerTests.swift:292-312`，注释掉代码也能过）；spec 可测试性声明已授权视图层替代真实手势，故不计 finding，未来引入视图检视工具可升级。
    - 跨层硬链接去重（父层直接列出、子目录内再现同一 inode）无覆盖；同级与子树内去重已测（`DiskExplorerTests.swift:212-224`、`DiskScannerTests.swift:36-53`），可选补 case。
    - AC-005 的“子树整体替换”只对当前层断言（`DiskExplorerTests.swift:70-94`、`DiskScannerTests.swift:105-155`），重分析后重进孙目录取新值未单独断言；可选覆盖扩展。
    - 名单枚举顺序、demo `partial` 长阻塞状态无自动断言（非 AC；demo smoke 由实施侧截图覆盖）。
- 总体判断：19 条 AC 全部有触达生产逻辑的测试、208 例全绿、无假测试/弱化断言/skip/mock 被测逻辑；但存在 1 条未解决的 important（f001，危险模式删测试未补回），本报告不 PASS。
- 系统性 follow-up：无（f001/f002 均可在本 task 内闭环）。

### AC 复验方式

复验命令：`xcodebuild test -scheme Zmole -destination 'platform=macOS'`（derivedData 落预批临时目录，工作区无改动）→ 208 tests、0 failures（含新增 DiskExplorerTests 19 例、DiskScannerTests 5 例）。

- AC-001：re_verified — `testListingAppearsBeforeDirectorySizesFinish` 断言 Gamma 测量完成、Beta 仍阻塞时名单与 `alpha.txt=100` 已出现；套件重跑通过。
- AC-002：re_verified — `testComputingDirectoriesDrawNoAreaAndStayOutOfTheTotal` 断言合计 50 且 tiles 只含 `ready.bin`。
- AC-003：re_verified — 同上两条的合计断言 + `testShareAndBarFractionHandleBoundaries`。
- AC-004：re_verified — `testCompletedLevelIsServedFromTheSessionCacheWithoutRelisting`（`listRequests` 证明不再列举）+ `DiskScannerTests.testSessionCacheKeepsScanResultsUntilReanalyze`（真实临时目录改文件后缓存不变）。
- AC-005：re_verified — `testReanalyzeReplacesTheCachedSubtree`（900 替换 500）+ `testSessionCache…`（refresh 后 totalSize = inside + extra）。
- AC-006：re_verified — `testSiblingMeasurementsDoNotBlockListingAnotherDirectory`、`testNavigationBackToCachedLevelIsImmediate`；listing 中旧名单保留由 `testBackIsIgnoredWhileListing` 断言 `level.path` 不变佐证。
- AC-007：re_verified — 同上 `testSiblingMeasurements…`（Alpha 阻塞时 Beta 名单先出现）。
- AC-008：re_verified — `DiskScannerTests.testSymlinkCountsOnlyItself`（只计链接自身 `st_blocks`，2MB 目标不计入）。
- AC-009：re_verified — `DiskScannerTests.testMeasureSumsDescendantsAndDedupesHardLinks`（真实 `linkItem`）+ `DiskExplorerTests.testHardLinkedFilesCountOnceInTheLevelTotal`。
- AC-010：re_verified — 两条 `testUnreadableDirectoryIsMarkedAndExcluded`（注入 unreadable + `chmod 000` 真实目录）。
- AC-011：re_verified — `testOtherDeviceDirectoryStaysOutOfTheParentTotal`（不计入父合计、`measureRequests` 为空、进入后 900）。
- AC-012：re_verified — `testDiskSourcesDoNotRunMoleCommands` 通过（证据强度见 f002）。
- AC-013：re_verified — `testDiskPageHasNoDeleteControl` 源码扫描通过。
- AC-014：re_verified — `DiskScannerTests.testListingMarksDirectoriesComputingAndFilesSized` 与测试侧独立 `lstat` 对比。
- AC-015：re_verified（spec 授权的替代口径，真实拖拽不可注入）— `testSplitLayoutClampsBothPanes` + `testSplitHandleBindsDragGesture`。
- AC-016：re_verified（同上）— `testOpeningAFileDoesNotEnterIt` + `testDiskListRowDropsOpenButtonAndKeepsDoubleClickEntry`。
- AC-017：re_verified（同上）— 同一源码断言 + `openDirectory` 的 `isDirectory` 守卫用例。
- AC-018：re_verified — `testShareAndBarFractionHandleBoundaries` + 列表合计断言（纯函数口径经 spec 授权）。
- AC-019：re_verified — `testShareAndBarFractionHandleBoundaries`（0 / 100% / >100% 边界）。

coverage = 19 / 19（AC-012/015/016/017 以 spec 授权的替代证据复验：源码/视图层断言而非真实手势或运行时命令记录，证据强度见 f002 与提示；无 trust_prior 项。）

reviewed_scope: 9e3527df4325335b

verdict: FAIL

______________________________________________________________________

## Round 2 (2026-10-17T01:40:06+08:00)

- diff_anchor：`3d42958b84fbfc08d96a24d20b3a8613ee31f3a6`（同 Round 1）
- 门禁复跑：`xcodebuild test -scheme Zmole -destination 'platform=macOS'`（derivedData 落预批临时目录，工作区无改动）→ **212 tests、0 failures**；xcresult 确认新增 4 条用例已执行：`testBreadcrumbJumpReturnsToCachedAncestor`、`testNameSortOrdersRowsAndKeepsTheirSizes`、`testListingFailureShowsErrorAndStillAllowsGoingBack`、`testRevealForwardsTheEntryPath`。
- 本轮 worktree 无 reviewer 不可见未跟踪交付文件（`git status -uall` 仅源码/测试改动 + 流程文件）。

### 前轮 finding 复核（以 diff 与测试断言为准，不采信处置表自述）

|finding_id|severity|复核结论|证据（本轮 diff / 测试）|
|---|---|---|---|
|t028_test_f001|important|**已修**：四条覆盖逐条核实，均以真实行为断言补回，无「修成另一种弱化形式」|见下四条|
|t028_test_f002|minor|**已修**（按 minor 口径）：装配点已纳入断言，与 Round 1 建议的最小修复一致|`tests/unit/DiskExplorerTests.swift:381-389`、`:430-437`|

f001 四条逐项：

1. reveal 转发 — 新增 `testRevealForwardsTheEntryPath`（`tests/unit/DiskExplorerTests.swift:353-369`），恢复 `DiskRevealerSpy`（`:473-476`）。以有界轮询等待异步 reveal 后**硬断言** `paths == ["/root/readme.txt"]`；不转发、传错路径、重复转发都会失败。非条件跳过（断言在轮询外无条件执行）。
2. breadcrumb `open(path:)` 回跳 — 新增 `testBreadcrumbJumpReturnsToCachedAncestor`（`:273-314`）：从 `/root/sub/deep` 跳 `/root/sub`、再跳 `/root`，断言 `level.path` 两次回跳结果、`canGoBack` 翻转，并以 `listRequests == ["/root", "/root/sub/deep"]` 证明回跳全部命中缓存、未重新列举。
3. 名称排序 — 新增 `testNameSortOrdersRowsAndKeepsTheirSizes`（`:316-330`）：byName `["Alpha","Beta","Zeta"]` 且 `knownSize == [30, nil, 10]`（保留且不改字节），bySize 交叉校验 `["Alpha","Zeta","Beta"]`。
4. 列表失败与返回 — 新增 `testListingFailureShowsErrorAndStillAllowsGoingBack`（`:332-351`）：进入无列举的目录后断言 `level == nil`、`errorMessage != nil`、`canGoBack` 保持；`goBack()` 后恢复缓存层 `/root` 且 `errorMessage == nil`。复核了后台测量与失败列举的交错路径，断言在各交错下稳定。

f002：`testDiskSourcesDoNotRunMoleCommands` 追加 `assemblySource()`（`:430-437`）并断言生产装配 `AnalyzeViewModel(scanner: LiveDiskScanner(), root: "/")`、demo 装配 `scanner: DemoDiskScanner(state: configuration.state)` 与 `src/zmole/App/AppDependencies.swift:538-543` 实际内容一致（套件通过佐证）。残余仍为源码字符串代理的固有权衡（纯格式化重构会误红、新增旁路文件不受限），按 minor 处置口径视为已消除，不再计 finding。

### 改测方向复核（本轮）

- 无「迁就实现」改测：对照 Round 1 审过的测试内容，本轮对既有测试**零修改**——diff 仅插入 4 个新 `test` 方法与恢复的 spy actor，另在 AC-012 用例内追加装配断言；既有断言未删改、未弱化。
- 生产侧本轮另有 code-review 修复（`LiveDiskScanner.childPath` / `directoryPrefix` 统一路径拼接，`AnalyzeViewModel.swift:221`、`DiskScanner.swift:150-157`；blueprint 补跨层硬链接语义）：行为保持型重构，测试断言未变，套件全绿。

### 本轮新发现

0 条。

### 结论

- 未进表的提示：跨层硬链接语义（父层直接列出 + 子目录内再现同一 inode，子层合计不重复计入）现已写入 `docs/blueprint/architecture.md` 磁盘页扫描节，仍无直接用例，可选补 case 锁定；AC-012/015/016/017 的源码字符串代理断言为 spec 授权的替代口径，格式化重构误红属已知代价；Round 1 提示的 AC-005 子树替换直接断言、名单顺序等延续，均为可选覆盖扩展。
- 总体判断：f001（important）与 f002（minor）均以 diff/测试核实真修，本轮无新 blocker，可 PASS。
- 系统性 follow-up：无。

### AC 复验方式（本轮）

复验命令同上门禁（212 tests、0 failures）。

- AC-001–AC-014：re_verified — 沿用 Round 1 的用例映射，本轮套件重跑全绿；AC-012 证据增强为「三源文件扫描 + 生产/demo 装配点断言」。
- AC-015、AC-016、AC-017：re_verified（spec 授权的替代口径，真实手势不可注入）— `testSplitLayoutClampsBothPanes` / `testSplitHandleBindsDragGesture` / `testDiskListRowDropsOpenButtonAndKeepsDoubleClickEntry` / `testOpeningAFileDoesNotEnterIt`。
- AC-018、AC-019：re_verified — `testShareAndBarFractionHandleBoundaries` + 合计断言。

coverage = 19 / 19（无 trust_prior 项）。

reviewed_scope: 70d19f4c797abae5

verdict: PASS

# Task review t018（reviewer_focus: test）

- task: t018_clean_page（清理页整次预览后执行）
- spec: `docs/tasks/t018_clean_page/spec.md`
- diff_anchor: `ef1efac64fa4d2338b4ff5e421b26f4512d91fb0`
- target: `git -C '/Users/karson/kar/code/zmole_t018' diff ef1efac64fa4d2338b4ff5e421b26f4512d91fb0`（new files intent-to-add）
- round: 1
- reviewed_at: 2026-10-16T19:00:00+08:00

## 验证记录

- `xcodebuild test -scheme Zmole -destination 'platform=macOS'` → 129 passed（含 `CleanPageTests` 8 例全绿）。
- `pytest .repo_template/tests -q -m contract` → 147 passed。
- `bash tests/integration/clean_trash_test.sh` → `clean_trash_routing: all cases passed`。
- 危险模式扫描：测试全部走临时目录 + 假 `MoleProcessControlling`，`confirmExecution` 触发的假 `clean` 只返回固定文本，无真实删除、无网络、无写工作区外路径。未见危险模式。

## Findings

### t018_test_f001 - 生产 streaming 预览分支无任何测试覆盖

- 严重度：important
- 锚点：`src/zmole/Features/Clean/CleanViewModel.swift:133-156`、`src/zmole/App/AppDependencies.swift:349`
- 位置：`tests/unit/CleanPageTests.swift`、`tests/unit/ZmoleTests.swift`
- 问题：`runDryRun` 有两条分支：注入 `streaming` 时逐行解析阶段（`CleanViewModel.swift:143-152`），否则回退 `process.run` 一次性解析（`:135-140`）。生产（非 demo）装配恒传 `streaming`（`AppDependencies.swift:349`，`configuration.isEnabled` 仅 `--demo` 时为真），即生产走 streaming 分支且 `cancelPreview` 走 `streaming.cancel()`（`:160-164`）。所有 clean 测试（`CleanPageTests` 与既有 `ZmoleTests`）都未注入 `streaming`（默认 nil），只覆盖回退分支。于是生产实际使用的阶段逐行更新与 stream 取消路径零覆盖；spec 可测试性声明明确要求「假 Bridge 输出阶段行」自动断言，此处未落地（全仓仅有 `StatusStreamTests.FakeStatusStreaming`，clean 无假 streaming）。
- 建议：补一个假 `MoleStreaming`（yield `.stdoutLine("…➤ Browsers…")`）注入 `CleanViewModel`，断言阶段随流更新、`cancelPreview` 调用 streaming 取消而非 `process.cancel()`。

### t018_test_f002 - `currentStage` 从未被断言，AC-004 的「输出→阶段→译名」绑定未验证

- 严重度：minor
- 锚点：`src/zmole/Features/Clean/CleanViewModel.swift:139,150`
- 位置：`tests/unit/CleanPageTests.swift`
- 问题：全仓测试只引用 `lastReclaimBytes`，没有一处引用 `viewModel.currentStage`。`testPreviewUsesDryRunAndExecutesOnlyAfterConfirmation` 的假进程 stdout 就是 `"➤ Browsers\n"`，本可断言 `currentStage?.raw == "Browsers"`，却未断言。AC-004 只靠 `CleanStageCatalog.stage(fromLine:)`/`lastStage(in:)` 纯函数测试，从「扫描输出」到「视图模型暴露阶段」再到界面译名的链路无端到端断言。
- 建议：在 `testPreviewUsesDryRun…` 中加 `XCTAssertEqual(viewModel.currentStage?.localizedKey, "clean.stage.browsers")`，并在取消/重扫后断言 `currentStage == nil`。

### t018_test_f003 - AC-005 角标数值断言自指（期望值由被测解析器同源算出）

- 严重度：minor
- 锚点：`tests/unit/CleanPageTests.swift:84,89`
- 位置：`CleanPageTests.swift:83-89`
- 问题：`expected = CleanPreviewParser.reclaimBytes(from: fixture)`，而 `viewModel.lastReclaimBytes` 来自 `snapshot.reclaimBytes`，两者都是 `CleanPreviewParser.sections(from:)` 的同一 reduction（`CleanPreview.swift:45-51`、`CleanPreviewModel.swift:23-31`、`:52-54`）。期望值与被测值走完全相同的代码路径，解析/求和若有 bug 会同步错，断言恒真。AC-005「角标等于本次预览可回收量」的数值正确性并未独立验证，只验证了 nil/非 nil。
- 建议：改用独立常量，如 fixture 对应 `2_400_000_000 + 512_000_000 = 2_912_000_000`，断言 `lastReclaimBytes == 2_912_000_000`。

### t018_test_f004 - AC-003 缺少「无子集执行控件」断言

- 严重度：minor
- 锚点：`spec.md:63`（测试策略）、`tests/unit/CleanPageTests.swift:100-131`
- 位置：`tests/unit/CleanPageTests.swift`
- 问题：AC-003 含两半：(a) 页面没有按勾选子集执行的控件；(b) 保护路径写入白名单并使预览失效。(b) 由 `testProtectingPathInvalidatesCurrentPreview` 覆盖（并结合既有白名单 save 测试）。(a) 无任何断言——既无行为断言也无源码扫描断言（对比既有 `testCleanExecutionNoteUsesLocalizedCatalogKey` 已示范源码内容断言）。spec 测试策略明确列出「增加…『无子集执行控件』断言」，未落地。
- 建议：加源码扫描断言，`CleanView.swift` 不含勾选态/子集执行控件（如无 `Toggle`/selection-set 驱动的执行按钮），或断言执行路径只暴露单一整次 `clean.execution` 入口。

### t018_test_f005 - AC-004 阶段译名未校验 `Localizable.xcstrings` 键存在

- 严重度：minor
- 锚点：`tests/unit/CleanPageTests.swift:15-33`、`CleanScanStage.swift:28-33`
- 位置：`CleanPageTests.swift`
- 问题：`testStageCatalogCoversBundledCleanSections` 只断言 `CleanStageCatalog.key(for:)` 非 nil，`testStageParsingStripsANSIAndLocalizesKnownSection` 只断言返回的 key 字面量。两者都不校验该 key 在 `Localizable.xcstrings` 中真有 zh-Hans 译文。若 `clean.stage.*` 条目缺失，`Text(LocalizedStringKey(key))`（`CleanView.swift:165`）会渲染原始 key，而测试仍全绿——AC-004「显示译名」可静默失效。现有 15 个键确实齐全，但该回归不会被捕获。
- 建议：在 catalog 测试中读取 `Localizable.xcstrings`，断言每个 `keys` 值在 strings 中存在且 `zh-Hans` 有值（复用 `testCleanExecutionNoteUsesLocalizedCatalogKey` 的读法）。

## 结论

- 本轮新发现：5 条（0 critical / 1 important / 4 minor）。
- AC 覆盖：
    - AC-001：充分（`testCleanPreviewUsesDryRun…`、`testCleanConfirmationRunsCleanWithoutDryRun`、`testCleanNonZeroDryRunCannotConfirmOrExecute`）。
    - AC-002：充分（`testCleanConfirmationCancelExpiresPreviewWithoutExecution` + `CleanPreviewStore.verifyUnchanged` 既有测试）。
    - AC-003：半覆盖，缺 (a) 子集控件断言（f004）。
    - AC-004：映射函数覆盖好，但生产 streaming 链路与 `currentStage` 绑定未测（f001/f002），译名键存在性未校验（f005）。
    - AC-005：nil/非 nil 正确，数值断言自指（f003），另 `SidebarView` 读 `lastReclaimBytes` 无源码断言。
    - AC-006：充分（`testCleanExecutionFailurePersistsErrorStateAndSummary`，持久字段 + 视图 resultNotices）。
    - AC-007：充分（`testZhHansCleanCopyMentionsTrash` 校验 3 个键含「废纸篓」且不含「永久删除」）。
- 未进表的提示：clean 页展示 demo 预览（`DemoMoleProcess` 写无 `=== section ===` 头的列表）会归入 `Other` 分类；非 AC，仅提示。测试无法独立复核 `SidebarView` 角标渲染，属 GUI，按约定不作为 blackbox 门禁。
- 红绿灯归属：全部门禁绿灯（129 / 147 / shell 集成），无失败测试需要归因；上述 finding 均为覆盖缺口而非红灯。
- 总体判断：实现与既有测试质量良好，fixture 与真实 `clean.sh` 导出格式（`=== Name ===` + `path  # 2.4 GB, 18 items`）保真，阶段目录测试对真实 `start_section` 做反向覆盖值得肯定。但生产 streaming 预览分支（AC-004 的实际运行路径）完全无覆盖，属重要缺口，本轮不得 PASS。

verdict: FAIL

### Round 2 (2026-10-16T19:05:00+08:00)

#### 处置确认

|finding_id|severity|status|rationale|fix_ref|
|---|---|---|---|---|
|t018_test_f001|important|已修|新增注入 `CleanPageStreaming` 假流的两例：`testStreamingPreviewShowsLiveStageAndAcceptsPreview` 覆盖生产 streaming 预览链路（断言流侧 argv、`currentStage`、预览被接受、可回收量），`testCancelPreviewCancelsTheStreamingProcess` 覆盖 `cancelPreview` 经 `streaming.cancel()` 传播（`cancelCount >= 1`、`isPreviewing` 归 false）。|tests/unit/CleanPageTests.swift:106-160|
|t018_test_f002|minor|已修|`currentStage?.raw` / `localizedKey` 在 streaming 测试中断言，回退分支外的生产绑定已触达。|tests/unit/CleanPageTests.swift:130-132|
|t018_test_f003|minor|已修|期望值改为独立常量 `2_400_000_000 + 512_000_000`，不再经被测解析器推导；streaming 测试同样用硬编码值。|tests/unit/CleanPageTests.swift:84,132|
|t018_test_f004|minor|已修|新增 `testCleanViewHasNoSubsetExecutionControl` 扫描 `CleanView.swift` 的禁用标识符（`Toggle(`、`Checkbox`、`selectedEntries`、`cleanSelected`、`selectAll`）。|tests/unit/CleanPageTests.swift:162-172|
|t018_test_f005|minor|已修|新增 `testStageLocalizationKeysHaveThreeLocales` 遍历 `CleanStageCatalog.sections`，校验每个键在 `Localizable.xcstrings` 中 en/zh-Hans/zh-Hant 均有非空值。|tests/unit/CleanPageTests.swift:174-192|

#### 甄别度复核

- f001 新测试具甄别力：假 `MoleProcessControlling` 与假 `MoleStreaming` 分别记录 argv；若 `runDryRun` 未走注入流，`streaming.recordedArguments` 为空即失败；若阶段未逐行更新，`currentStage` 断言失败。取消测试以 `block: true` 挂起流，验证取消确实路由到流而非 `process.cancel()`。
- f003 新断言独立：`lastReclaimBytes` 必须等于硬编码 2.912e9，解析/求和路径若偏移即失败，不再自证。
- f005 新断言独立：从真实 `Localizable.xcstrings` 取值，删任一 `clean.stage.*` 条目即失败，弥补此前「只认字面量 key」的盲区。
- f004 残留局限（不阻塞）：负向断言为标识符 blocklist，只能证明不含这些命名，无法证明不存在任何形态的子集执行控件；当前设计确无选择态（单一整次执行入口），可接受。

#### 门禁复跑

- `xcodebuild test -scheme Zmole -destination 'platform=macOS'` → 133 passed（`CleanPageTests` 12 例全绿）。
- `pytest .repo_template/tests -q -m contract` → 147 passed。
- `bash tests/integration/clean_trash_test.sh` → `clean_trash_routing: all cases passed`（8/8）。
- 危险模式扫描：新测试仍只用临时目录 + 假进程/假流，无真实删除、无网络、无越界写入。

#### 结论

- 本轮新发现：0。
- AC 覆盖（复核后）：AC-001/002/003/004/005/006/007 均有可自动断言且有甄别力的测试；round 1 的 5 条 finding 全部已修，无遗留 critical/important。
- 红绿灯归属：全部门禁绿灯，无失败测试。
- 总体判断：round 1 的覆盖缺口已闭合，生产 streaming 阶段链路、角标数值、阶段译名键、无子集控件均获独立断言，测试可信度达标。

reviewed_scope: 8a70ed92bb4d7e6c

verdict: PASS

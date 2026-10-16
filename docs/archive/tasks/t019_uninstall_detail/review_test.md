# Task review t019（reviewer_focus: test）

- task: t019_uninstall_detail（卸载列表详情与多选）
- spec: `docs/tasks/t019_uninstall_detail/spec.md`
- diff_anchor: `88be325cacc5c76cdc0a7c76bfea2436df35953b`
- target: `git -C '/Users/karson/kar/code/zmole_t019' diff 88be325cacc5c76cdc0a7c76bfea2436df35953b`（new files intent-to-add）
- round: 1
- reviewed_at: 2026-10-16T19:18:00+08:00
- review_level: full

## 验证记录

- `xcodebuild test -scheme Zmole -destination 'platform=macOS'` → 142 passed，0 failures；其中 `UninstallDetailTests` 9 例全绿，既有 `UninstallTests`（11）、`BatchUninstallTests`（4）原样保留并通过。
- `pytest .repo_template/tests -q -m contract` → 147 passed（`uv run --no-project --with pytest`，本机无全局 pytest）。
- 新增测试全部经生产 `UninstallViewModel` 驱动，仅替换 `MoleProcessControlling` / `UninstallMetadataProviding` / `FileRevealing` 三个外部边界替身（`DetailProcessSpy` / `FakeMetadataProvider` / `RevealerSpy`），未 mock 被测逻辑。
- 危险模式扫描：无 `.skip` / `.only` / 注释或删除断言；无恒真或自指断言；无 force-unwrap；无真实废纸篓/Finder/网络副作用；`try?` 仅用于 `RevealerSpy` 的 sleep 轮询。唯一可疑项是 AC-005 的负向断言（见 f002）。

## Findings

### t019_test_f001 - AC-001「搜索过滤后已选 path 仍保留」零覆盖

- 严重度：minor
- 锚点：`spec.md:33`（AC-001）、`spec.md:49,61`（可测试性声明、测试策略「搜索不清选择」）；`src/zmole/Features/Uninstall/UninstallView.swift:13,22-41`；`src/zmole/Features/Uninstall/UninstallViewModel.swift:123-149`
- 位置：`tests/unit/UninstallDetailTests.swift`（无对应用例）
- 问题：AC-001 含两半：(a) 详情显示名称与 path，(b) 搜索过滤后已选仍保留。(a) 由 `testFocusAndSelectionAreIndependentOfEachOther`（:22-34，断言 `focusedAppID`/`focusedApp?.path`/`selectedIDs`）覆盖。(b) 无任何断言：搜索是 `UninstallView` 的 view-local `@State search` + `visibleApps` 过滤（:22-41），`selectedIDs` 只由 `toggleSelection`/`selectAll`/`clearSelection`/`loadList` 改动，搜索不经过 ViewModel，全仓测试无一处引用搜索/过滤。spec 可测试性声明与测试策略都点名「搜索不清选择」，未落地；若未来把搜索态接进 ViewModel 并误清选择，现测试不会变红。参照 t018 对同类「策略点名但未落地」缺口的定级，此为 minor。
- 建议：将显示过滤抽成可测纯函数（如 `UninstallViewModel.visibleApps(matching:source:sort:)` 或独立 filter helper），断言先选 A/B 再按仅命中 A 的关键字过滤后 `selectedIDs` 不变；或对 `UninstallView.swift` 搜索分支做源码扫描，断言其不调用 `clearSelection()`。

### t019_test_f002 - AC-005「不含关联体积」未验证；断言与命名/AC 错位

- 严重度：minor
- 锚点：`spec.md:37`（AC-005「多选合计文本含本体估计，不含关联体积」）、`spec.md:16`（范围「不加上关联文件体积，也不写成已释放空间」）；`tests/unit/UninstallDetailTests.swift:116-137`；`src/zmole/Features/Uninstall/UninstallView.swift:47-53,113-141`
- 位置：`tests/unit/UninstallDetailTests.swift:116-137`
- 问题：`testUnknownSizeIsNilAndTotalUsesBodyEstimateWording` 只做两件事：`app.sizeBytes == nil`（AC-005 前半，与既有 `BatchUninstallTests` 的解析器测试重叠），以及校验 zh-Hans 的 `uninstall.selected_total_app_estimate` 文案含「本体估计」且不含「释放」。`XCTAssertFalse(value.contains("释放"))` 对应的是范围里的「不写成已释放空间」，被误挂在 AC-005「不含关联体积」名下。真正要担保的合计数值逻辑 `knownSelectedBytes = selectedApps.compactMap(\.sizeBytes).reduce(0,+)`（View:47-49，只累加本体 size，天然不含关联体积）无任何断言；若合计口径改成把关联路径体积计入，本测试仍绿。测试名 `...TotalUsesBodyEstimateWording` 也易读成「合计取值」，实际只校验标签文案。
- 建议：把合计计算提为可测函数并用独立常量断言（例如两个已知 size 的已选项 → 硬编码期望字节数），或直接断言 `knownSelectedBytes` 只由 `sizeBytes` 得出；负向「不写成已释放空间」的断言保留但改挂到范围条目。

### t019_test_f003 - AC-003 只验数据源为 nil，未验界面「未知」映射

- 严重度：minor
- 锚点：`spec.md:35`（AC-003）；`tests/unit/UninstallDetailTests.swift:36-46`；`src/zmole/Features/Uninstall/UninstallView.swift:222-225,320-325`
- 位置：`tests/unit/UninstallDetailTests.swift:36-46`
- 问题：`testMetadataShowsUnknownWhenMissing` 断言 `metadata?.version`/`lastUsed` 为 nil，即「数据源缺字段」。AC-003 是「详情显示未知」，其映射在 View：`metadata(for:)?.version ?? String(localized: "uninstall.unknown")`（:223,249）与 `lastUsedText` 的 `?? uninstall.unknown`（:321-322）。无测试断言 nil → `uninstall.unknown`；若 View 去掉 fallback（显示空串或 key 原文），现测试仍绿。对比 AC-005 的测试读了 `Localizable.xcstrings`，`uninstall.unknown` 键虽已在 catalog（:319），但无一条断言把它与被测的 nil 分支绑定。
- 建议：对 `uninstall.unknown` 做与 `testUnknownSizeIsNilAndTotalUsesBodyEstimateWording` 相同的 catalog 断言（键在 en/zh-Hans/zh-Hant 均有非空值），让「nil 显示未知」的译名链路有独立保护。

### t019_test_f004 - AC-004 用例命名夸大 dry-run 归属；替身忽略 argv

- 严重度：minor
- 锚点：`spec.md:36`（AC-004）；`tests/unit/UninstallDetailTests.swift:58-74,165-191`；`src/zmole/Features/Uninstall/UninstallViewModel.swift:191-207`
- 位置：`tests/unit/UninstallDetailTests.swift:58-74`
- 问题：`testRelatedPathsOnlyComeFromThatAppsDryRun` 断言「未 dry-run 时 `relatedPaths` 为 nil」「dry-run 后等于原文路径」，覆盖 AC-004 语义，但 `DetailProcessSpy`（:184-186）对任意 `--dry-run` 一律返回同一 `dryRunOutput`，不看 `app.uninstallName`。因此该用例无法证明 dry-run 被限定到该项；若 `loadRelatedFiles` 回归成传错名或不传名，用例仍绿（名字「OnlyComeFromThatApps」夸大）。另 `loadRelatedFiles` 的身份校验失败分支（`UninstallSelectionValidator.batch` throw → 置 `[]`，:193-196）无覆盖。
- 建议：断言 `process.invocations` 中的 dry-run 调用参数恰为 `["uninstall", "--dry-run", app.uninstallName]`；补一条同名冲突 app 的用例，断言 `relatedPaths(for:) == []` 且不发起 dry-run。

### t019_test_f005 - AC-002 多选仅验到 dry-run，多选确认执行 argv 未端到端覆盖

- 严重度：minor
- 锚点：`spec.md:34`（AC-002「一次确认可以卸载多个已选项」）；`tests/unit/UninstallDetailTests.swift:6-20`；`tests/unit/UninstallTests.swift:51-82`；`src/zmole/Features/Uninstall/UninstallViewModel.swift:332-336`
- 位置：`tests/unit/UninstallDetailTests.swift:6-20`
- 问题：`testBatchPreviewUsesOnlySelectedUninstallNamesAndConfirmationInput` 只覆盖多选的 **preview**（`uninstall --dry-run Alpha App Beta Tool` + `y\n`）。真正「一次确认卸载多个」的执行 argv（`["uninstall"] + currentBatch.map(\.uninstallName)`）在所有测试中只有单项（`UninstallTests` 的 `confirmExecution` 用例仅选一个 app）。多选执行时的名字顺序/个数、确认后 `fetchList()` 身份复核整体链路未端到端断言；`BatchUninstallResultParser` 的多计数解析虽有独立单测，但与本任务的 ViewModel 执行路径未串联。
- 建议：补一条两选确认用例，断言调用序列含 `["uninstall", "Alpha App", "Beta Tool"]`（无 `--dry-run`）、`y\n` stdin，并在第二次 `--list` 返回相同 list 时 `result.status == .succeeded`。

### t019_test_f006 - AC-007 取消用例的「不执行」断言偏弱且带竞态

- 严重度：minor
- 锚点：`spec.md:39`（AC-007）；`tests/unit/UninstallDetailTests.swift:99-114`
- 位置：`tests/unit/UninstallDetailTests.swift:110-111`
- 问题：`testCancelConfirmationDoesNotExecuteUninstall` 在 `cancelConfirmation()` 后断言无「非 dry-run/list 的 uninstall」调用，但没有触发任何执行路径，断言近乎恒真；且若实现改为在取消时 `Task { confirmExecution() }`，该断言在 `cancelConfirmation()` 返回后立即取值会与 Task 竞争而漏检。真正该验的是「取消后执行入口不可达」，未被证。
- 建议：取消后显式 `await viewModel.confirmExecution()`，断言不产生 `["uninstall", ...]` 调用、`isConfirmationPresented == false`、`preview == nil`、`canConfirm == false`，使「不执行」有真实判别力。

## 结论

- 本轮新发现：6 条（0 critical / 0 important / 6 minor）。
- 改测方向复核：未就地改写既有测试预期；`UninstallTests` / `BatchUninstallTests` 原样保留（旧行内详情无障碍测试 `testUninstallAccessibilityKeepsCompleteApplicationIdentityReachable` 仍通过）。新增 fakes 位于外部边界，未 mock 被测逻辑。
- 异步等待复核：`testRevealInFinderUsesTheAppPath`（:86-97）用 `Task.sleep(100ms)` 等 `revealInFinder` 派生 Task 写完 actor，属时序等待，非确定性但风险低（仅本用例）。其余用例均 `await` ViewModel 的 async 方法，无静默超时。
- AC 覆盖：
    - AC-001：**半覆盖**。详情名称/path 与焦点-选择独立由 `testFocusAndSelectionAreIndependentOfEachOther` 覆盖；「搜索过滤后已选保留」零覆盖（f001）。
    - AC-002：覆盖。多选 argv 与 `y\n` 由 `testBatchPreviewUsesOnlySelectedUninstallNamesAndConfirmationInput` 精确断言；身份校验（同名/改 path/目标消失/选项形态名）由既有 `BatchUninstallTests` + `UninstallTests` 覆盖；缺口仅多选**执行**未端到端（f005）。
    - AC-003：半覆盖。数据源 nil 有断言，「未知」界面映射未断言（f003）。
    - AC-004：覆盖。前置 nil、dry-run 原文路径、空结果三态均有断言；归属 scoping 与校验失败分支未覆盖（f004）。
    - AC-005：半覆盖。不可解析 size 为 nil 有断言；「含本体估计」文案有断言；「不含关联体积」与合计数值未验证，负向断言错位（f002）。
    - AC-006：覆盖。`testRevealInFinderUsesTheAppPath` 经替身断言路径等于 `app.path`，满足「用该项 path，不用演示路径」。
    - AC-007：覆盖但断言偏弱（f006）。
- 红绿灯归属：全部门禁绿灯（142 / 147），无失败测试需归因；全部 finding 为覆盖/断言强度问题，非红灯。
- 未进表的提示：生产装配 `AppDependencies.swift:356` 走默认 `LiveUninstallMetadataProvider` / `LiveFileRevealer`，二者触达真实文件系统与 `NSWorkspace`，属环境受限路径，按约定（有意不测真实废纸篓/Finder）不作为门禁；`loadAllMetadata`（ViewModel:184-189）作为列表行版本预取的运行分支无直接断言，风险低，仅记录。
- 总体判断：实现与测试质量良好——核心新行为（多选 argv、关联路径只来自 dry-run、Finder 用真实 path、取消不执行）均有触达生产逻辑的断言，替身边界干净，未见恒真/自指/危险模式。缺口集中在 AC-001 搜索语义与 AC-005 合计口径两条子句的覆盖不足及若干弱断言，均为 minor，不阻断本轮验收。

reviewed_scope: c4a36263b9bd6012

verdict: PASS

### Round 2 (2026-10-16T19:22:00+08:00)

#### 处置确认

|finding_id|severity|status|rationale|fix_ref|
|---|---|---|---|---|
|t019_test_f001|minor|已修|抽出 `UninstallListFilter.visible` 作为搜索/来源过滤的唯一真相源（`UninstallView.visibleApps` 改调它），新增 `testSearchFilterHidesRowButKeepsSelection`：选 Alpha 后按 `search:"Beta"` 过滤得到 `["Beta Tool"]`，且 `selectedIDs` 仍为 `[Alpha]`。搜索过滤现经生产函数验证，选择保留有断言。|UninstallSnapshot.swift:148-160；UninstallDetailTests.swift:139-148|
|t019_test_f002|minor|部分修|新增 `sizeText`（UninstallSnapshot.swift:25-28）与 `testZeroSizeStringIsUnknown`，AC-005 前半「不可解析 size 显示未知」由 `unknown`/`0` 两例覆盖。但 AC-005 后半「不含关联体积」的合计数值口径仍未测：`knownSelectedBytes` 仍是 `UninstallView` 私有计算（:40-41，`selectedApps.compactMap(\.sizeBytes).reduce`），未抽出，`不含释放` 负向断言仍在，与「不含关联体积」错位问题未变。|UninstallDetailTests.swift:116-137,172-179|
|t019_test_f003|minor|未修|`testMetadataShowsUnknownWhenMissing` 与 round 1 逐字相同（仅断言 `version`/`lastUsed` 为 nil），未新增 nil→`uninstall.unknown` 的映射断言。实现侧给的是 UI 由生产代码保证的理由，非测试。|—|
|t019_test_f004|minor|未修|`testRelatedPathsOnlyComeFromThatAppsDryRun` 与 round 1 逐字相同；`DetailProcessSpy`（:207-233）仍对任意 `--dry-run` 返回同一 `dryRunOutput`，未断言 dry-run argv 归属该项，校验失败分支仍无覆盖。AC-004 语义（前 nil、原文路径、空结果）本已覆盖，残留的是 scoping 与命名夸大。|—|
|t019_test_f005|minor|已修|新增 `testConfirmationExecutesOnlySelectedBatch`：两选确认后断言执行 argv 恰为 `["uninstall","Alpha App","Beta Tool"]`（无 `--dry-run`）且 `preview == nil`，走真实 `confirmExecution`（含第二次 `--list` 身份复核）。|UninstallDetailTests.swift:150-170|
|t019_test_f006|minor|未修|`testCancelConfirmationDoesNotExecuteUninstall` 与 round 1 逐字相同，未在取消后调用 `confirmExecution`；「不执行」断言仍近恒真且取值早于任何派生 Task，判别力未提升。AC-007 语义已覆盖。|—|

#### 甄别度复核

- f001 新用例具甄别力：若 `UninstallListFilter.visible` 回归成不过滤（或搜索匹配字段收窄），`visible.map(\.name) == ["Beta Tool"]` 即失败；`selectedIDs` 断言本身偏弱（纯函数无从改选择，唯有把清选逻辑接入过滤才会红），但配合「过滤后可见行不含被选项」仍能表达 AC 语义。
- f005 新用例具甄别力：执行 argv 精确枚举两项名，漏传/少传/错序即失败；确认后经真实 `confirmExecution` 的 `fetchList` 身份复核与 preview 清空断言，非自证。
- f002 新增 `testZeroSizeStringIsUnknown` 具甄别力（`sizeBytes`/`sizeText` 对 "0" 均 nil）；但合计口径残留使 AC-005 后半仍无独立断言。
- f003/f006 残留：未见新增断言；f004 残留：AC 语义已覆盖，argv 归属仍无断言。

#### 门禁复跑

- `xcodebuild test -scheme Zmole -destination 'platform=macOS'` → 145 passed（`UninstallDetailTests` 12 例全绿，较 round 1 增 3）。
- `pytest .repo_template/tests -q -m contract` → 147 passed。
- 危险模式扫描：新增三例无 `.skip` / `.only` / 注释断言 / force-unwrap / 恒真自指；`testSearchFilterHidesRowButKeepsSelection` 的 selection 断言甄别力偏弱，已记入 f001。

#### 结论

- 本轮新发现：0。round 1 六条处置为 2 已修（f001/f005）、1 部分修（f002）、3 未修（f003/f004/f006），全部仍为 minor，无 critical/important。
- AC 覆盖（复核后）：
    - AC-001：覆盖（f001 已修，搜索过滤经生产函数 + 选择保留有断言）。
    - AC-002：覆盖（f005 已修，多选执行 argv 端到端断言）。
    - AC-003：半覆盖（f003 未修，nil→`uninstall.unknown` 显示映射无断言）。
    - AC-004：覆盖（f004 未修，语义三态已覆盖，仅 argv 归属/命名残留）。
    - AC-005：半覆盖（f002 部分修，size 未知已覆盖；合计「不含关联体积」口径仍未测）。
    - AC-006：覆盖（`testRevealInFinderUsesTheAppPath` 经替身断言 `app.path`）。
    - AC-007：覆盖但断言偏弱（f006 未修）。
- 红绿灯归属：全部门禁绿灯（145 / 147），无失败测试需归因。
- 总体判断：round 1 中两条最实质缺口（AC-001 搜索、AC-002 多选执行）以具甄别力、触达生产逻辑的测试闭合，测试可信度较 round 1 提升；剩余 f002 合计口径、f003/f004/f006 均为 minor 覆盖/断言强度问题，不阻断本轮验收，且无新增问题。

reviewed_scope: 4bc03310009e7dd3

verdict: PASS

### Round 3 (2026-10-16T19:26:00+08:00)

#### 焦点复核：related-path 测试仍触达生产逻辑且有甄别力

- 生产侧：关联文件 dry-run 改为显式动作——`UninstallView` 在 `relatedPaths == nil` 时展示 `uninstall.files_not_loaded` + `uninstall.files_check` 按钮（View:288-290）调用 `viewModel.loadRelatedFiles(for:)`；`loadDetail`（ViewModel:170-177）不再自动跑 dry-run，只加载元数据。`loadRelatedFiles`（ViewModel:191-212）改为 public，并新增协调器租约（:198 `coordinator.acquire(.uninstall)` + `defer { lease.release() }`），保证与单槽命令桥上的批量 preview/execution 互斥。
- 测试侧：`testRelatedPathsOnlyComeFromThatAppsDryRun`（:58-74）与 `testRelatedPathsEmptyWhenDryRunHasNoPaths`（:76-84）改为直接 `await viewModel.loadRelatedFiles(for: app)`。
- 判定：**仍触达生产逻辑，且有甄别力**。调用链为真实的 `UninstallViewModel.loadRelatedFiles` → 真实 `UninstallSelectionValidator.batch` → 替身进程 `process.run(["uninstall","--dry-run",…])`（仅外部边界）→ 真实 `relatedPaths(from:)` 解析 → 写入 `relatedPathsByID`，再由 `relatedPaths(for:)`（:166-168）读回。首断言 `XCTAssertNil(viewModel.relatedPaths(for: app))`（:67）落在显式 dry-run 之前，正对应 AC-004「未做该项 dry-run 时不展示关联路径」；随后断言精确等于 dry-run 原文两行，对应「原样展示」。若非 dry-run 前被预填、或解析/字段前缀过滤改动，两断言都会失败。改进方向合理：显式动作让用例不再依赖焦点自动加载的隐式时序，确定性更好。

#### 新发现

### t019_test_f007 - 新增的租约互斥分支无覆盖

- 严重度：minor
- 锚点：`src/zmole/Features/Uninstall/UninstallViewModel.swift:191-201`（`loadRelatedFiles` 的 `session.isBusy`/`isListing` guard 与 `coordinator.acquire` 失败 return）
- 位置：`tests/unit/UninstallDetailTests.swift:58-84`
- 问题：round 3 给 `loadRelatedFiles` 新加了两处早退：忙态 guard（:192）与 `coordinator.acquire` 失败（:198，双击「检查关联文件」或与 preview/execution 争单槽租约时触发）。两条路径都无覆盖：现有两例均在空闲协调器下调用，只会走成功分支。若互斥逻辑回归（例如与批量 preview 并发发起 dry-run），测试不会变红，而单槽桥并发正是本仓核心约束（`OperationCoordinator` single-slot）。属新引入生产分支的覆盖缺口。
- 建议：补一例——先用 `previewUninstall()` 使 `session.isBusy`（或持有租约）后调用 `loadRelatedFiles(for:)`，断言未新增 dry-run 调用且 `relatedPaths(for:)` 仍为 nil；再补一例连续两次 `loadRelatedFiles` 断言第二次因租约占用不重复发起。

#### 残留（round 2 未修项，均为 minor，未变动）

- t019_test_f002（AC-005 合计「不含关联体积」口径未测；`knownSelectedBytes` 仍在 View，未抽出）、t019_test_f003（AC-003 nil→`uninstall.unknown` 映射无断言）、t019_test_f004（related-path 用例仍不断言 dry-run argv 归属）、t019_test_f006（AC-007「不执行」断言仍近恒真）。

#### 门禁复跑

- `xcodebuild test -scheme Zmole -destination 'platform=macOS'` → 145 passed（`UninstallDetailTests` 12 例全绿）。
- `pytest .repo_template/tests -q -m contract` → 147 passed。
- 危险模式扫描：related-path 两例仍只用外部边界替身，无恒真/自指/force-unwrap/`.skip`；新增 `uninstall.files_check` 键在 en/zh-Hans/zh-Hant 均有译文。

#### 结论

- 本轮新发现：1 条（0 critical / 0 important / 1 minor，t019_test_f007）。
- 焦点结论：related-path 测试确认仍触达生产逻辑且有甄别力（首断言覆盖 AC-004 前半、精确路径断言覆盖后半），显式动作化后确定性提升。
- AC 覆盖（复核后）：AC-004 覆盖（语义与显式动作链均有断言）；其余同 round 2——AC-001/002/006 覆盖，AC-003/005 半覆盖，AC-007 覆盖但断言偏弱。
- 红绿灯归属：全部门禁绿灯（145 / 147），无失败测试需归因。
- 总体判断：round 3 的显式动作改动方向正确，related-path 测试有效性确认；新增租约互斥分支缺覆盖记 f007（minor），叠加 round 2 残留三条 minor，均不阻断本轮验收。

reviewed_scope: 5b2d5ab80d5cb213

reviewed_scope: 5b2d5ab80d5cb213

verdict: PASS

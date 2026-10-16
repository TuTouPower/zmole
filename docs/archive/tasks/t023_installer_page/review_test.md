# Task review t023（reviewer_focus: test）

- task: t023_installer_page（安装包页预览后移除）
- spec: `docs/tasks/t023_installer_page/spec.md`
- review_level: full
- diff_anchor: `8c35388de81115ebafabe95b9a5520bab481e3e1`
- target: `git -C '/Users/karson/kar/code/zmole_t023' diff 8c35388de81115ebafabe95b9a5520bab481e3e1`（new files intent-to-add，非 `...HEAD`）
- round: 1
- reviewed_at: 2026-10-16T20:25:00+08:00

## 验证记录

- `xcodebuild test -scheme Zmole -destination 'platform=macOS'` → 168 passed，0 failures。新 `ZmoleTests/InstallersPageTests` 6 例全绿（`-only-testing:ZmoleTests/InstallersPageTests` 复核：`testConfirmRemovalUsesOnlySelectedListedPaths` / `testNewScanInvalidatesSelectionAndConfirmation` / `testNoRemovalBeforeConfirmation` / `testRejectedPathsAreKeptWithReason` / `testScanUsesOnlyNonInteractiveListing` / `testTrashWordingIsPresent`）。
- `pytest .repo_template/tests -q -m contract` → 147 passed，367 deselected。
- 危险模式扫描：测试全部经 `InstallerRunnerSpy`（actor）与注入闭包，无真实下载目录访问、无 `rm`/`FileManager.remove`、无 `sleep`/计时竞态、无网络、无越界写入；唯一文件读取是 `Localizable.xcstrings`（只读）。未见危险模式。
- 红灯光照：anchor `8c35388` 下 `git ls-tree` 只有占位 `InstallersView.swift`，无 `InstallerInterface.swift`（Swift 包装）与 `InstallersViewModel.swift`，测试文件亦不存在 → 6 条用例在 anchor 均因 SUT/测试缺失而红，变更后转绿。

## Findings

### t023_test_f001 - minor - AC-004 后半「再次删除必须重新确认同一次列出结果」无任何断言

- 严重度：minor
- 锚点：`tests/unit/InstallersPageTests.swift:17-30`、`src/zmole/Features/Installers/InstallersViewModel.swift`（`cancelConfirmation`/`confirmRemoval`）
- 问题：`testNoRemovalBeforeConfirmation` 覆盖「取消确认后不删除」这半句（取消后 `removalInvocations` 仍空），但 AC-004 后半「再次删除必须重新确认同一次列出结果」没有任何用例：既无「取消 → 再次 `requestConfirmation` → `confirmRemoval` 成功删除」的正向路径断言，也无「取消后直接调 `confirmRemoval()` 不得删除」的负向锁定。当前保护完全依赖 `confirmRemoval` 里 `guard isConfirmationPresented, canConfirm` 这一实现细节，若日后该守卫被改动（例如取消被实现为只清 UI 标志、保留可确认态），测试不会变红。
- 建议：在 `testNoRemovalBeforeConfirmation` 末尾补 `await viewModel.confirmRemoval()` 后仍断言 `removalInvocations.isEmpty`；另加一条「取消 → 重新 request → confirm」用例断言恰好删除一次且路径集合与首次列出一致。

### t023_test_f002 - minor - AC-002「未列出」分支（扫描前的删除调用）无断言

- 严重度：minor
- 锚点：`tests/unit/InstallersPageTests.swift:17-30`
- 问题：AC-002 为「未列出**或**未确认时，删除调用次数为 0」。现用例先 `scan()` 再选、再取消，只覆盖「未确认」。未测「未列出」——即未 scan（`lastListing` 空）时直接 `requestConfirmation`/`confirmRemoval` 不得产生任何删除调用。当前该行为由 `canConfirm`（`selectedPaths.isSubset(of: Set(lastListing.map(\.path)))`）与 `lastListing` 为空共同保证，但无负向断言锁定；`canConfirm` 的子集守卫本身也没有任何用例触达（选中集始终来自当前 listing，子集恒真），属未被测试覆盖的防御分支。
- 建议：加一条不 scan 的用例，断言 `canConfirm == false`、`requestConfirmation()` 后 `isConfirmationPresented == false`、`confirmRemoval()` 后 `removalInvocations.isEmpty`。

### t023_test_f003 - minor - AC-006 仅校验两个本地化键，未验证界面引用，且用户可见废纸篓文案未全纳入

- 严重度：minor
- 锚点：`tests/unit/InstallersPageTests.swift:86-101`、`src/zmole/Features/Installers/InstallersView.swift:44`（`installers.trash_note`）、`:20-24`（确认框 `installers.confirm_summary`）、`:22`（`installers.confirm_title`）、`:145`（`installers.remove`）
- 问题：`testTrashWordingIsPresent` 直接读源文件 `Localizable.xcstrings`，只断言 `installers.trash_note` 与 `installers.confirm_summary` 的 zh-Hans 含「废纸篓」。这是资源内容断言，不是界面行为断言：(a) 若 `InstallersView` 停止渲染这两个键（例如删掉 `UtilityNotice(title: "installers.trash_note")` 或确认框不再展示 summary），测试仍绿，AC-006「界面写明移入废纸篓」的绿灯不受界面引用约束；(b) 主按钮 `installers.remove`（值「移到废纸篓」）与确认标题 `installers.confirm_title`（「将安装包移到废纸篓？」）这些更直接的可见文案未纳入断言。spec 可测试性声明称 AC-001–006 均由「假 installer 接口自动断言」，而 AC-006 实为资源文件断言，声明与实现不一致（措辞无法经接口断言，属务实妥协，但应显式区分）。
- 建议：把 `installers.remove`、`installers.confirm_title` 加入键列表；若要锁定「界面确实引用」，可对 `InstallersView` 源码/渲染做轻量断言，或至少把 spec 可测试性声明改为「AC-001–005 假接口自动断言；AC-006 资源文案断言」。

## 结论

### AC 覆盖

|AC|用例|判定|
|---|---|---|
|AC-001|`testScanUsesOnlyNonInteractiveListing`（`invocations == [["installer","--list-json"]]`，任何全屏 `installer` 调用都会破坏精确相等）|充分；刷新按钮与 `scan()` 同源|
|AC-002|`testNoRemovalBeforeConfirmation`（确认前、取消后 `removalInvocations` 均空）|部分充分：仅覆盖「未确认」；「未列出」分支缺测（见 f002）|
|AC-003|`testConfirmRemovalUsesOnlySelectedListedPaths`（恰好 2 次 `["installer","--remove",…]`，删除路径集合 == {A,C}，B 不出现）|充分；断言绑定夹具 JSON 路径，非自指|
|AC-004|`testNoRemovalBeforeConfirmation` + `testNewScanInvalidatesSelectionAndConfirmation`（新 scan 清选择、`canConfirm`/`isConfirmationPresented` 复位）|部分充分：取消后不删除已测；「再次删除须重新确认同一次列出结果」缺测（见 f001）|
|AC-005|`testRejectedPathsAreKeptWithReason`（`failures.map(path)==[B]`、`reason=="changed since scan"` 来自注入 stderr、`selectedPaths` 仍留 B、成功的 A 从 `candidates` 移除）|充分；失败原因与保留路径均独立断言|
|AC-006|`testTrashWordingIsPresent`（xcstrings `trash_note`/`confirm_summary` zh-Hans 含「废纸篓」）|弱充分：资源内容断言，不绑定界面引用，键覆盖不全（见 f003）|

- 本轮新发现：3 条（0 critical / 0 important / 3 minor）。
- 红绿灯归属：门禁全绿（168 / 147），无失败测试可归因。新 6 例在 anchor 上因 SUT 与测试缺失全红，变更后全绿；断言非自指——期望值取自手写夹具字符串而非实现输出，删除集合、失败原因、确认世代均为独立信号。
- 未进表提示：spec 范围提及的「多选/全选/清空」与「扫描或删除进行中不可重复提交」不是行为 AC（AC-001–006 之外），`selectAll`/`clearSelection`/`isRemoving` 无测试，不计门禁缺口；`OperationCoordinator` 写入租约在 `confirmRemoval` 中被取得（`.installer`），但占用冲突路径（`acquire` 返回 nil → busy）无用例，属范围外。
- 总体判断：核心破坏性流程（列出 → 选择 → 确认 → 按路径移除 → 失败保留）由假接口断言且具判别力，AC-001/003/005 断言扎实。AC-002/004 的次要分支与 AC-006 的界面绑定存在覆盖缺口，但均为 minor，且均有结构性守卫兜底。测试可信度达标。

verdict: PASS

______________________________________________________________________

## Round 2 (2026-10-16T20:35:00+08:00)

### 复核范围

- 重跑 `git -C '/Users/karson/kar/code/zmole_t023' diff 8c35388de81115ebafabe95b9a5520bab481e3e1`：测试扩到 173 行（+2 用例），`InstallersViewModel` 新增 `confirmationDetail`（`InstallersViewModel.swift:42-47`）与本地化键 `installers.confirm_count_unit`，`InstallersView` 传入 `detail: viewModel.confirmationDetail`（`InstallersView.swift:23`），`DestructiveConfirmationView` 增 `detail` 参数（`DestructiveConfirmation.swift:25`）。
- 门禁：`xcodebuild test -scheme Zmole -destination 'platform=macOS'` → 170 passed，0 failures；`pytest .repo_template/tests -q -m contract` → 147 passed，367 deselected。
- 危险模式扫描：新用例仍只经 `InstallerRunnerSpy`（actor）与注入闭包，无真实路径写入、无删除、无网络、无计时竞态。未见危险模式。

### 处置确认

|finding_id|severity|status|rationale|fix_ref|
|---|---|---|---|---|
|t023_test_f001|minor|已修|新增 `testRemovalRequiresFreshConfirmationAfterCancel`：取消后直接 `confirmRemoval()` → `removalInvocations` 为空；再 `requestConfirmation()` + `confirmRemoval()` → 恰好 1 次删除。直接锁定 AC-004 后半「再次删除必须重新确认同一次列出结果」|tests/unit/InstallersPageTests.swift:112-128|
|t023_test_f002|minor|已修|同一用例直接断言 `confirmRemoval` 的 no-op 早退（`isConfirmationPresented == false`）。该守卫与「未列出」态是同一 `guard isConfirmationPresented, canConfirm`，行为等价；未单设「从未 scan」实例，属边际覆盖，接受|tests/unit/InstallersPageTests.swift:112-121|
|t023_test_f003|minor|撤回|AC-006 措辞由资源键断言（`installers.trash_note`/`installers.confirm_summary` zh-Hans 含「废纸篓」）+ 生产引用检视（`InstallersView.swift:44` 渲染 `trash_note`、`:22` 传 `confirm_summary`）共同确认。GUI 文案无法经假接口断言，资源断言与仓内既有做法（t021）一致；`installers.remove`/`confirm_title` 为附加键，非 AC 必需，不再列为遗留|tests/unit/InstallersPageTests.swift:86-101；src/zmole/Features/Installers/InstallersView.swift:22,44|

### 新增 finding

### t023_test_f004 - minor - confirmationDetail 计数断言 `contains("2")` 过弱，无法区分计数与大小

- 严重度：minor
- 锚点：`tests/unit/InstallersPageTests.swift:104-110`、`src/zmole/Features/Installers/InstallersViewModel.swift:42-47`
- 问题：`confirmationDetail` 由 `"\(count) \(unit) · \(size)"` 拼成。`testConfirmationDetailIncludesSelectedCount` 仅断言整串 `contains("2")`：当前夹具 `selectedBytes == 300`（size 串无 `2`）、unit 无 `2`，唯一来源恰为 count，故此刻非假绿；但断言不能区分「计数=2」与「大小串混入 2」——若实现把 count 写错、而 size/unit 恰好含 `2`，用例仍绿。属「断言过弱」盲区。
- 建议：断言前缀或精确串，如 `XCTAssertTrue(viewModel.confirmationDetail.hasPrefix("2 "))`，或直接断言 `selectedCandidates.count == 2` 与 `confirmationDetail` 的计数段。

### 甄别度复核

- f001 具甄别力：取消后 `selectedPaths` 与 `lastListing` 仍在，`canConfirm` 仍为 `true`，唯一阻止删除的就是 `confirmRemoval` 的 `isConfirmationPresented` 守卫；若删该守卫即会真删，`removals.isEmpty` 必失败。该守卫是承重逻辑，本次用例真正锁定。
- f002 独立：断言不依赖实现内部推导，锁定 `confirmRemoval` 无确认即 no-op 的负向行为。
- f004 独立：从拼接结果取子串，与实现输出同源但不自指（若计数段缺失会失败）；仅断言强度不足，故降为 minor，不影响其他 AC。

### AC 覆盖（Round 2）

|AC|判定|
|---|---|
|AC-001|充分：`invocations == [["installer","--list-json"]]` 精确相等|
|AC-002|充分：确认前 / 取消后 / 无确认直调 `confirmRemoval` 均 0 删除调用|
|AC-003|充分：恰好 2 次 `--remove`，删除路径集合 == {A,C}，B 不出现|
|AC-004|充分：取消后不删除 + 必须重新确认同一次列出结果（新增用例）|
|AC-005|充分：失败路径与原因保留，成功路径从 candidates 移除|
|AC-006|充分：资源键断言 + 生产引用检视|

红灯光照：门禁全绿，无失败测试可归因；新 2 例在缺 `isConfirmationPresented` 守卫 / 缺 `confirmationDetail` 时分别转红，具判别力。

### 结论

- 本轮新发现：1 条（0 critical / 0 important / 1 minor）。
- 处置：f001 已修、f002 已修、f003 撤回；无遗留 critical/important。
- 总体判断：round 1 的 AC-004 覆盖缺口已闭合，AC-001–006 全部充分；新确认计数用例断言偏弱（f004，minor），不影响门禁。测试可信度达标。

reviewed_scope: 8c35388（dirty worktree）

reviewed_scope: 8ecd6bbf180521cc

verdict: PASS

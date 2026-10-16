# Task review t023（reviewer_focus: 代码）

- task：`t023_installer_page`
- spec：`docs/tasks/t023_installer_page/spec.md`
- diff_anchor：`8c35388de81115ebafabe95b9a5520bab481e3e1`
- target：`git -C '/Users/karson/kar/code/zmole_t023' diff 8c35388de81115ebafabe95b9a5520bab481e3e1`
- round：1
- reviewed_at：2026-10-16T20:25:00+08:00

## 方法与证据

- 落点：本会话 shell cwd 为主仓 `/Users/karson/kar/code/zmole`；评审对象为登记 worktree `/Users/karson/kar/code/zmole_t023`，git/文件操作均以 `git -C` 指向该 worktree 的 `t023_installer_page` 分支。
- 阅读范围：全量 diff（`InstallerInterface.swift`、`InstallersViewModel.swift`、`InstallersView.swift`、`AppDependencies.swift`、`AppShellView.swift`、`OperationCoordinator.swift`、`Localizable.xcstrings`、`tests/unit/InstallersPageTests.swift`、`project.pbxproj`）；对照 `installer.sh`（t022 接口）、`OperationCoordinator`/`OperationLease`、`DestructiveConfirmationView`、`UtilityUI.UtilityNotice`，以及视觉权威 `docs/design/mole_desktop_demo_cn_final.html` 的 `renderInstallers`。
- 接口契约核对：`InstallerInterface.list()` → `installer --list-json`；`remove` → `installer --remove <path> --size <bytes> --identity <id>`，与 `installer.sh:966-996` 的解析分支一致；`InstallerCandidate` 的 `size_bytes/source/identity` 与 `installer_list_json`（`installer.sh:872-875`）逐字段对齐。
- 门禁实跑：`xcodebuild test -scheme Zmole -destination 'platform=macOS'` → **168 tests / 0 failures**；`pytest .repo_template/tests -q -m contract` → **147 passed**。
- 单元测试覆盖核对：`InstallersPageTests` 以注入闭包驱动生产 `InstallerInterface`/`InstallersViewModel`，覆盖 AC-001（仅 `--list-json`）、AC-002、AC-003（路径集合）、AC-004（新列出作废旧确认）、AC-005（拒因保留）；`testTrashWordingIsPresent` 直读 `Localizable.xcstrings` 断言 AC-006。
- 符号查询：`WriteOperation` 无 `allCases`/穷举 switch 漏处理；`activeOperation` 无其他消费者；`.task` 仅在 `candidates.isEmpty && !isListing` 时列出，未见全屏 installer 调用。

## Findings

### t023_code_f001 - 确认框未写明选中数量，违反 spec 范围条

- 严重度：important
- 锚点：spec 范围「先扫描列出，再确认。确认框写明选中数量**和**将移入废纸篓」（`spec.md:15`）。
- 位置：`src/zmole/Features/Installers/InstallersView.swift:19-25`；`src/zmole/Resources/Localizable.xcstrings:377-378`（`installers.confirm_title` / `installers.confirm_summary`）。
- 问题：确认态整页替换为 `DestructiveConfirmationView(title: "installers.confirm_title", summary: "installers.confirm_summary")`，两条文案均为静态键。`summary` 中英繁三语只写「选中的安装包将移到废纸篓」，**不含选中数量**；`DestructiveConfirmationView`（`Confirmation/DestructiveConfirmation.swift:22-24`）只接收 `LocalizedStringKey` 的 title/summary，实现侧也未传插值/计数。主页面 `statStrip` 的「已选择」计数在确认态被整页替换而不可见，故确认框内确实无数量信息。spec 明确把「数量 + 废纸篓」一并挂在确认框上，此条未满足；现有单测（AC-006 只断言 `trash_note` 与 `confirm_summary` 含「废纸篓」）亦未覆盖数量，故门禁未拦。
- 建议：确认框文案加数量，例如新增带占位符的键 `installers.confirm_summary_count`（`…%lld 个…`）并以选中数插值，或给 `DestructiveConfirmationView` 增加可选计数参数；同步补一条断言确认文案含选中数的测试。

### t023_code_f002 - 扫描进行中可提交移除：`requestConfirmation` 缺 `isListing` 守卫、Remove 按钮未按 `isListing` 禁用

- 严重度：minor
- 锚点：spec 范围「扫描或删除进行中不可重复提交」（`spec.md:16`）；风险「列表刷新后仍用旧路径删除」（`spec.md:74-75`）。
- 位置：`src/zmole/Features/Installers/InstallersViewModel.swift:78-81`（`requestConfirmation`）、`InstallersViewModel.swift:42-57`（`scan` 在**完成后**才清空 `selectedPaths`/`lastListing`）；`InstallersView.swift:130-139`（底部移除条在 `isListing` 时仍渲染，按钮 `.disabled(!canConfirm || isRemoving)`）。
- 问题：重扫时 `scan()` 先置 `isListing=true` 并 `await`，此期间不清空旧 `selectedPaths`/`lastListing`，`canConfirm` 仍为真。`isListing` 分支只把列表区换成 `ProgressView`，但底部 `if !viewModel.candidates.isEmpty` 的移除条依旧显示且按钮可用；`requestConfirmation()` 只判 `canConfirm`，无 `!isListing` 守卫，`toggleSelection/selectAll/clearSelection` 均有该守卫，唯此处遗漏。于是「先选择 → 点刷新 → 扫描未回时点移除 → 确认」可在扫描在途时以**上一份列出结果**发起删除，构成与 `scan()` 的并发提交，触碰「扫描中不可提交」与「新列出使旧确认失效」的边界（用户点击足够快时才会命中，故定 minor）。
- 建议：`requestConfirmation` 增加 `guard !isListing, !isRemoving`；底部 Remove 按钮禁用条件补 `|| viewModel.isListing`；或在 `scan()` 起始即清空选择/确认，使旧确认在扫描一开始就失效。

### t023_code_f003 - 写入租约被占时把原始本地化键当正文展示，且标题误导

- 严重度：minor
- 锚点：租约冲突的用户可见反馈（`spec.md:80` 单一写入租约）。
- 位置：`src/zmole/Features/Installers/InstallersViewModel.swift:91-94`；`src/zmole/Features/Installers/InstallersView.swift:44-46`；`UtilityUI.swift:89-94`。
- 问题：`coordinator.acquire(.installer)` 失败时 `errorMessage = "operation.error.busy"`。视图以 `UtilityNotice(title: "installers.error_title", detail: errorMessage, isError: true)` 呈现，而 `UtilityNotice.detail` 是 `String?` 且以 `Text(verbatim:)` 渲染，不做本地化——用户会照字面看到 `operation.error.busy`。同时 `installers.error_title` = 「安装包扫描失败」，与租约冲突语义不符。仓库既有做法是把该类键经 `LocalizedStringKey` 呈现（`OptimizeView.swift:79`、`PurgeView.swift:81`、`WhitelistViewModel.swift:89`），此处偏离。
- 建议：区分错误键与错误描述，例如新增 `errorMessageKey: String?` 并以 `LocalizedStringKey(errorMessageKey)` 作为标题呈现，或直接对 `operation.error.busy` 用 `String(localized:)` 求值后放入 detail；同时避免用「扫描失败」标题承载租约冲突。

### t023_code_f004 - 占位视图移除后遗留 `installers.placeholder` 文案键

- 严重度：minor
- 锚点：本 task 改动引入的失效资源。
- 位置：`src/zmole/Resources/Localizable.xcstrings:248`。
- 问题：旧 `InstallersView` 占位文案（「安装包扫描与移除将在后续任务接入」）已随本 task 重写删除，`installers.placeholder` 全仓（源码 + 测试）已无引用，成为新增的死文案键。
- 建议：删除该键（三语条目），保持文案表与实际引用一致。

## 结论

- 前轮 finding 复核：Round 1，无。
- 本轮新发现：4 条（important 1：f001；minor 3：f002、f003、f004）。
- 未进表的提示：
    - 视觉与 `renderInstallers` 存在差异（`statStrip` 用「找到/已选择/已选大小/移除位置」替代设计的「找到/文件/最早下载/移除位置」；页面头部无设计中的 `移除 {size}` 主操作，主操作只落到底部移除条）。属设计还原/copy 范畴，交由 general/视觉评审判定，不入代码 finding 表。
    - 通过项：AC-001–AC-006 均有对应单测且门禁 168/147 全绿；`InstallerInterface` argv 与 `installer.sh` 契约一致；删除仅走 `coordinator.acquire(.installer)` 单一租约并 `release`；`scan()` 成功/失败两路都清空选择与确认（AC-004）；失败路径保留在 `candidates` 与 `failures`（AC-005）；`InstallerCandidate` 解码字段与 CLI 产出对齐；无全屏 installer 调用。
- 总体判断：核心安全不变量（只删选中且属本次列出的路径、新列出作废旧确认、失败保留、单写入租约、废纸篓文案、不调全屏菜单）经实现与单测核对成立，门禁全绿。但 f001 是 spec 范围明列的确认框必写项（选中数量），实现与测试均缺失，属未解决的 important，不能判 PASS。f002/f003/f004 为 minor，建议本轮一并修复。

verdict: FAIL

______________________________________________________________________

### Round 2 (2026-10-16T20:27:43+08:00)

- 复核对象：`git -C '/Users/karson/kar/code/zmole_t023' diff 8c35388de81115ebafabe95b9a5520bab481e3e1`（相对 Round 1 增量：`DestructiveConfirmation.swift` 新增 `detail`；`InstallersViewModel` 的 `canConfirm`/`confirmationDetail`/busy 文案；`InstallersView` 传 `detail`；`Localizable.xcstrings` 新增 `installers.confirm_count_unit`；`InstallersPageTests` 新增 2 例）。
- 门禁实跑：`xcodebuild test -scheme Zmole -destination 'platform=macOS'` → **170 tests / 0 failures**；`pytest .repo_template/tests -q -m contract` → **147 passed**。

#### 前轮 finding 处置

|finding_id|severity|status|rationale|fix_ref|
|---|---|---|---|---|
|t023_code_f001|important|已修|`DestructiveConfirmationView` 增可选 `detail: String?`（默认 nil，其余调用点不受影响）；`InstallersViewModel.confirmationDetail` 返回「`<count> <unit> · <size>`」，`InstallersView` 以 `detail: viewModel.confirmationDetail` 传入；新增键 `installers.confirm_count_unit`；新测 `testConfirmationDetailIncludesSelectedCount` 断言含选中数「2」|`InstallersViewModel.swift:47-52`、`InstallersView.swift:23`、`DestructiveConfirmation.swift:25/35-38`、`Localizable.xcstrings`|
|t023_code_f002|minor|已修|`canConfirm` 追加 `!isListing && !isRemoving`；`requestConfirmation` 与底部 Remove 按钮禁用条件均经 `canConfirm`，扫描在途时两者同时失效，不再以旧列出发起移除|`InstallersViewModel.swift:40-44`、`InstallersView.swift:138`|
|t023_code_f003|minor|已修（含残留提示）|busy 分支改为 `errorMessage = String(localized: "operation.error.busy")`，`Text(verbatim:)` 展示的是本地化文案而非原始键；不再泄漏 `operation.error.busy`。残留：标题仍复用 `installers.error_title`（「安装包扫描失败」），承载租约冲突语义略偏，属 minor 文案提示，不入表|`InstallersViewModel.swift:91-95`|
|t023_code_f004|minor|未修（接受）|`installers.placeholder` 死文案键保留。该键已无任何源码/测试引用，属资源清理 nit，非功能缺陷；随 spec 明列项均已闭环，接受其残留|`Localizable.xcstrings:248`|

#### 回归扫描

- 共享组件改动向后兼容：`detail` 带默认值且置于 `summary` 与 `onConfirm` 之间，其余四处调用点（Clean/Optimize/Purge/Uninstall）继续以 `title:summary:onConfirm:onCancel:` 调用，编译通过、170 测试全绿。
- `canConfirm` 收紧无双向影响：仅在确认入口（`requestConfirmation`/`confirmRemoval`/按钮禁用）消费；`confirmRemoval` 的守卫在置 `isRemoving=true` 之前求值，仍为真，删除路径未受影响。
- 安全不变量复核（沿用 Round 1）：仍只删「选中且属本次列出」路径（`selectedCandidates` 走 `lastListing`）；新列出清空选择并作废旧确认；失败路径保留于 `candidates` 与 `failures`；单 `.installer` 写入租约 acquire/release 成对；`--list-json`/`--remove` argv 与 `installer.sh` 契约一致；无全屏 installer 调用。
- 未发现新 finding，未见 Round 1 已判定通过项回归。

#### 结论（Round 2）

- 前轮 finding 复核：f001/f002 已修并经门禁与新测验证；f003 主项（原始键泄漏）已修，仅余标题语义的 minor 提示；f004 为有意保留的资源清理 nit。
- 本轮新发现：0 条。
- 总体判断：Round 1 唯一的 important（确认框未写选中数量）已消除，剩余仅为 minor/nit 残留；spec 范围内全部要求与 AC-001–AC-006 均成立，门禁 170/147 全绿，无未解决 critical/important。

reviewed_scope: b57016c
reviewed_scope: 8ecd6bbf180521cc

verdict: PASS

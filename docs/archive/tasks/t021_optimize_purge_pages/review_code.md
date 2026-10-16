# Code Review — t021 优化页与项目清理页

- reviewer: code
- review_level: full
- diff_anchor: `e0a077092a195a016ba55ee18facf378244d6272`
- target: `git -C /Users/karson/kar/code/zmole_t021 diff e0a0770`（含未跟踪新文件）
- 范围：仅 diff 触及路径

## 审查范围

新增 `OptimizePlan.swift`、`PurgePaths.swift`、`PurgePathsEditorView.swift`；重写 `OptimizeView` / `PurgeView`；`AppDependencies` 增 `purgePathsViewModel`；`AppShellView` 接线；`tests/unit/OptimizePurgePageTests.swift`；`Localizable.xcstrings`、blueprint / ui_contract / task.md front matter 同步。`MaintenanceOperation` 的 preview/execute argv 未改。

为核实 AC-002，实跑捆绑 CLI（只读 dry-run）：

```
./src/zmole/Resources/mole/bin/optimize.sh --dry-run
```

## AC 对照

|AC|结论|证据|
|---|---|---|
|AC-001|满足|`MaintenanceKind.executionArguments` = `["optimize"]`；`OptimizePurgePageTests.testOptimizeArgsNeverIncludeSelectedTaskSubset` 断言 `[["optimize","--dry-run"],["optimize"]]`|
|AC-002|**不满足**|见 f001：真实 dry-run 下全部行被判为「将执行」，跳过状态丢失|
|AC-003|满足|`OptimizeView:58` 常驻永久删除说明 + `OptimizePlan.swift:38` 行级标记；`optimize.permanent_note` 文案|
|AC-004|满足|`["purge","--yes"]`；`testPurgeUsesYesAndCancelDoesNotExecute`|
|AC-005|满足|`cancelConfirmation` 后 `invocations` 仅 `[["purge","--dry-run"]]`|
|AC-006|部分|存取与非法保留有测试；但生产路径从不加载现有内容，见 f002|
|AC-007|满足|`optimize.permanent_note` / `purge.permanent_note` 均写「永久删除」；`testPermanentDeletionCopyUsesPermanentWording`|

## Findings

### t021_code_f001

- severity: important
- location: `src/zmole/Features/Optimize/OptimizePlan.swift:36`、`src/zmole/Features/Optimize/OptimizeView.swift:8`、`tests/unit/OptimizePurgePageTests.swift:39`
- 现象：跳过判定只看分隔符之后的 `detail` 里是否含 `skip` / `unavailable` / `reason`。mole 真实输出把跳过措辞写在任务名同一行、且无 `: ` / `-` / `—` 分隔，导致 `detail` 为空 → 判为 `willRun`。

实跑真实输出并用同算法复算，`optimize --dry-run` 产生 55 行、**0 行跳过**，其中：

- `→ Periodic maintenance skipped (not available on this macOS version)` → `willRun`
- `→ Disk verify skipped (set MOLE_ENABLE_DISK_VERIFY=1 to enable)` → `willRun`
- `◎ Close these apps before database optimization: Mail`（Database Optimization 因 Mail 占用被跳过）→ `willRun`
- 非任务行也成行：`Optimize`、`→ DRY RUN MODE...`、`⚙ System  35/64 GB RAM | ...`、`PERFORMANCE DIAGNOSIS`、`Dry Run Complete, No Changes Made`、`Would apply 4 optimizations`、`14 unchanged | 2 skipped | 1 unavailable`、`Run without --dry-run...`

行名还残留 CLI 图标（`→`/`➤`/`✓`/`◎`/`⚙`）。违反 spec「优化页列出 mole 的真实任务」「状态文本来自本次 dry-run：会执行、跳过、原因」与 AC-002 的状态语义。测试通过只因所用绿色夹具把原因放在 `: ` 之后，与真实格式不符（测试夹具已脱离生产契约）。

- 建议：以真实行前缀（`➤`=任务、`→`/`◎`/`✓`）切分任务与其明细行，跳过判定对整行（含 `skipped` / `unavailable` / `reason` / `Close these apps before`）扫描；或让夹具取自真实 dry-run 输出，避免再次偏离。

### t021_code_f002

- severity: important
- location: `src/zmole/Features/Purge/PurgePathsEditorView.swift:7`、`src/zmole/Features/Purge/PurgePaths.swift:76`
- 现象：`PurgePathsEditorView` 无 `.task` / `.onAppear` 调 `viewModel.load()`；全仓（`src/`）无任何对 `purgePathsViewModel` 的 `load()` 调用。`PurgePathsViewModel` 是 app 级单例，`text` 初值 `""`，因此从项目清理页打开「编辑扫描目录」时编辑器为空，未展示 `~/.config/mole/purge_paths` 现有内容。

后果：用户直接点「保存」会把现有配置清成只剩注释头（`PurgePathsStore.save` 写 header + 空 paths），即静默覆盖。对照 `WhitelistView.swift:114` 的既有模式（`.task` 中 `load()`），此处漏掉加载。AC-006 仅由测试内手工调用 `load()` 覆盖，生产路径未被验证。

- 建议：在 `PurgePathsEditorView` 加 `.task { viewModel.load() }`（或在打开 sheet 时加载），并加一条覆盖「打开即显示现有内容」的测试。

### t021_code_f003

- severity: important
- location: `src/zmole/Features/Purge/PurgePaths.swift:70`、`src/zmole/Features/Purge/PurgePaths.swift:88`
- 现象：`PurgePathsViewModel` 不接 `OperationCoordinator`，`save()` 不获取写入租约、也不在成功后 `invalidatePreviews()`。spec「依赖与约束」明确「与清理、卸载、安装包、白名单保存共用单一写入租约」；`WhitelistViewModel.save`（`WhitelistViewModel.swift:87`、`:100`）正是 acquire `.protectionRules` + `coordinator.invalidatePreviews()`。

后果：扫描目录变更后旧 purge 预览不失效。`purge --yes` 由 mole 按新配置重新认定范围，而界面仍展示旧 dry-run 的项、且 `canConfirm` 仍为真，用户据旧预览确认、实际执行集合可能不同——与白名单保存失效清理预览的同款安全语义缺失。

- 建议：给 `PurgePathsViewModel` 注入 `coordinator`，`save()` 成功走租约并 `invalidatePreviews()`。

### t021_code_f004

- severity: minor
- location: `src/zmole/Features/Purge/PurgePaths.swift:46`、`src/zmole/Features/Purge/PurgePaths.swift:92`
- 现象：`purge.paths.hint` 文案写「注释以 # 开头」，但 `save()` 过滤掉 `#` 行，`load()` 也丢弃，用户所写注释在保存后静默消失。行为与提示不一致。
- 建议：或在提示中说明注释不被保留，或保留原注释行。

### t021_code_f005

- severity: minor
- location: `src/zmole/Features/Purge/PurgePaths.swift:64`、`src/zmole/Features/Purge/PurgePaths.swift:76`、`src/zmole/Features/Purge/PurgePathsEditorView.swift:23`
- 现象：`didSave` 只在 `save()` 内更新，重新打开编辑器或再次编辑时不重置，`purge.paths.saved` 会持续显示；`load()` 也只在成功时清 `errorKey`，旧错误可能滞留。
- 建议：`load()` 与文本变更时重置 `didSave` / `errorKey`。

## 结论

- AC-001/003/004/005/007 满足；AC-006 存取逻辑正确但生产加载路径缺失。
- AC-002 不满足：真实 dry-run 输出下解析器把跳过任务与大量非任务行统一标成「将执行」，跳过状态与原因未落在对应任务行；单测夹具与真实 CLI 格式脱节，掩盖了该缺陷。
- 另有项目清理编辑器不加载现有配置（可能覆盖用户配置）、保存不参与写入租约/不失效预览两处重要问题。

未解决 important 3 项，按 task 规则不得 PASS。

verdict: FAIL

______________________________________________________________________

### Round 2 (2026-10-16T19:53:24+08:00)

diff 重跑范围：`git -C /Users/karson/kar/code/zmole_t021 diff e0a0770`（`OptimizePlan.swift` 78 行、`PurgePaths.swift` +116、`PurgePathsEditorView.swift` +36、`OptimizePurgePageTests.swift` +171；`AppDependencies` 传入 coordinator）。

#### 处置

|finding_id|severity|status|rationale|fix_ref|
|---|---|---|---|---|
|t021_code_f001|important|部分修复|按 `➤` 段落 + 缩进明细重写，非任务行（`Optimize`/`DRY RUN`/`System`/summary）不再成行，样例多数跳过行正确；残留两处漏判 → 见 f006|`OptimizePlan.swift:29-77`|
|t021_code_f002|important|已修|编辑器出现即加载现有内容|`PurgePathsEditorView.swift:34`|
|t021_code_f003|important|已修|`PurgePathsViewModel` 注入 coordinator；`save()` 取 `.purge` 租约并在 `defer` 中 `invalidatePreviews()`；新增断言旧预览失效的单测|`PurgePaths.swift:69-104`、`OptimizePurgePageTests.swift:102-120`|
|t021_code_f004|minor|遗留|注释行仍在保存时被过滤，hint 仍称支持注释|`PurgePaths.swift:95`|
|t021_code_f005|minor|遗留|`load()` 仍不重置 `didSave`（重开编辑器继续显示「已保存」）|`PurgePaths.swift:78-85`|

复核 f002/f003：`PurgePathsEditorView` 生产路径已加载；`testSavingScanDirectoriesInvalidatesPurgePreview` 复现「保存扫描目录后 purge 预览失效、`canConfirm` 转假」，与 `WhitelistViewModel.save` 的 `invalidatePreviews` 语义一致。二者修复确认。

#### Round 2 findings

### t021_code_f006

- severity: important
- location: `src/zmole/Features/Optimize/OptimizePlan.swift:21-24`、`src/zmole/Features/Optimize/OptimizePlan.swift:69`、`src/zmole/Features/Optimize/OptimizeView.swift:140-143`
- 现象：`noOpMarkers` 用固定措辞表判非执行，仍漏当前 mole 源码的两类真实行：
    1. `tasks.sh:572` `◎ Close these apps before database optimization: <apps>`（随后 `optimize_task_result SKIPPED`）不含任何 marker → `Database Optimization` 判为 `willRun`、`reason` 置 nil。`rowView` 对 `willRun` 只渲染 `name`，明细被丢弃，故该跳过原因**不出现在对应任务行**。
    2. `tasks.sh:1485`/`1592` `... database is healthy (...)`（unchanged）不匹配 `all healthy` → `Notifications` / `Usage Data` 判 `willRun`；而 `Launch Agents all healthy` 判 `skip`，同为 no-op 却分类相反。
- 证据：用同算法复算 `docs/spikes/s001_mole_cli_fixtures/samples/optimize_dry_run.txt`，`Database Optimization` = `willRun`/reason nil；复算本机实跑 `optimize --dry-run` 输出，`Database Optimization`、`Notifications`、`Usage Data` 均 `willRun`。
- 影响：AC-002 第一分句「跳过原因出现在对应任务行」对 `Database Optimization` 仍不成立；样例第 30 行即含该行，但新增测试只断言 `Periodic Maintenance`，恰好避开了失败用例。
- 建议：把「close these apps before」「is healthy」纳入非执行判定（或改按 mole 结果词 `skipped`/`unavailable`/`unchanged` 归类），并让样例测试覆盖 `Database Optimization`。

### t021_code_f007

- severity: minor
- location: `tests/unit/OptimizePurgePageTests.swift:42-47`
- 现象：测试硬编码 `docs/spikes/s001_mole_cli_fixtures/samples/optimize_dry_run.txt`。按 AGENTS.md 流程 spike 完结由 repo-hygiene 迁 `docs/archive/spikes/`，该路径将失效导致单测失败；且该样例是 spike 期 HEAD 快照，措辞已与当前 `tasks.sh` 不一致（样例 `unavailable`/`not found`，现源码 `is healthy`），夹具会持续腐化。
- 建议：把稳定样例移入 `tests/`（或不过期的固定位置），并与当前源码措辞对齐。

#### Round 2 结论

- f002、f003 确认修复；f001 主体修复但残留 f006；f004、f005 仍为 minor 开放。
- f006 使 AC-002 仍未完全满足，属 important 未解决。
- 未发现回归（`.purge` 租约失败路径亦 `invalidatePreviews`，与既有白名单模式一致，不计为回归）。

verdict: FAIL

______________________________________________________________________

### Round 3 (2026-10-16T19:55:30+08:00)

diff 重跑范围：`git -C /Users/karson/kar/code/zmole_t021 diff e0a0770`（`OptimizePlan.swift:21-25` 增 marker，`PurgePaths.swift:78-79` load 重置 `didSave`，`OptimizePurgePageTests.swift` 增 `testOptimizePlanRecognizesCurrentSkipWording`）。

#### 处置

|finding_id|severity|status|rationale|fix_ref|
|---|---|---|---|---|
|t021_code_f001|important|已修|f006 补齐措辞后，真实输出 21 个任务全部归类正确|`OptimizePlan.swift:21-25`|
|t021_code_f002|important|已修|（Round 2 确认）|`PurgePathsEditorView.swift:34`|
|t021_code_f003|important|已修|（Round 2 确认）|`PurgePaths.swift:97-105`|
|t021_code_f004|minor|遗留|注释行仍在保存时被过滤，hint 仍称支持注释；未处理，属 minor|`PurgePaths.swift:96`|
|t021_code_f005|minor|已修|`load()` 开头置 `didSave = false`，重开编辑器不再残留「已保存」|`PurgePaths.swift:79`|
|t021_code_f006|important|已修|`noOpMarkers` 增 `is healthy`、`close these apps before`|`OptimizePlan.swift:21-25`|
|t021_code_f007|minor|遗留（用户接受）|硬编码 spike 路径暂不处理|`OptimizePurgePageTests.swift:42-47`|

f006 复核：用现算法复算 spike 样例与本机实跑 `optimize --dry-run`，`Database Optimization` = `skip`（reason `Close these apps before database optimization: Mail`）、`Notifications`/`Usage Data` = `skip`（reason 含 `is healthy`），其余 6 行 `willRun` 均为确有动作的任务（DNS flushed、QuickLook refreshed、saved states optimized 等）。AC-002 的两个漏判场景已消除。新增单测 `testOptimizePlanRecognizesCurrentSkipWording` 直接覆盖该措辞。

f005 复核：`load()` 首行 `didSave = false`，重开编辑器不再显示上一次的「已保存」。

#### Round 3 findings

无新增 finding（new finding count: 0）。

回归扫描：

- 新增 marker `is healthy` / `close these apps before` 为子串匹配；逐行复核两份真实输出，未出现把确有动作任务误判为跳过（6 个 `willRun` 与 mole 摘要「Would apply 4 optimizations」的语义方向一致）。
- `load()` 提前重置 `didSave` 不影响 `save()` 的租约/失效逻辑；`testSavingScanDirectoriesInvalidatesPurgePreview` 仍成立。
- 其余 diff 路径（`OptimizeView` / `PurgeView` / `AppDependencies` / `AppShellView` / xcstrings）自 Round 2 未变动。

#### Round 3 结论

- f001、f002、f003、f005、f006 确认修复；f007 用户接受；仅 f004（注释行）为开放 minor。
- 无 critical/important 未解决，AC-001–AC-007 满足。

reviewed_scope: 89a2686a8650fc3e

verdict: PASS

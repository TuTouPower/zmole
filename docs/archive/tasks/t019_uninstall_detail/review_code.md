# Task review t019（reviewer_focus: code）

- task: t019 卸载列表详情与多选
- branch: t019_uninstall_detail
- diff_anchor: 88be325cacc5c76cdc0a7c76bfea2436df35953b
- 审查范围: diff 触及路径（新增 `UninstallMetadata.swift`、`UninstallDetailTests.swift`；改写 `UninstallView.swift`、`UninstallViewModel.swift`；`Localizable.xcstrings`、`project.pbxproj`、ui_contract、task.md）
- 门禁复核: `xcodebuild test -scheme Zmole -destination 'platform=macOS'` → 142 passed（本地实跑）；`pytest -m contract`（需在 `.repo_template/` 下执行）→ 147 passed（本地实跑）
- 已核对: 新引用本地化键全部存在；pbxproj 新文件加入正确 target；AC-002/003/004/006/007 的 VM 级断言通过

## Findings

### t019_code_f001 卸载确认 UI 缺失，批量移入废纸篓在界面不可达（High）

`UninstallView` 重写后仍未渲染 `DestructiveConfirmationView`（Clean/Purge/Optimize 三处均有）。`uninstall.execute` 只调用 `viewModel.requestConfirmation()`（`UninstallView.swift:334`），而全仓没有任何视图调用 `confirmExecution()`（仅 Clean/Purge/Optimize 调用），状态进入 `.confirming` 后无出路：再次点 execute 时 `beginConfirmation()` 只接受 `.ready` 返回 false，界面卡死。

- 详情页新增的“移到废纸篓”按钮（`UninstallView.swift:250` 起）最终同样走到这条死路。
- 违反 spec 范围「确认框绑定这次选中的 path 与 bundle id」；AC-002/AC-007 以确认框存在为前提，用户端不可验证。
- 成因说明：该回退始于 `15f769c`（非本 diff 引入），但本 task 明确要求「保留多选与批量移入废纸篓」，交付未达成，本地化键 `uninstall.confirm_title` / `uninstall.confirm_summary` 仍在库中闲置即为佐证。

建议：按 Clean 的模式在 `UninstallView` 顶层加 `if viewModel.isConfirmationPresented { DestructiveConfirmationView(... onConfirm: confirmExecution, onCancel: cancelConfirmation) }`。

### t019_code_f002 详情 dry-run 与共享进程/列表竞争，失败被吞成“无关联文件”（Medium）

`loadRelatedFiles`（`UninstallViewModel.swift:191`）先 `relatedLoadedIDs.insert(app.id)`，再用 `try?` 调 `process.run`；任何错误（含 `MoleBridge.busy`、非 0 退出）都落到 `relatedPathsByID[app.id] = []`，且该 id 已永久标记为已加载，UI 显示「本次 dry-run 没有关联文件」，把“未跑/失败”误报成“空”。

命令桥是全局单槽（`MoleBridge.activeRunner`；`AppDependencies` 中 `process = commandBridge` 被 clean/uninstall/optimize/purge 及 overview/history 装载器共用）。详情 dry-run 未取 coordinator lease，也不检查在飞操作，因此：

- 快速连点两行 → 第二次 dry-run 命中 `busy` → 该 app 永久显示“无关联文件”；
- dry-run 进行中点刷新 → `loadList()`（`UninstallViewModel.swift:75`）只查 `session.isBusy`，不查在飞的详情 dry-run → `uninstall --list` 命中 `busy` → `listSession.fail`，`apps=[]`、`hasLoaded=false`，整个列表被清空并显示错误。

建议：把详情 dry-run 纳入 coordinator/lease 协调，并区分“失败”与“空”（失败回退为 not_loaded 或可重试），不要用 `[]` 覆盖。

### t019_code_f003 全量元数据读取在主线程同步跑 Spotlight（Low）

`loadAllMetadata()`（`UninstallViewModel.swift:184`）在 `loadList` 后对每个 app 执行 `Bundle(url:)` + 同步 `NSMetadataItem`（Spotlight 查询），且运行在 MainActor 上；应用数较多时阻塞 UI。另 VM 默认注入 `LiveUninstallMetadataProvider()`，使既有 `UninstallTests` 在 loadList 后真实触碰文件系统/Spotlight（后台 Task，测试异步收尾）。建议移出主 actor 或改为惰性/限流。

### t019_code_f004 AC-005：不可解析 size 未显示未知（Low）

行与详情都直接贴原始 `app.size`（`UninstallView.swift:205`、`254`）。`UninstallSizeParser` 明确把 `"0"` 视为不可解析（返回 nil），因此 mole 返回 `"0"` 时界面会显示 `0`，与「size 不能解析时显示未知，不显示 0」冲突。建议 `sizeBytes == nil` 时统一走 `uninstall.size_unknown`。

### t019_code_f005 关联路径解析属未核实契约（Low）

`relatedPaths(from:)`（`UninstallViewModel.swift:209`）只保留以 `/` 或 `~/` 开头的行并做 trim。s001 未采集 `uninstall --dry-run` 输出样例，spec「未知契约清单」写“无”；若真实输出带前缀/项目符号，路径会被静默丢弃，且 trim 也非严格“原样展示”。建议补一份 dry-run fixture 固化契约（AC-004 的“原样”依赖此格式）。

### t019_code_f006 AC-001 搜索保留与 AC-005 文案缺少直接断言（Low）

`testFocusAndSelectionAreIndependentOfEachOther` 覆盖焦点/选择独立，但「搜索过滤后已选 path 仍保留」无自动断言（search 是 View 私有 `@State`，仅靠“过滤不动 VM 状态”间接成立）。AC-005 的合计文案测试只读 xcstrings 文本，未断言 shelf 实际渲染（含“任一 size 未知时隐藏合计”这一分支）。可接受，但覆盖有缺口。

### t019_code_f007 本地化键被本 diff 变孤儿（Low）

改用 `sidebar.uninstall` 后，`software.uninstall` 成为死键；移除行内展开与来源展示后 `uninstall.details`、`uninstall.source_unknown` 亦不再被引用（`uninstall.confirm_title/summary` 更早已闲置）。建议随本任务清理，避免 xcstrings 残留。

## 结论

门禁全绿（142 / 147），AC-002/003/004/006/007 的注入式 VM 断言均通过，列表/详情/多选结构基本符合 spec。但 f001 使「批量移入废纸篓」在界面不可达，直接违背 spec 范围与 AC-002/AC-007，属阻断；f002 为本次新增代码引入的并发/误报问题，需修。建议修复 f001、f002 后复审，其余为 Low 级改进。

verdict: FAIL

### Round 2 (2026-10-16T19:22:00+08:00)

- diff 复核：`UninstallView` 顶层加 `Group`/`DestructiveConfirmationView`；`UninstallViewModel.loadRelatedFiles` 改为仅在成功 dry-run 时标记已加载；`LiveUninstallMetadataProvider` 包 `Task.detached`；新增 `UninstallApp.sizeText` 与 `UninstallListFilter.visible`，行/详情改用 `sizeText`。
- 门禁实跑：`xcodebuild test -scheme Zmole -destination 'platform=macOS'` → 145 passed；`pytest -m contract`（在 `.repo_template/` 下）→ 147 passed。

#### 处置确认

- t019_code_f001 FIXED。`UninstallView`（body）在 `isConfirmationPresented` 时渲染 `DestructiveConfirmationView`，`onConfirm` 调 `confirmExecution()`、`onCancel` 调 `cancelConfirmation()`，与 `CleanView` 一致；确认框不再缺失，AC-002/AC-007 的用户路径打通。
- t019_code_f002 PARTIAL。成功才 `relatedLoadedIDs.insert` + 落盘（失败直接 return，不再污染 `relatedPathsByID`），“临时 busy 被吞成永久无关联文件”已修；`testRelatedPathsEmptyWhenDryRunHasNoPaths` 仍区分“空”与“未加载”。但根因——详情 dry-run 未纳入进程/协调，仍与共享单槽 `MoleBridge` 竞争——未解，见 f008。
- t019_code_f003 FIXED（主线程部分）。`Task.detached(priority: .utility)` 把 Bundle/Spotlight 移出 MainActor。遗留（非阻塞）：既有 `UninstallTests` 仍用默认 `LiveUninstallMetadataProvider`，测试期仍会真实触碰文件系统/Spotlight，建议测试注入 Fake 或在 finalization 处理。
- t019_code_f004 FIXED。新增 `UninstallApp.sizeText`（`sizeBytes == nil` 返回 nil），行与详情改 `sizeText ?? unknown`；`testZeroSizeStringIsUnknown` 断言 `"0"` → nil。
- t019_code_f005 OPEN。`relatedPaths(from:)` 仍只收 `/` 或 `~/` 开头的行，s001 无 dry-run 样例，属未核实契约。Low，保留。
- t019_code_f006 PARTIAL。新增 `testSearchFilterHidesRowButKeepsSelection` 覆盖 AC-001 搜索保留；AC-005 合计文案仍只断言 xcstrings 文本，未断言 shelf 渲染（含“任一 size 未知则隐藏合计”分支）。Low，保留。
- t019_code_f007 OPEN。`software.uninstall`、`uninstall.source_unknown`、`uninstall.details` 仍为死键（`uninstall.confirm_title/summary` 现已重新启用）。Low，保留。

#### 新发现

### t019_code_f008 详情 dry-run 仍与列表/预览竞争共享进程（Medium）

`loadRelatedFiles` 现在失败不落盘（好），但仍在 coordinator/lease 之外直接调 `process.run`；命令桥是全局单槽（`MoleBridge.activeRunner`，`AppDependencies` 中 `process = commandBridge` 被 clean/uninstall/optimize/purge 与各装载器共用）。mole dry-run 约 33s（s001），窗口很宽：

- 详情 dry-run 在飞时点工具栏刷新 → `loadList()`（`UninstallViewModel.swift:75`）只查 `session.isBusy`，不查在飞的详情 dry-run → `uninstall --list` 命中 `MoleBridge.busy` → `listSession.fail`，`apps=[]`、`hasLoaded=false`，列表被清空并显示错误；
- 同窗口点预览 → `previewUninstall()` 同样穿透守卫 → `uninstall --dry-run` 命中 busy → 预览失败。

建议：详情 dry-run 取 coordinator lease（或在 VM 内记录“在飞详情 dry-run”并纳入 `loadList`/`previewUninstall` 的守卫），与全应用共享单进程槽的既有约定对齐。此项为 f002 未修的根因，非回归。

#### 结论

round 1 的阻断项 f001 已修（确认框落地，批量移入废纸篓在界面可达），f002/f003/f004 主体已修，AC-001–007 的注入式断言均通过，门禁 145/147 全绿。遗留 f005/f006/f007 为 Low；f002 的根因残留为新 f008（Medium，非回归），不影响本轮 spec 达成，建议独立修复或转入 pending。

verdict: PASS

### Round 3 (2026-10-16T19:27:00+08:00)

- diff 复核：`loadDetail(for:)` 不再触发 dry-run（仅加载元数据）；新增公开 `loadRelatedFiles(for:)`，取 `.uninstall` coordinator lease（`defer` 释放）、守卫 `!relatedLoadedIDs.contains && !session.isBusy && !isListing`、仅成功落盘；详情面板在 `relatedPaths == nil` 时展示 `uninstall.files_check` 按钮（「检查关联文件」）触发。新增本地化键 `uninstall.files_check`。
- 门禁实跑：`xcodebuild test -scheme Zmole -destination 'platform=macOS'` → 145 passed；`pytest -m contract`（在 `.repo_template/` 下）→ 147 passed。

#### 处置确认

- t019_code_f008 **PARTIAL**。dry-run 不再随焦点自动触发；作为显式用户动作，且取 `.uninstall` lease。`OperationCoordinator.acquire` 为全局单租约（`activeLeaseID`），故与前一批 preview/execution 互斥——`previewUninstall`/`confirmExecution` 在该 dry-run 期间会拿到 nil 并走既有 busy 失败分支，不再与执行重叠。残留见 f009：`loadList()` 不调用 `acquire`，绕过协调器，详见下文。
- f002/f003/f004/f005/f006/f007 状态同 round 2（f002 PARTIAL、f003 FIXED、f004 FIXED、f005/f006/f007 OPEN），本轮无变化。

#### 新发现

### t019_code_f009 详情 dry-run 缺进度反馈，且刷新仍可撞共享进程（Low）

`loadRelatedFiles` 现为显式动作（约 33s，见 s001），但无任何进行中状态：按钮保持可见可点，`session.isBusy`/`isListing` 均不变，重复点击被 `coordinator.acquire` 静默拒绝，用户无 spinner、无取消入口（`self.lease` 未赋值，工具栏不会切到取消态）。同时 `loadList()`（`UninstallViewModel.swift:75`）只查 `session.isBusy`/`isListing`、不取 coordinator 租约，故详情 dry-run 在飞时点工具栏刷新 → `uninstall --list` 命中 `MoleBridge.busy` → `listSession.fail`、`apps=[]`、`hasLoaded=false`，列表被清空并显示错误（可再刷新恢复）。建议：把详情 dry-run 的“在飞”状态并入 `loadList` 守卫（或让 `loadList` 也走 coordinator），并在详情面板加进度/禁用态。属 f008 残留，非回归。

#### 结论

f008 的主要目标（取消焦点自动 dry-run、以显式动作 + `.uninstall` 租约消除与批量预览/执行的并发）已达成；门禁 145/147 全绿，AC-001–007 断言通过，本轮未发现回归。残留 f009（Low，f008 的刷新路径未协调 + 无进度反馈）与 f005/f006/f007 一并作为收尾建议，不阻断本次 spec 达成。

reviewed_scope: 5b2d5ab80d5cb213

verdict: PASS

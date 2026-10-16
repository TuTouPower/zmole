# Task review t029（reviewer_focus: 代码）

- task：`t029_uninstall_list_progressive`
- spec：`docs/tasks/t029_uninstall_list_progressive/spec.md`
- diff_anchor：`ab664ca5f9ba3a484abad7a3c1c0056123e82534`
- target：`git -C '/Users/karson/kar/code/zmole_t029' diff ab664ca5f9ba3a484abad7a3c1c0056123e82534`
- round：1
- reviewed_at：2026-10-17T02:36:00+08:00

## Findings

### t029_code_f001 - 被写入取消的预跑项在一次空闲周期内跑两次

- 严重度：important
- 锚点：AC-012（「无写入且无进行中的用户扫描时……各跑一次」；配合 spec 范围「失败项在下一次空闲时重试」）
- 位置：`src/zmole/Features/Operations/PrewarmService.swift:124-128`（`queue = retries + queue`）、`:156-165`（`cancelCurrent(requeue:)`）、`:199-202`（`noteFailure`）
- 问题：写入开始时 `noteActivityChanged()` 走 else 分支调 `cancelCurrent(requeue: true)`，把正在跑的项插回队首（`queue.insert(item, at: 0)`）；随后该次运行以 `MoleBridgeError.cancelled` 结束，`run` 的 catch 调 `noteFailure(item)` 又把同一项放进 `retryItems`。下一次空闲时 `queue = retries + queue` 没有去重，同一项在队列里出现两份，`drain` 会连续执行两次。可复现路径：预跑正在跑 `uninstall --list-stream`（s001 实测约 36s）时用户执行一次 clean（或任意写入）→ 写入结束回到空闲 → uninstallList 在同一队列里被完整扫描两次。旧测试 `testStartingAWriteCancelsTheCurrentPrewarmRun` 只断言取消计数，释放租约后没有检查队列，因此套件未覆盖。
- 建议：merge 时去重，如 `queue = retries + queue.filter { !retries.contains($0) }`；或 `noteFailure` 加 `guard !queue.contains(item) else { return }`（保留 `cancelCurrent` 的 requeue 作为唯一来源）。

### t029_code_f002 - 磁盘测量静默结束时预跑不再被唤醒

- 严重度：important
- 锚点：AC-012（空闲时应各预跑一次）；AC-018 相关（空闲判定使用磁盘页扫描状态）
- 位置：`src/zmole/Features/Analyze/AnalyzeViewModel.swift:57-59`（`isScanning`）、`:177-189`（`processMeasurements`，`measurementWorker = nil`）、`src/zmole/App/AppDependencies.swift:687-700`（仅订阅四个 VM 的 `objectWillChange`）
- 问题：空闲判定 `isScanning` 由非 `@Published` 的 `measurementWorker` / `pendingMeasurements` 组成；测量任务收尾（worker 置 nil、队列清空）不写任何 `@Published` 属性，也不改 coordinator，因此不触发任何 prewarm 订阅的事件。可复现路径：打开磁盘页 → 进入某目录 → 在该目录测量完成之前返回上级；后台剩余测量属于子目录，最后一次 `apply` 的 `touched` 不含当前 `level`，全程无 `objectWillChange`。此时 prewarm 停在 `wasIdle=false`、队列非空、`worker=nil` 状态：应用已空闲但预跑不再启动，直到下一次无关事件（页面扫描、写入等）才恢复。AC-012 的「无写入且无进行中的用户扫描时各跑一次」在该流程内不成立，各页也不会出现预跑时间戳。
- 建议：让分析页的扫描状态可观察——把 worker 收尾放进 `@Published`（或在 `processMeasurements` 结束时显式通知 prewarm），或让 `PrewarmService` 对 `isScanning` 使用可订阅的派生属性。

### t029_code_f003 - clean 预跑与用户预览对同一清单文件存在启动竞态

- 严重度：minor
- 锚点：行为缺陷（clean-list.txt 争用）+ AC-013/AC-017 的取消语义在窄窗口内失效
- 位置：`src/zmole/Features/Operations/PrewarmService.swift:176-182`（`run` 只在启动前查 `cleanPreviewActiveProvider`）、`:220-230`（clean 载荷写 store）、`src/zmole/App/AppDependencies.swift:681-684`、`src/zmole/Features/Clean/CleanViewModel.swift:85-111`
- 问题：`cleanPreviewActiveProvider` 只看「已有预览 / 确认框」，不覆盖用户预览正在跑（`isPreviewing`）。当预跑的 clean 项启动与用户点「预览」在 `run(item)` 的 isIdle 检查之后、bridge 注册 runner 之前交错时，`cancelCurrent` 派发的取消 Task 可能先于 runner 注册到达而成为空操作（`MoleBridge.cancel` 的 `guard let runner = activeRunner else { return }`），此后两个 `clean --dry-run` 会同时在 ~33s 内写同一份 `~/.config/mole/clean-list.txt`；用户侧 `read(generation)` 可能读到半写/被覆盖的文件（`emptyFile`/`invalidUTF8`）或另一进程的输出。窗口为亚毫秒级、且确认前 `verifyUnchanged` 仍会拦住错误执行，故定 minor。
- 建议：把 `cleanViewModel.isPreviewing` 并入 `externalActivityProvider`（或 `cleanPreviewActiveProvider`），并在 `run(item)` 真正 spawn 前二次检查 `isIdle()`。

### t029_code_f004 - 确认时未核对「卸载名」（AC-005 字面与实现不一致）

- 严重度：minor
- 锚点：AC-005 字面（「路径、bundle id 或卸载名相对预览有变化，则拒绝」）；实现合理但与 spec 描述不符，建议处置为改 spec
- 位置：`src/zmole/Features/Uninstall/UninstallViewModel.swift:396-400`、`src/zmole/Features/Uninstall/UninstallMetadata.swift:38-46`
- 问题：确认前核对只做 `path` 存在 + `bundleIdentifier == bundleID`，没有比对 `uninstallName`。卸载名由扫描派生（mdls 显示名或 brew cask token），无法在不重扫的前提下轻量复核；本 diff 更新的 `docs/blueprint/architecture.md` 已明确写「确认前只做轻量身份核对（路径存在、bundle id 未变）」。残余风险限于 Homebrew cask token 在 path/bundle id 不变时变化的窄场景（此时脚本按旧名解析，通常以失败告终而非误删）。
- 建议：同步 spec/AC-005 措辞（或在 `docs/blueprint/decisions.md` 记录「卸载名不参与确认核对」的取舍），不再按字面升级为 blocking。

### t029_code_f005 - 本任务产生/遗留的孤儿代码

- 严重度：minor
- 锚点：代码质量（死代码）
- 位置：`src/zmole/Features/Uninstall/UninstallSnapshot.swift:95-98`（`UninstallListSnapshot`，全仓零引用）、`:106`（`UninstallPreviewSnapshot.identities`，旧确认核对用，现已无引用）、`:149-161`（`UninstallListDecoder`，仅 `tests/unit/BatchUninstallTests.swift:6` 使用）、`:166-175`（`UninstallListFilter.visible`，仅测试使用）、`src/zmole/Features/Operations/PrewarmService.swift:13-26`（`PrewarmItem.commandArguments`，新代码，零引用，命令在 `payload(for:)` 另行硬编码）
- 问题：`fetchList` 被本任务删除后，上述类型/函数失去生产消费者；`commandArguments` 是新增但从未接入的重复定义（同一命令表在 `payload(for:)` 再写一遍，未来改命令易分叉）。
- 建议：删除零引用项；`commandArguments` 要么接入 `payload(for:)` 作为唯一来源，要么删除。

### t029_code_f006 - changedTarget 后的重扫只合并不清理，已消失应用留在列表

- 严重度：minor
- 锚点：AC-005（「有变化时拒绝本次执行……并重新扫描名单」）
- 位置：`src/zmole/Features/Uninstall/UninstallViewModel.swift:117-151`（`performList` 不清 `listings`）、`:444-448`（changedTarget 触发重扫）
- 问题：`performList` 只按 path 追加/覆盖，不删除本次扫描未再出现的行。确认被拒后的自动重扫里，触发拒绝的那个应用（路径已消失或身份已变）会以旧数据留在名单上，用户仍可选中并再次预览（随后以 dry-run 失败告终，安全性由 target checker 兜底）；「重新扫描名单」实际不完整。手动刷新（`loadList`）会清空，因此是路径相关的显示缺陷。
- 建议：重扫时以本次流到的 path 集合裁剪 `listings`（或至少清理未再出现的已选行），保留 selectedPaths 的语义另行处理。

### t029_code_f007 - `sizeLabel` 前景色三元两分支相同

- 严重度：minor
- 锚点：代码质量（死表达式/表达意图不清）
- 位置：`src/zmole/Features/Uninstall/UninstallView.swift:232`
- 问题：`.foregroundStyle(listing.sizeText == nil && viewModel.isListing ? .secondary : .secondary)` 两个分支相同，「计算中」与「未知」样式实际无差别，读起来像漏了另一分支的实现。
- 建议：删除条件保留单一 `.secondary`，或补上原意的区分样式。

### t029_code_f008 - 流式名单 merge 逻辑在两处重复

- 严重度：minor
- 锚点：代码质量（DRY，verbatim 重复）
- 位置：`src/zmole/Features/Uninstall/UninstallViewModel.swift:123-133` 与 `src/zmole/Features/Operations/PrewarmService.swift:206-217`
- 问题：`indexByPath` 合并「later-row-wins」的实现逐行重复；目前行为一致，但后续任何一侧的修正（如 f006 的裁剪）都需要改两处。
- 建议：提取为 `UninstallAppListing` 上的静态合并函数（或序列化工具）供两处调用。

## 结论

- 本轮新发现：8 条（important 2 / minor 6）。
- 未进表的提示：
    - 文件过大（实现源码 ≥400 且本 task 净增）：`src/zmole/Features/Uninstall/UninstallViewModel.swift` 510 行（460→510）、`src/zmole/Features/Uninstall/UninstallView.swift` 440 行（398→440）、`src/zmole/App/AppDependencies.swift` 704 行（574→704）。建议后续 task 拆分（尤其 AppDependencies 的装配）。
    - 排除计量：`src/zmole/Resources/mole/bin/uninstall.sh`（2105 行）与 `installer.sh`（1059 行）是上游 mole 脚本承载本地 patch 的 vendor 文件（带 "zmole local patch" 标注、按上游 bump 重放），不按文件过大阈值计时；本次 patch 增量 +114/+70 行。
    - 圈复杂度（手算近似）：`UninstallViewModel.confirmExecution` ≈15（以线性错误映射分支为主，任务内分支增减相当，未超 finding 门槛）；新增的 `PrewarmService.payload/run`、`UninstallListStreamParser.listing` 各 ≤7。
    - 范围外观察：demo 的 `DemoUninstallListStream` 合成 version/last_used（demo 数据，不影响真实路径）；`MOLE_INSTALLER_SCAN_DISABLED` 是集成测试钩子，生产环境不设置，无行为影响。
- AC 复验方式：
    - AC-001 re_verified：真实 CLI 黑盒运行捆绑 `uninstall.sh --list-stream`（只读通道），66 条身份行 0.7s 到达、完整行与 `{"event":"done"}` 38.0s（与 s001 的 36s 一致），身份行不含 size。
    - AC-002 re_verified：`NSMetadataItem`/`LiveUninstallMetadataProvider` 全仓零引用；黑盒完整行含 `version:"1.0.0"` 与 `last_used_epoch`（int）；`UninstallDetailTests` 断言版本/上次使用随行携带。
    - AC-003 re_verified：图标走 `UninstallIconProviding` 异步补、行先渲染占位；`UninstallStreamProgressTests.testIconsLoadAfterTheListIsAlreadyVisible` 通过（列表先可见、图标 gate 后到）。
    - AC-004 re_verified：确认路径不再调 `fetchList`；`UninstallTests` 断言调用序列无 `uninstall --list`、仅 `--dry-run` + 执行。
    - AC-005 re_verified：`LiveUninstallTargetChecker` + `testUninstallChangedTargetCannotExecuteAndRescansTheList` 通过（不 spawn `uninstall`、重扫名单 2 次）；卸载名未核对见 f004。
    - AC-006 re_verified：`testRelatedPathsAreNotLoadedWithoutAUserRequest` 通过（未点击零调用）。
    - AC-007 re_verified：确认前 `--dry-run`、确认后才 spawn；`testCancelConfirmationDoesNotExecuteUninstall` 通过。
    - AC-008 re_verified：重跑 `tests/integration/installer_interface_test.sh`，t029 两例通过（`MOLE_INSTALLER_SCAN_DISABLED=1` 下删除成功，证明删除不再遍历扫描根）。
    - AC-009 re_verified：集成脚本「size change / identity mismatch is refused」通过，文件保留；脚本逐字节比对目标自身 size 与 identity。
    - AC-010 re_verified：Swift 侧 `lastListing` 复核（`testStaleSelectionCannotRemoveAnUnlistedPath` 通过）+ 集成脚本「path not listed is refused」。
    - AC-011 re_verified：`confirmRemoval` 要求确认框状态，未确认无删除路径。
    - AC-012 re_verified（有间隙）：`testQueueRunsEachItemOnceInOrderWithoutOverlap` 通过（顺序、单并发、无租约）；但 f001/f002 的可复现场景会破坏「各跑一次」。
    - AC-013 re_verified：测试断言 `coordinator.activeOperation == nil` 且写入可即时获得租约并触发取消；启动竞态见 f003。
    - AC-014 re_verified：四页采纳测试通过（`testUninstallPageAdopts…`、`testInstallersPageAdopts…`、`testCleanPageAdopts…`、`testOptimizeAndPurgeAdoptPrewarmPreviews`）；页面 `.task` 采纳 + `prewarm.scan_time %@` 文案已在代码确认。
    - AC-015 re_verified：`invalidatePreviews` 覆盖各写入路径并经订阅清空结果（`testInvalidationClearsResultsAndRequeuesEverything` 通过）；确认框保护测试 `testCleanPageAdoptsPrewarmPreviewAndProtectsTheConfirmation` 通过。
    - AC-016 re_verified：`testPrewarmOnlyUsesReadOnlyDryRunCommands` 通过；命令表固定在 `payload(for:)`。
    - AC-017 re_verified：`testUserRescanDropsThatItemFromTheQueue` 通过；`userDidRescan` 取消当前项并丢弃结果。
    - AC-018 re_verified：`externalActivityProvider` 含 `analyze.isScanning`；`testDiskScanningBlocksPrewarmUntilIdle`（合成 provider）通过；真实通知缺口见 f002。
    - AC-019 re_verified：`testDemoConfigurationDisablesPrewarm` 通过；`lanes.prewarm == nil`、demo 不装配 PrewarmService。
    - 另：全量 `xcodebuild test`（233 例）通过；两组 shell 语法检查通过。coverage = 19/19 re_verified（trust_prior 0）。
- 总体判断：机制落地完整、测试与真实 CLI 验证大多通过；但预跑队列存在两处可复现的行为缺陷（f001 重复执行、f002 空闲信号丢失），修复前不可信。
- 系统性 follow-up：无（`task.py list` 未见等价 task；f001/f002 属本任务内缺陷）。

reviewed_scope: 22f73bf27b02d13c

verdict: FAIL

## Round 2 (2026-10-17T02:52:00+08:00)

### 前轮 finding 复核（以相对 `ab664ca5f9ba3a484abad7a3c1c0056123e82534` 的 diff 与代码为准）

- f001 已消除。`PrewarmService.swift:107-122` 空闲合并改为 `queue = retries + queue.filter { !retryItems.contains($0) }`，被取消项（`cancelCurrent` 的 requeue 与 `noteFailure` 的 retry 双记账）合并后只保留一份；新增回归 `PrewarmTests.testCancelledItemIsRequeuedExactlyOnce`（`tests/unit/PrewarmTests.swift:35-63`）断言取消项只再跑一次、总计 6 次调用；本机重跑全套通过。
- f002 已消除。`AnalyzeViewModel.swift:14` `@Published private(set) var isScanning`，`:56-65` `refreshScanState()`，调用点覆盖全部跃迁：`list` 起止（`:126-131`）、`startMeasurementWorker`（`:185`）、`processMeasurements` 收尾（`:199-200`）。测量任务静默结束时 isScanning 变 false 会发 `objectWillChange`，预跑订阅可收到空闲信号；未发现遗漏路径。
- f003 已修（残余窗口维持原级）。`AppDependencies.swift:681-686` `cleanPreviewActiveProvider` 并入 `cleanViewModel.isPreviewing`，覆盖「用户预览进行中」的延后判定。Round 1 建议的第二半（spawn 前二次 `isIdle` 检查）未实现，取消 Task 与 bridge 注册 runner 的亚毫秒竞态窗口理论上仍在；结果仍由 `verifyUnchanged` 兜底、非破坏性，维持 minor，不另开 finding。
- f004 已消除（spec 同步）。`spec.md` 范围与 AC-005 收紧为「路径或 bundle id」，并写明卸载名由预览/执行命令自身失败暴露；与实现（`UninstallViewModel.swift:404-406` + `LiveUninstallTargetChecker`）及 blueprint 一致。prompt 尾部契约区 drift 即本条推荐处置，非未经确认的 AC 变更。
- f005 修不彻底。`UninstallListSnapshot`、`UninstallPreviewSnapshot.identities`、`UninstallListDecoder`、`UninstallListFilter.visible`、`PrewarmItem.commandArguments` 均已删除且无引用；但删除 `identities` 后其底层 `UninstallApp.identity`（`UninstallSnapshot.swift:18-20`）与 `UninstallIdentity`（`:89-93`）成为零引用死代码 → 见 f010。
- f006 修不彻底。裁剪已实现（`UninstallViewModel.swift:124-139` 按 `seenPaths` 裁 listings/selection/related/icons），但名单合并仍以全新 `indexByPath` 追加进**既有** `listings` → 重扫时每个仍存在的应用被追加成两份、裁剪后依旧重复 → 见 f009（important）。
- f007 已消除。`UninstallView.swift:232` 现为单一 `.foregroundStyle(.secondary)`，同分支三元已删。
- f008 已消除。`UninstallListMerge`（`UninstallListStream.swift:80-93`）被 `UninstallViewModel.performList`（`:128`）与 `PrewarmService.payload`（`:197`）共用，无第二份实现。

### 本轮新发现

#### t029_code_f009 - 身份变化重扫把名单里每个应用追加成重复行，之后预览必然失败

- 严重度：important
- 锚点：AC-005（拒绝后「重新扫描名单」须得到可用名单）+ 行为缺陷：重扫后点预览报 `changed_target`，列表 `ForEach` 出现重复 id
- 位置：`src/zmole/Features/Uninstall/UninstallViewModel.swift:123-139`、`src/zmole/Features/Uninstall/UninstallListStream.swift:80-93`
- 问题：`performList` 每次都用新的空 `indexByPath`，却把行 merge 进**不清空**的 `listings`（只有 `loadList` 会清空）。`confirmExecution` 的 changedTarget 分支（`UninstallViewModel.swift:450-454`）在既有名单上直接调 `performList`：对每个已在名单中的应用，identity 行因 `indexByPath` 无记录被 `rows.append` 追加副本，后续完整行只更新副本；收尾 `listings.filter { seenPaths.contains($0.path) }` 按 path 过滤不去重，老副本与新副本同时保留 → 名单行数翻倍且 `id`（=path）重复。失败场景：应用 A 在磁盘上被替换/删除 → 确认被拒 → 重扫 → 用户选中任一未变应用点预览 → `UninstallSelectionValidator.batch`（`UninstallSnapshot.swift:166-168`）发现 `selected.count(2) != selectedIDs.count(1)` → 抛 `.changedTarget`，面板显示「目标已变化」，预览在手动刷新（`loadList`）前始终失败；同时 `selectedApps`/`knownSelectedBytes` 把已选体积翻倍，`ForEach(visibleListings)` 出现重复 id。现有测试 `testUninstallChangedTargetCannotExecuteAndRescansTheList`（`tests/unit/UninstallTests.swift:140-168`）只断言 `opens==2`，不检查 `listings` 内容，故未被捕获。
- 建议：重扫时以本次扫描结果为准重建——在 `performList` 内 `var fresh: [UninstallAppListing] = []` 配局部 `indexByPath` 合并，结束后 `listings = fresh`（或 merge 前清空 `listings`/`indexByPath`），再做 `seenPaths` 裁剪；补一条断言重扫后无重复 path 的用例。

#### t029_code_f010 - f005 残留零引用：`UninstallIdentity` 与 `UninstallApp.identity`

- 严重度：minor
- 锚点：代码质量（死代码，f005 修不彻底）
- 位置：`src/zmole/Features/Uninstall/UninstallSnapshot.swift:18-20`、`:89-93`
- 问题：`UninstallPreviewSnapshot.identities` 删除后，`UninstallApp.identity` 与 `UninstallIdentity` 在 src/tests 全仓零引用（rg 仅命中定义自身）。
- 建议：连同 `UninstallIdentity` 一并删除，或在需要时再恢复。

### 本轮结论

- 前轮 finding 复核：f001/f002/f003/f004/f007/f008 已消除，f005/f006 修不彻底（残余见 f010/f009）。
- 本轮新发现：2 条（important 1 / minor 1）。
- 未进表的提示：文件过大不变——`UninstallViewModel.swift` 516 行、`UninstallView.swift` 440 行、`AppDependencies.swift` 706 行（vendor 脚本 `uninstall.sh` 2113 / `installer.sh` 1059 排除计量）；测试用环境钩子 `MOLE_UNINSTALL_SCAN_ROOT`（`uninstall.sh:513-520`）与 `MOLE_INSTALLER_SCAN_DISABLED` 仅测试设置、生产不设，无行为影响；复杂度无新增超线函数（`confirmExecution` 与 Round 1 相同）。
- 总体判断：两处原 important（f001/f002）与其余 minor 已核实修好，但 f006 的裁剪修复残留重扫重复行缺陷（f009，important），修复前 PASS 不成立。
- 系统性 follow-up：无。

### AC 复验方式

- AC-001 re_verified：重跑 `tests/integration/uninstall_stream_test.sh`（真实脚本 + 隔离 HOME + fixture 扫描根）：身份行在前、完整行在后、末 `{"event":"done"}`；流式代码与 Round 1 实机黑盒（66 条身份行 0.7s 到达、38s done）逐行一致。
- AC-002 re_verified：上述集成测试断言 `version=="2.3"`（读目标 Info.plist）与 `last_used_epoch` 为整数；`NSMetadataItem` 全仓零引用。
- AC-003 re_verified：`UninstallStreamProgressTests.testIconsLoadAfterTheListIsAlreadyVisible` 重跑通过。
- AC-004 re_verified：`UninstallTests` 全绿，断言确认仅 `--dry-run`+执行、无 `--list`。
- AC-005 re_verified（含缺陷）：新增 `UninstallTargetCheckerTests` 四分支通过（路径缺失/身份变化拒绝、身份相同/空 bundle id 放行）、重扫触发（opens==2）通过；重扫后名单重复的缺陷见 f009。
- AC-006 re_verified：`testRelatedPathsAreNotLoadedWithoutAUserRequest` 全绿。
- AC-007 re_verified：确认前 dry-run、取消确认不执行等用例全绿。
- AC-008 re_verified：重跑 `tests/integration/installer_interface_test.sh`，t029 两例通过（扫描根只遍历一次）。
- AC-009 re_verified：集成脚本 size/identity 变化拒绝、文件保留用例通过。
- AC-010 re_verified：`InstallersPageTests` 全绿（选择恒来自会话名单、重扫后不可删除）；代码核对 `selectedCandidates ⊆ lastListing` + `canConfirm` 子集约束 + 脚本候选检查。
- AC-011 re_verified：确认门控与未确认不删除用例全绿。
- AC-012 re_verified：顺序/互斥/零租约用例 + 新增 `testCancelledItemIsRequeuedExactlyOnce` 通过。
- AC-013 re_verified：断言预跑零租约、写入即时获租约并取消当前项；f003 残余窗口说明见复核。
- AC-014 re_verified：四页采纳预跑结果测试全绿。
- AC-015 re_verified：作废重跑与确认框保护用例全绿。
- AC-016 re_verified：只读命令白名单用例全绿。
- AC-017 re_verified：用户重扫丢弃用例全绿。
- AC-018 re_verified：`testDiskScanningBlocksPrewarmUntilIdle` 全绿；isScanning 三处跃迁代码核对。
- AC-019 re_verified：demo 无预跑用例全绿。
- coverage = 19/19 re_verified（trust_prior 0）。

reviewed_scope: 966025fc156710b2

verdict: FAIL

## Round 3 (2026-10-17T02:59:00+08:00)

### 前轮 finding 复核（以相对 `ab664ca5f9ba3a484abad7a3c1c0056123e82534` 的 diff 与代码为准）

- f009 已消除。`UninstallViewModel.performList`（`UninstallViewModel.swift:124-136`）改为局部 `merged` + 局部 `indexByPath` 合并（`:130` 仍走 `UninstallListMerge.merge`），每行流到即 `listings = merged` 发布（`:132-135`，保留渐进可见），扫描结束时整份替换 → 重扫不再把旧行追加成重复项；成功路径的 `selectedPaths/related/icons` 裁剪保留（`:137-140`）。回归断言 `testUninstallChangedTargetCannotExecuteAndRescansTheList` 新增两条（`tests/unit/UninstallTests.swift:168-170`：无重复 path、重扫后名单替换为 1 行），本机重跑通过；Round 2 版本代码在该断言下会得到 2 行，能真实拦住回归。
- f010 已消除。`UninstallIdentity` 与 `UninstallApp.identity` 已删除（`UninstallSnapshot.swift` 现 311 行），全仓 grep 仅剩 `InstallerCandidate.identity`（不同领域类型）。
- 此前已闭合项无回归：与 Round 2 相比，`PrewarmService.swift`（235）、`AnalyzeViewModel.swift`、`AppDependencies.swift`（150 diff 行）、`UninstallListStream.swift`（145）等文件均无新改动；本机重跑全套 236 例、`installer_interface_test.sh`、`uninstall_stream_test.sh`（rc=0）与 `pytest .repo_template/tests -m contract`（147 passed）全部通过。f003 残余亚毫秒窗口与 f004 的 spec 同步维持 Round 2 结论。

### 本轮新发现

#### t029_code_f011 - 取消重扫后选中集合不裁剪，预览按钮可能无提示禁用

- 严重度：minor
- 锚点：行为缺陷（取消路径与成功路径状态不一致）；窗口亚秒级、可恢复、无数据风险
- 位置：`src/zmole/Features/Uninstall/UninstallViewModel.swift:137-148`（成功路径裁剪 `:137-140`，取消分支 `:146-148` 直接早退）
- 问题：`performList` 现在每行就把 `listings` 整体替换为部分 `merged`，但取消路径不做 `selectedPaths/related/icons` 裁剪。场景：`confirmExecution` 身份核对失败 → 自动重扫（`selectedPaths` 保留 refusal 前的选择）→ 用户在身份行未全部到达前点「取消」（`cancelList`）→ `listings` 已被替换为部分名单，而选中集合里仍含未再出现的 path。此时 `canPreview`（`:73-78`）要求每个选中 path 都在 `listings` 且已解析 → 为 false，预览按钮无提示禁用；这些 path 也没有对应行可取消勾选（需用「清除选择」或刷新恢复）。身份行实测 0.7s 内到齐，故实际窗口极短、影响低。
- 建议：把 `seenPaths` 裁剪移出成功分支（成功/取消都执行，如用 `defer` 或在 catch 内做同样交集），或取消路径清空 selection。

### 本轮结论

- 前轮 finding 复核：f009/f010 已消除；f001–f008 无回归（同上，不再重复展开）。
- 本轮新发现：1 条（minor，f011）。
- 未进表的提示：文件过大不变——`UninstallViewModel.swift` 517 行、`UninstallView.swift` 440 行、`AppDependencies.swift` 706 行（vendor 脚本 `uninstall.sh` 2113 / `installer.sh` 1059 排除计量）；复杂度无新增超线函数；`performList` 逐行 `listings = merged` 为 O(n²) 拷贝，n 为数百行内，量级可忽略，不作 finding。
- 总体判断：前轮 important（f009）与 f010 已按 diff 核实修复，无未解决 critical/important，仅余 1 条 minor → PASS。
- 系统性 follow-up：无。

### AC 复验方式

- AC-001 re_verified：`performList` 逐行发布 `listings`（`:132-135`）+ `UninstallStreamProgressTests.testListingsAppearBeforeSizesFinish` 重跑通过；`uninstall_stream_test.sh` 重跑通过（身份行在前、完整行后补）。
- AC-002 re_verified：集成测试断言 `version=="2.3"`（读 Info.plist）与 `last_used_epoch` 为整数；`NSMetadataItem` 全仓零引用。
- AC-003 re_verified：`testIconsLoadAfterTheListIsAlreadyVisible` 重跑通过。
- AC-004 re_verified：`UninstallTests` 全绿，确认仅 `--dry-run`+执行、无 `--list`。
- AC-005 re_verified：`UninstallTargetCheckerTests` 四分支通过；重扫链路（拒绝 → `performList` → 永不 spawn 卸载、名单剪裁与替换）由更新的 `testUninstallChangedTargetCannotExecuteAndRescansTheList`（含无重复断言）复核通过；取消路径残差见 f011。
- AC-006 re_verified：`testRelatedPathsAreNotLoadedWithoutAUserRequest` 全绿。
- AC-007 re_verified：确认前 dry-run、取消确认不执行等用例全绿。
- AC-008 re_verified：`installer_interface_test.sh` 重跑通过（t029 两例）。
- AC-009 re_verified：集成脚本 size/identity 变化拒绝用例通过。
- AC-010 re_verified：`InstallersPageTests` 全绿 + 代码核对 `selectedCandidates ⊆ lastListing` 与 `canConfirm` 子集约束。
- AC-011 re_verified：确认门控与未确认不删除用例全绿。
- AC-012 re_verified：顺序/互斥/零租约与 `testCancelledItemIsRequeuedExactlyOnce`（exactly-once）全绿。
- AC-013 re_verified：预跑零租约、写入即时获租约并取消当前项用例全绿。
- AC-014 re_verified：四页采纳预跑结果测试全绿。
- AC-015 re_verified：作废重跑与确认框保护用例全绿。
- AC-016 re_verified：只读命令白名单用例全绿。
- AC-017 re_verified：用户重扫丢弃用例全绿。
- AC-018 re_verified：`testDiskScanningBlocksPrewarmUntilIdle` 全绿；isScanning 三处跃迁代码核对。
- AC-019 re_verified：demo 无预跑用例全绿。
- coverage = 19/19 re_verified（trust_prior 0）。

reviewed_scope: e23ac1b75ca4593f

verdict: PASS

## Round 4 (2026-10-17T03:03:00+08:00)

### 前轮 finding 复核（以相对 `ab664ca5f9ba3a484abad7a3c1c0056123e82534` 的 diff 与代码为准）

- f011 已消除。`UninstallViewModel.performList` 将 session 裁剪抽为 `pruneSessionState(to:)`（`UninstallViewModel.swift:163-168`），在 do/catch 之后统一调用（`:152-154`）：成功与取消两条路径都会把 selected/related/icons 裁剪到本次流到的 path；`focusedAppID` 与 `startIconLoading()` 只在 `hasLoaded` 时执行（`:155-160`），取消扫描不再留下与部分 listings 不一致的选中集合。代码路径核对 + 全套 236 例重跑通过（含 `UninstallTests` 10 例）。
- 此前已闭合项无回归：与 Round 3 相比，`AppDependencies.swift`（150 diff 行）、`AnalyzeViewModel.swift`（20）、`PrewarmService.swift`（235）、`UninstallListStream.swift`（145）、`UninstallSnapshot.swift`（69）、`InstallersViewModel.swift`（30）等全部 stat 一致，仅 `UninstallViewModel.swift` 因抽出 `pruneSessionState` 净增（现 527 行）；本机重跑 236 例套件、`uninstall_stream_test.sh`、`installer_interface_test.sh`（均 rc=0）与 `pytest .repo_template/tests -m contract`（147 passed）全部通过。f003 亚毫秒残余窗口与 f004 的 spec 同步维持 Round 2/3 结论。

### 本轮新发现

0 条（clean review）。对 Round 4 delta（仅 `performList` / `pruneSessionState`）按安全/正确性/契约·Breaking/性能·资源/架构·可维护性/健壮性·可观测/测试·文档·规格逐项扫过，未命中。

### 本轮结论

- 前轮 finding 复核：f011 已消除；f001–f010 无回归（同上，不再重复展开）。
- 本轮新发现：0 条。
- 未进表的提示：低置信度观察一条——非取消类的扫描错误路径（`UninstallViewModel.swift:141-149`）仍早退不裁剪，出现 `listings=[]` 而 selection/related/icons 保留的短暂不一致；该行为自 Round 1 起未变、结果面板同时显示扫描错误提示、离开页面再进入即自愈，且错误时 `seenPaths` 只是部分集合、裁剪语义不明确，故不进 finding 表。文件过大不变——`UninstallViewModel.swift` 527 行、`UninstallView.swift` 440 行、`AppDependencies.swift` 706 行（vendor 脚本 `uninstall.sh` 2113 / `installer.sh` 1059 排除计量）；复杂度无新增超线函数。
- 总体判断：无未解决 critical/important，连续两轮无新 blocker → PASS。
- 系统性 follow-up：无。

### AC 复验方式

- AC-001 re_verified：`performList` 逐行发布 `listings`（`UninstallViewModel.swift:132-135`）+ `UninstallStreamProgressTests.testListingsAppearBeforeSizesFinish`、`uninstall_stream_test.sh` 重跑通过（身份行在前、完整行后补）。
- AC-002 re_verified：集成测试断言 `version=="2.3"`（读 Info.plist）与 `last_used_epoch` 为整数；`NSMetadataItem` 全仓零引用。
- AC-003 re_verified：`testIconsLoadAfterTheListIsAlreadyVisible` 重跑通过；图标加载仍只在扫描成功后启动（`:155-159`）。
- AC-004 re_verified：`UninstallTests` 全绿，确认仅 `--dry-run`+执行、无 `--list`。
- AC-005 re_verified：`UninstallTargetCheckerTests` 四分支通过；拒绝 → 重扫链路（无重复、名单替换、cancel 后裁剪一致）由更新后的测试与代码核对复核。
- AC-006 re_verified：`testRelatedPathsAreNotLoadedWithoutAUserRequest` 全绿。
- AC-007 re_verified：确认前 dry-run、取消确认不执行等用例全绿。
- AC-008 re_verified：`installer_interface_test.sh` 重跑通过（t029 两例，rc=0）。
- AC-009 re_verified：集成脚本 size/identity 变化拒绝用例通过。
- AC-010 re_verified：`InstallersPageTests` 全绿 + 代码核对 `selectedCandidates ⊆ lastListing` 与 `canConfirm` 子集约束。
- AC-011 re_verified：确认门控与未确认不删除用例全绿。
- AC-012 re_verified：顺序/互斥/零租约与 exactly-once 用例全绿。
- AC-013 re_verified：预跑零租约、写入即时获租约并取消当前项用例全绿。
- AC-014 re_verified：四页采纳预跑结果测试全绿。
- AC-015 re_verified：作废重跑与确认框保护用例全绿。
- AC-016 re_verified：只读命令白名单用例全绿。
- AC-017 re_verified：用户重扫丢弃用例全绿。
- AC-018 re_verified：`testDiskScanningBlocksPrewarmUntilIdle` 全绿；isScanning 三处跃迁代码核对。
- AC-019 re_verified：demo 无预跑用例全绿。
- coverage = 19/19 re_verified（trust_prior 0）。

reviewed_scope: 4cd8a9b2eaaa5528

verdict: PASS

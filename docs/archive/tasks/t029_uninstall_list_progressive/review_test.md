# Task review t029（reviewer_focus: 测试）

- task：`t029_uninstall_list_progressive`
- spec：`docs/tasks/t029_uninstall_list_progressive/spec.md`
- diff_anchor：`ab664ca5f9ba3a484abad7a3c1c0056123e82534`
- target：`git -C '/Users/karson/kar/code/zmole_t029' diff ab664ca5f9ba3a484abad7a3c1c0056123e82534`
- round：1
- reviewed_at：2026-10-17T02:28:32+08:00

reviewed_scope: 22f73bf27b02d13c

## Findings

### t029_test_f001 - 确认时身份核对实现（LiveUninstallTargetChecker）零测试，旧覆盖删除后未在任何层补回

- 严重度：important
- 锚点：AC-005（确认时路径/bundle id 变化 → 拒绝执行、不 spawn 卸载命令、重扫名单）
- 位置：`src/zmole/Features/Uninstall/UninstallMetadata.swift:38-47`；`tests/unit/UninstallTests.swift:140-168`；`tests/unit/UninstallTestSupport.swift:64-66`
- 问题：AC-005 的检测主体是 `LiveUninstallTargetChecker.stillMatches`（目标存在 + `Bundle.bundleIdentifier == app.bundleID`）。全部测试都经 `makeUninstallViewModel` 默认注入 `FixedTargetChecker(matches: true)`，替换后的 `testUninstallChangedTargetCannotExecuteAndRescansTheList` 再改注 `matches: false`——真实检测实现无任何用例（`rg LiveUninstallTargetChecker tests/` 无命中）。旧版由 VM 用整表比对实现，且由 `testUninstallChangedTargetCannotExecute` / `testUninstallMissingTargetCannotExecute` 覆盖；这两例随本 task 删除（UninstallTests.swift:136-139 注释自述合并），而检测覆盖没有在任何更高层补回。失败场景：若 `stillMatches` 被改错（恒返回 true、bundle 比对取反、`Bundle(url:)` 失败分支写反），233 例全绿，应用会对已变化的 target 执行不可逆卸载。检测逻辑是纯文件系统判断（临时目录造 `Foo.app` + Info.plist 即可测），不属于只能 mock 的系统边界。
- 建议：新增 `LiveUninstallTargetChecker` 单测：临时目录造带 `CFBundleIdentifier` 的 app bundle，断言「路径缺失→false」「bundle id 相同→true」「bundle id 不同→false」，可顺带覆盖 `bundleID` 空串分支。

### t029_test_f002 - testStaleSelectionCannotRemoveAnUnlistedPath 空转，实际验证的是「重扫清空确认态」而非名单外拒绝

- 严重度：important
- 锚点：AC-010（安装包路径不在当前名单中时拒绝删除）
- 位置：`tests/unit/InstallersPageTests.swift:161-175`；`src/zmole/Features/Installers/InstallersViewModel.swift:36、46、132、156`
- 问题：测试先 `requestConfirmation()` 再 `scan()`；`scan()` 已清空 `selectedPaths` 并把 `isConfirmationPresented` 置 false（InstallersViewModel.swift:78-79）。随后 `confirmRemoval()` 在 :132 `guard isConfirmationPresented, canConfirm` 直接早退，永远走不到 :156 的名单成员守卫。断言 `removals.isEmpty` 对 AC-010「名单外路径被拒」不构成证据：删除 :156 守卫后测试照样通过；且该守卫当前不可达——`batch = selectedCandidates`（:36）由 `lastListing` 过滤而来，`canConfirm`（:46）又要求 `selectedPaths ⊆ lastListing`，构造上不可能出现名单外元素，循环内也无法并发变更（`isRemoving` 阻断 scan/toggle/adopt）。测试注释「a path outside the current list must not be removed」把通过原因归到了不会执行的路径上；真正被验证的行为（重扫使待确认失效）已由 `testNewScanInvalidatesSelectionAndConfirmation`（:56-68）覆盖。
- 建议：二选一。要么让 :156 守卫可达并直接测它（例如 batch 取自重扫前的快照而非从 `selectedCandidates` 派生，测试构造「确认后名单被替换」仍进入删除循环的场景）；要么删除该不可达守卫与测试的误导性注释，把本测试改为明确断言「重扫后无法再执行删除」，不再宣称覆盖名单成员校验。

### t029_test_f003 - 新 CLI 表面 uninstall --list-stream 与 UninstallListStream(streaming:) 装配无任何测试

- 严重度：important
- 锚点：AC-001、AC-002（渐进名单先出、版本/上次使用来自同次扫描）——这两条 AC 的唯一生产数据源未被测试
- 位置：`src/zmole/Resources/mole/bin/uninstall.sh:1713-1767`（`uninstall_stream_apps`：fd3 身份行、完整行、plist 版本、`last_used_epoch`、done 标记）；`src/zmole/Features/Uninstall/UninstallListStream.swift:92-116`（`init(streaming:)` 的事件→行→parser 装配）；`tests/` 中无执行 uninstall.sh 的用例（`rg "list-stream|uninstall.sh" tests/` 仅命中 PrewarmTests 的参数断言）
- 问题：渐进行为的全部测试用注入行、注入 stream 或 `UninstallListStream(open:cancel:)` 直接构造，没有任何测试断言生产 emitter 的输出契约或 `init(streaming:)` 的装配结果。PrewarmTests 中唯一经过 `init(streaming:)` 的用例（PrewarmLaneSpy）只断言调用了 `["uninstall","--list-stream"]`，未断言 `results[.uninstallList]`（只断言 installerList/cleanDryRun），transform 写坏时 item 静默失败、后续项照跑，整套仍绿。失败场景：shell 侧字段名/类型漂移（如 `last_used_epoch` 输出成字符串、`size` 格式不被 `UninstallSizeParser` 识别、JSON 键拼错），Swift parser 静默丢弃或降级——真机上名单缺大小/版本甚至为空，而 233 例 + 集成测试全绿；demo 模式走 `DemoUninstallListStream`，兜不住真实脚本。同类新接口（installer `--remove`）在本 task 已补集成契约用例，uninstall 侧缺位。
- 建议：给 uninstall.sh 加与 installer.sh 同级的 fixture 根钩子（如 `MOLE_UNINSTALL_SCAN_ROOT`），在 `tests/integration` 增契约用例：断言身份行先于完整行、字段名与类型、N/A 不成为 0、末行 `{"event":"done"}`；至少补一个用脚本化 `MoleStreaming` 驱动 `UninstallListStream(streaming:)` 并断言解析后 rows 的单测（含 done 标记跳过与 malformed 行跳过）。

## 结论

- 前轮 finding 复核：本轮为 Round 1，无前轮 finding。
- 改测方向复核：修改/替换旧测试的方向本身合理——列表数据源改注入流、版本/上次使用改随扫描携带，均为 spec 已批准的决策（AC-002 与上下文区），断言更新方向是「新语义应有的预期」，非迁就实现；`testUninstallChangedTargetCannotExecute` + `testUninstallMissingTargetCannotExecute` 合并、元数据两例替换均有注释/理由。但被删两例所覆盖的「身份变化检测」没有在更高层补回（见 f001），该替换实际丢了覆盖。
- 本轮新发现：3 条（important 3）。
- 未进表的提示：
    - AC-018 的装配链路（`AnalyzeViewModel.isScanning` 与 AppDependencies 里 externalActivityProvider/objectWillChange 订阅）无测试；service 层用通用 activity provider 验证了机制，spec 测试策略已批准注入空闲信号，此处只作可选覆盖扩展。
    - PrewarmTests 的计数断言都是「等到目标计数立即读取」：晚到的重复执行（第 6 次等）不会被发现，exactly-once 只有弱证据；若要收紧，可在断言前多等一拍并断言计数不再增长。
    - `testUninstallConfirmationExecutesWithoutPermanentAndShowsSummary` 的「invocations 不含 --list」是对旧架构的代理断言；新架构下列表走 stream，confirm 期间重开 stream 不会被该测试发现（use CountingListStream 的用例只存在于 changed-target 测试与 adopt 测试）。
    - `--remove plain.zip`（zip 无安装载荷，不在名单）未测；installer_interface_test.sh 已有 notes.txt 非候选例，zip 载荷分支只在列表侧被覆盖。可选加一例。
    - `src/zmole/Features/Uninstall/UninstallView.swift` 的 `foregroundStyle(listing.sizeText == nil && viewModel.isListing ? .secondary : .secondary)` 两分支相同，属代码轴（code reviewer）观察，此处仅记录。
- AC 复验方式：
    - AC-001：re_verified（实跑套件；`testListingsAppearBeforeSizesFinish` 断言未就绪 sizeText 为 nil、parser 零值样例；生产 emitter 未测见 f003）
    - AC-002：re_verified（`testParserReadsIdentityAndFullRows`/`testVersionAndLastUsedComeFromTheListScan`；`rg NSMetadataItem src/` 已无命中，结构上无 Spotlight 路径；shell 侧见 f003）
    - AC-003：re_verified（`testIconsLoadAfterTheListIsAlreadyVisible` + 查证 UninstallView 以占位符渲染、图标异步补；滚动本身无渲染测试）
    - AC-004：re_verified（确认执行用例断言无 `--list`、变更路径用例 `opens == 2` 无第二份全量注入）
    - AC-005：re_verified（拒绝 + 重扫流程经 `testUninstallChangedTargetCannotExecuteAndRescansTheList` 实跑；真实检测实现无测试，见 f001）
    - AC-006：re_verified（`testRelatedPathsAreNotLoadedWithoutAUserRequest` 断言 invocations 为空）
    - AC-007：re_verified（无选择/取消确认两例断言不 spawn 非 dry-run uninstall）
    - AC-008：re_verified（`testBatchRemovalUsesTheSameListingWithoutRescanning` listCalls==1；集成新增「scan-disabled 仍可删除」实跑通过）
    - AC-009：re_verified（集成 AC-004(c)(d) size/identity 变更拒绝实跑通过）
    - AC-010：re_verified（行为由选中集合不变量结构性保证；测试空转见 f002）
    - AC-011：re_verified（`testNoRemovalBeforeConfirmation`、`testRemovalRequiresFreshConfirmationAfterCancel`）
    - AC-012：re_verified（`testQueueRunsEachItemOnceInOrderWithoutOverlap` 断言精确顺序与 maxConcurrent==1）
    - AC-013：re_verified（首例 `activeOperation == nil`；`testStartingAWriteCancelsTheCurrentPrewarmRun` 断言租约即时可得且 cancel 发生）
    - AC-014：re_verified（四个 adopt 测试断言 capturedAt 与零重扫；时间文本渲染为视图代码查证）
    - AC-015：re_verified（`testInvalidationClearsResultsAndRequeuesEverything` + 确认保护两段断言）
    - AC-016：re_verified（`testPrewarmOnlyUsesReadOnlyDryRunCommands` 黑名单 + 首例精确命令表）
    - AC-017：re_verified（`testUserRescanDropsThatItemFromTheQueue` + 各页 scan 先调 `userDidRescan` 后自行扫描）
    - AC-018：re_verified（`testDiskScanningBlocksPrewarmUntilIdle` 验证活动阻断与恢复；真实 isScanning 装配见提示）
    - AC-019：re_verified（`testDemoConfigurationDisablesPrewarm` 断言 prewarmService == nil）
    - coverage = 19 / 19（其中 AC-001/AC-002/AC-005 的生产侧证据缺口见 f001/f003；AC-010 见 f002；trust_prior 0）
- 总体判断：测试整体结构合理、套件实测 233 例全绿（含集成 installer/clean_trash 实跑），但确认时身份检测实现、安装包名单外拒绝、shell 端 --list-stream 数据源三处关键证据缺失或空转，本 task 测试层不可信，需补测后重审。
- 系统性 follow-up：无（三项均属本 task 应补的测试，建议留在本 task 修复；`task.py list` 中无等价 follow-up task）。

verdict: FAIL

## Round 2 (2026-10-17T02:51:00+08:00)

- 前轮 finding 复核（以 `git -C … diff ab664ca…`、当前代码/测试与独立重跑为准，不采信处置表自述）：
    - t029_test_f001 已消除：新增 `tests/unit/UninstallTargetCheckerTests.swift:5-48`，用真实 `LiveUninstallTargetChecker` + 临时目录 app bundle 覆盖四分支：路径存在且身份相同→true、身份不同→false、路径缺失→false、空 bundle id 仅核对路径→true。检测实现不再被桩绕开；VM 流程测试继续注入 `FixedTargetChecker`，属正确分层。该类隔离重跑通过。
    - t029_test_f002 已消除：不可达的逐文件守卫已从 `confirmRemoval` 删除（`src/zmole/Features/Installers/InstallersViewModel.swift:131-165`，循环直接遍历 batch），`installers.error.not_listed` 已无引用（`rg not_listed src/ tests/` 零命中）；原空转测试替换为 `testSelectionCannotOutliveItsSessionList`（`tests/unit/InstallersPageTests.swift:161-175`），断言改为「选择 ⊆ 会话名单 + 重扫后 `canConfirm == false` + `confirmRemoval` 不产生删除」，与实际执行机制一致，且能捕获「重扫不再清空选择/确认」的回归；误导性注释与空转宣称均已移除。隔离重跑通过。
    - t029_test_f003 已消除：`UninstallStreamingAssemblyTests.testStreamingInitializerTurnsCommandLinesIntoRows`（`tests/unit/UninstallStreamTests.swift:51-75`）用 `ScriptedMoleStreaming` 驱动生产 `UninstallListStream(streaming:)`，断言命令参数、malformed/done 跳过、2 行解析与 size/version/lastUsed 字段；`tests/integration/uninstall_stream_test.sh` 对真实 `uninstall.sh --list-stream`（`MOLE_UNINSTALL_SCAN_ROOT` fixture 根 + 隔离 HOME/meta cache）断言 JSONL 合法、身份行先于完整行、done 标记、bundle_id/uninstall_name/version/`last_used_epoch`(int)/size（字符串非 0），并已登记 `docs/blueprint/testing.md` test_cmd。三项独立实跑通过（见下）。
    - 上轮未进表提示的落实：`testQueueRunsEachItemOnceInOrderWithoutOverlap` 增补 `results[.uninstallList]` 断言；新增 `testCancelledItemIsRequeuedExactlyOnce`（`tests/unit/PrewarmTests.swift:35-63`）以「阻塞安装包列表→写入取消→释放租约」断言取消项精确重跑一次（安装包列表 2 次、总 6 次、200ms 稳定窗），对应队列去重修复（`PrewarmService.swift:109-115`）。
- 本轮独立复跑：`xcodebuild test` 236 例 0 失败；四个相关测试类隔离重跑 27 例通过；`tests/integration/uninstall_stream_test.sh`、`installer_interface_test.sh`、`clean_trash_test.sh` 全过；`pytest .repo_template/tests -q -m contract` 147 过。
- 本轮新发现：1 条。

### t029_test_f004 - AC-005/范围文本变更未见用户确认记录（契约区 drift）

- 严重度：important

- 锚点：本轮「契约区 drift 警告」——未经用户确认的 AC 变更按 blocking 处理；变更面为 AC-005 的确认前核对义务

- 位置：`docs/tasks/t029_uninstall_list_progressive/spec.md:19,63`（相对 anchor：范围句与 AC-005 由「路径、bundle id、卸载名」改为「路径或 bundle id……卸载名变化不在确认前复核」）；变更来源 `docs/tasks/t029_uninstall_list_progressive/task.md:45`（t029_code_f004 处置）

- 问题：契约区自 diff_anchor 以来的唯一变更删除了「卸载名变化须在确认前拒绝」的验收义务。可查记录中该变更源自代码评审 f004 的建议并被标记「已修（改 spec）」，但 task.md、spec 说明与 handoff 均无用户对该 AC 文本变更的确认记录（Round 2 派审说明亦未提及）。按本轮 drift 规则应作 blocking。技术方向本身可辩护（不重扫无法轻量复核卸载名，AC-004 又禁止重扫；实现、architecture.md、ui_contract.md 已一致），但 AC 是验收契约，减义务的文本变更需要用户背书后才可按新文本判定 PASS。

- 建议：由用户在 adoption 明确批准该措辞并在 task.md note/处置记录留痕（随后可撤回本 finding），或恢复原 AC-005 文本并在 `docs/blueprint/decisions.md` 记录「卸载名不参与确认核对」的取舍再走改 spec 流程；二者任一完成即可解除阻断。

- 改测方向复核：本轮两处既有测试修改——`BatchUninstallTests` 解码用例改直连 `JSONDecoder`（随 `UninstallListDecoder` 死代码删除）、`testSearchFilterHidesRowButKeepsSelection` 改用 `visibleListings`（随 `UninstallListFilter.visible` 删除）——均为「迁移到存活的生产 API」，JSON/断言语义未变，非迁就实现；新增测试无弱化断言、无条件跳过、无静默错误；未发现新的危险模式命中。

- AC 复验方式（本轮重跑 236 例 + 三组 shell 集成 + pytest contract）：

    - AC-001：re_verified（渐进行单测 + 真实脚本断言身份行先出；size 后续为非 0 字符串）
    - AC-002：re_verified（真实脚本完整行含 `version` 与 int `last_used_epoch`；`NSMetadataItem` 全仓零命中）
    - AC-003：re_verified（图标 gate 测试；滚动为 UI 行为，无渲染测试）
    - AC-004：re_verified（调用序列无 `--list`；变更路径重扫恰 1 次）
    - AC-005：re_verified（真实 checker 四分支 + 拒绝/重扫流程；AC 文本变更的确认问题见 f004）
    - AC-006：re_verified（未点击时进程调用为空）
    - AC-007：re_verified（无确认不 spawn 非 dry-run uninstall）
    - AC-008：re_verified（listCalls==1；scan-disabled 集成实跑删除成功）
    - AC-009：re_verified（集成 size/identity 变更拒绝实跑）
    - AC-010：re_verified（选择 ⊆ 名单 + 重扫后不可删除；守卫删除后行为由构造保证）
    - AC-011：re_verified（未确认零删除两例）
    - AC-012：re_verified（精确顺序/单并发 + exactly-once 回归）
    - AC-013：re_verified（无租约断言 + 写入即时取租约并取消预跑）
    - AC-014：re_verified（四页 adopt + capturedAt；时间文本为视图代码查证）
    - AC-015：re_verified（作废重跑 + 确认保护）
    - AC-016：re_verified（黑名单 + 精确命令表）
    - AC-017：re_verified（userDidRescan 丢弃 + 各页自行扫描）
    - AC-018：re_verified（service 级活动阻断；`isScanning`/装配订阅仍无直接测试——见提示）
    - AC-019：re_verified（demo prewarmService == nil）
    - coverage = 19 / 19（trust_prior 0）

- 未进表的提示：

    - `performList` 的新裁剪逻辑（`UninstallViewModel.swift:134-142`，重扫后丢弃未再出现的行，code f006 修复）无直接单测，可从 changedTarget 重扫场景扩展。
    - `uninstall_stream_test.sh` 目前只有单应用 fixture，可选加多应用/无候选/malformed 行用例。
    - `AnalyzeViewModel.isScanning` 与 `AppDependencies` 的订阅/Provider 装配（含 clean `isPreviewing` 并入）仍无测试，属装配层缺口。
    - `BatchUninstallTests` 用例名 `testDecoderKeepsSourceAndParsesHumanSize` 直连 JSONDecoder 后可考虑更名（命名，小事）。

- 总体判断：Round 1 三条 important 全部真修且经独立复跑确认，测试证据链已补齐并新增 exactly-once 回归；唯一未决项为 AC-005 文本变更缺用户确认（f004），依 drift 规则 blocking，待用户背书后即可复审转 PASS。

- 系统性 follow-up：无。

reviewed_scope: 966025fc156710b2

verdict: FAIL

## Round 3 (2026-10-17T02:58:34+08:00)

- 前轮 finding 复核与撤回（以 `git -C … diff ab664ca…`、当前代码/测试与独立重跑为准，不采信处置表自述）：
    - **撤回记录 t029_test_f004**（finding_id + 撤回理由）：撤回理由成立。用户 2026-10-17 在会话中明确批准 AC-005/范围文本变更（确认前只核对路径与 bundle id；卸载名变化由预览/执行命令自身失败暴露），批准记录见 `docs/tasks/t029_uninstall_list_progressive/task.md` Round 2 处置表 `t029_test_f004` 行；本轮契约区 drift 警告要求的「经用户确认」条件满足，新文本即当前验收基准。按共享规则「撤回配合」关闭该 finding，不再阻断，后续不属未解决 important。
    - t029_test_f001 / f002 / f003：Round 2 已核实消除（真实 checker 四分支 / 不可达守卫删除与测试改写 / `init(streaming:)` 装配与真实脚本契约测试），本轮对应文件与断言无新增改动，复核结论维持「已消除」。
    - t029_code_f009（code 轴，本轮指定复核其新增测试断言）：**断言真实**。`testUninstallChangedTargetCannotExecuteAndRescansTheList`（`tests/unit/UninstallTests.swift:167-169`）新增两条：`listings.map(\.path).count == Set(listings.map(\.path)).count`（重扫后无重复 path）与 `listings.count == 1`（重扫整体替换名单）。对照修复前逻辑（fresh `indexByPath` 把行合并进旧 `listings`，同 path 会残留旧行并追加新行 → 2 行重复），该断言必失败，确能捕获 f009 回归；修复后 `performList` 在局部 `merged` 上合并并逐行整体赋值（`src/zmole/Features/Uninstall/UninstallViewModel.swift:114-137`），渐进发布与裁剪（selected/related/icons ∩ seenPaths）语义保持，`UninstallStreamProgressTests.testListingsAppearBeforeSizesFinish` 等先行断言不受影响（全量 236 例通过）。该用例已隔离重跑通过。
- 本轮独立复跑：`xcodebuild test` 236 例 0 失败；`tests/integration/uninstall_stream_test.sh`、`installer_interface_test.sh`、`clean_trash_test.sh` 全过；`pytest .repo_template/tests -q -m contract` 147 过。
- 本轮新发现：0 条。
- 改测方向复核：本轮对既有测试的改动仅为在该用例上追加两条断言（加强，无删除/弱化/反转/条件跳过）；无「迁就实现」改测；`tests/` 复核无 `.skip`/`.only`/`@Ignore`/静默错误/恒真断言等新增危险模式。
- AC 复验方式（本轮重跑 236 例 + 三组 shell 集成 + pytest contract）：
    - AC-001：re_verified（渐进单测 + 真实脚本契约；复跑通过）
    - AC-002：re_verified（真实脚本 version/int `last_used_epoch`；`NSMetadataItem` 全仓零命中）
    - AC-003：re_verified（图标 gate 测试；滚动为 UI 行为，无渲染测试）
    - AC-004：re_verified（调用序列无 `--list`；重扫断言名单整体替换、无重复）
    - AC-005：re_verified（真实 checker 四分支 + 拒绝/重扫；文本变更已经用户批准，f004 撤回）
    - AC-006：re_verified（未点击零调用）
    - AC-007：re_verified（无确认不 spawn 非 dry-run uninstall）
    - AC-008：re_verified（listCalls==1 + scan-disabled 集成实跑）
    - AC-009：re_verified（集成 size/identity 变更拒绝实跑）
    - AC-010：re_verified（选择 ⊆ 名单 + 重扫后不可删除）
    - AC-011：re_verified（未确认零删除）
    - AC-012：re_verified（精确顺序/单并发 + exactly-once 回归）
    - AC-013：re_verified（无租约断言 + 写入即时取租约并取消预跑）
    - AC-014：re_verified（四页 adopt + capturedAt；时间文本为视图代码查证）
    - AC-015：re_verified（作废重跑 + 确认保护）
    - AC-016：re_verified（黑名单 + 精确命令表）
    - AC-017：re_verified（userDidRescan 丢弃 + 各页自行扫描）
    - AC-018：re_verified（service 级活动阻断；`isScanning`/装配订阅仍无直接测试——提示）
    - AC-019：re_verified（demo prewarmService == nil）
    - coverage = 19 / 19（trust_prior 0）
- 未进表的提示：
    - changedTarget 重扫断言现为单应用 fixture；可扩为多应用（含重扫中消失的 app）以同时覆盖「整体替换 + 裁剪」。
    - `AnalyzeViewModel.isScanning` 与 `AppDependencies` 订阅/Provider 装配仍无直接测试（装配层，非本 task 阻断）。
    - `uninstall_stream_test.sh` 单应用 fixture，可加无候选/malformed/多应用边界用例。
    - `BatchUninstallTests` 用例名可随实现（直连 `JSONDecoder`）更新。
- 总体判断：Round 1/2 的全部 blocker 均已修复，或（f004）已由用户明确背书并撤回；本轮新增断言真实有效，独立复跑全绿，测试轴无未解决 critical/important，可 PASS。
- 系统性 follow-up：无。

reviewed_scope: e23ac1b75ca4593f

verdict: PASS

## Round 4 (2026-10-17T03:02:13+08:00)

- 前轮闭合项回归复核（以 diff/代码/独立重跑为准）：
    - t029_test_f001 / f002 / f003：无回归，维持「已消除」；对应测试（UninstallTargetCheckerTests、testSelectionCannotOutliveItsSessionList、UninstallStreamingAssemblyTests、uninstall_stream_test.sh）本轮无改动且全量复跑通过。
    - t029_test_f004：维持 Round 3 撤回结论（用户批准 AC-005 文本变更，记录在 task.md Round 2 处置表）；本轮契约区未见再次变更（drift diff 与 Round 3 相同），无需动作。
    - t029_code_f009 的测试侧证据：`testUninstallChangedTargetCannotExecuteAndRescansTheList` 的「无重复 path / 名单整体替换」断言本轮无改动，复跑通过，未因 f011 修复而失效或弱化。
- 本轮改动（code f011）复核：`performList` 抽出 `pruneSessionState(to:)`（`src/zmole/Features/Uninstall/UninstallViewModel.swift:155-160`）并在成功与取消两条路径结束处统一调用（:117-152，busy/其余错误路径仍 early-return 不裁剪）。逐行核对：取消路径上 `listings = merged` 已随行整体替换，裁剪 `selectedPaths/relatedLoadedIDs/relatedPathsByID/iconsByPath` 到本次流到的 path 与可见名单一致，属一致性对齐，无破坏性路径暴露；无测试文件在本轮被修改（`git diff --stat` 测试计数与 Round 3 完全一致），既有断言无删除/弱化/反转。
- 裁剪行为是否需要测试——本轮判断：**不构成 blocker，列为可选覆盖扩展**。理由：（1）19 条 AC 均未锚定「卸载名单扫描取消后的会话状态」；（2）残留选中不足以造成误删——预览/执行前仍经 `UninstallSelectionValidator`（`selected.count != selectedIDs.count` → changedTarget）与 `LiveUninstallTargetChecker` 双重兜底；（3）成功路径的「名单整体替换」已有 f009 断言，取消路径裁剪为同一 helper 的一致性行为，故障模式仅为自己可恢复的 changedTarget 提示。建议（非阻断）：用多应用 fixture 补一例「重扫/取消后消失的 app 从 listings 与选中集裁剪」，可用现有 `AsyncGate`/`CountingListStream` 注入。
- 本轮独立复跑：`xcodebuild test` 236 例 0 失败；`tests/integration/uninstall_stream_test.sh`、`installer_interface_test.sh`、`clean_trash_test.sh` 全过；`pytest .repo_template/tests -q -m contract` 147 过。
- 本轮新发现：0 条。
- 改测方向复核：本轮无测试改动，「迁就实现」改测不适用；危险模式扫描：`tests/` 无 `.skip`/`.only`/`@Ignore`/静默错误/恒真断言/条件跳过等命中（无新测试代码进入）。
- AC 复验方式（本轮重跑 236 例 + 三组 shell 集成 + pytest contract）：
    - AC-001：re_verified（渐进单测 + 真实脚本契约；复跑通过）
    - AC-002：re_verified（真实脚本 version/int `last_used_epoch`；`NSMetadataItem` 全仓零命中）
    - AC-003：re_verified（图标 gate 测试；滚动为 UI 行为，无渲染测试）
    - AC-004：re_verified（调用序列无 `--list`；重扫断言名单整体替换、无重复）
    - AC-005：re_verified（真实 checker 四分支 + 拒绝/重扫；文本变更已经用户批准）
    - AC-006：re_verified（未点击零调用）
    - AC-007：re_verified（无确认不 spawn 非 dry-run uninstall）
    - AC-008：re_verified（listCalls==1 + scan-disabled 集成实跑）
    - AC-009：re_verified（集成 size/identity 变更拒绝实跑）
    - AC-010：re_verified（选择 ⊆ 名单 + 重扫后不可删除）
    - AC-011：re_verified（未确认零删除）
    - AC-012：re_verified（精确顺序/单并发 + exactly-once 回归）
    - AC-013：re_verified（无租约断言 + 写入即时取租约并取消预跑）
    - AC-014：re_verified（四页 adopt + capturedAt；时间文本为视图代码查证）
    - AC-015：re_verified（作废重跑 + 确认保护）
    - AC-016：re_verified（黑名单 + 精确命令表）
    - AC-017：re_verified（userDidRescan 丢弃 + 各页自行扫描）
    - AC-018：re_verified（service 级活动阻断；`isScanning`/装配订阅仍无直接测试——提示）
    - AC-019：re_verified（demo prewarmService == nil）
    - coverage = 19 / 19（trust_prior 0）
- 未进表的提示：
    - 【可选覆盖扩展】重扫/取消后消失 app 的裁剪断言（多应用 fixture，见上）；`uninstall_stream_test.sh` 可加无候选/malformed/多应用边界。
    - `AnalyzeViewModel.isScanning` 与 `AppDependencies` 订阅/Provider 装配仍无直接测试（装配层，非本 task 阻断）。
    - `BatchUninstallTests` 用例名可随实现（直连 `JSONDecoder`）更新。
- 总体判断：f011 为生产侧一致性修复，测试面零改动、闭合项无回归，独立复跑全绿；裁剪行为判断为可选覆盖而非阻断项，测试轴无未解决 critical/important，维持 PASS。
- 系统性 follow-up：无。

reviewed_scope: 4cd8a9b2eaaa5528

verdict: PASS

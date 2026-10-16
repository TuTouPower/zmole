# Task review t021（reviewer_focus: test）

- task: t021_optimize_purge_pages（优化页与项目清理页）
- spec: `docs/tasks/t021_optimize_purge_pages/spec.md`
- diff_anchor: `e0a077092a195a016ba55ee18facf378244d6272`
- target: `git -C '/Users/karson/kar/code/zmole_t021' diff e0a077092a195a016ba55ee18facf378244d6272`（new files intent-to-add，非 `...HEAD`）
- round: 1
- reviewed_at: 2026-10-16T20:00:00+08:00

## 验证记录

- `xcodebuild test -scheme Zmole -destination 'platform=macOS'` → 159 passed，0 failures。其中新 `ZmoleTests/OptimizePurgePageTests` 6 例全绿（`-only-testing` 复核）。
- `pytest .repo_template/tests -q -m contract` → 147 passed，367 deselected。
- 危险模式扫描：新增测试只用临时目录（`temporaryDirectory` + UUID）与假 `MoleProcessControlling`（`MaintenanceSpy` 固定返回 `would run`）；`PurgePathsStore` 走注入 `fileURL`，不写 `~/.config/mole/purge_paths`；无真实删除、无网络、无越界写入、无 sleep 竞态。未见危险模式。
- 复现方法：把 `OptimizePlanParser` 分隔/判定逻辑抽成脚本，喂入仓内真实样本 `docs/spikes/s001_mole_cli_fixtures/samples/optimize_dry_run.txt`（mole V1.55.0），逐行打印分类结果（见 f001）。

## Findings

### t021_test_f001 - AC-002/AC-003 fixture 为自造格式，与真实优化 dry-run 输出不符，绿灯不成立

- 严重度：important
- 锚点：`tests/unit/OptimizePurgePageTests.swift:42-53`、`src/zmole/Features/Optimize/OptimizePlan.swift:19-56`、`docs/spikes/s001_mole_cli_fixtures/samples/optimize_dry_run.txt`
- 位置：`tests/unit/OptimizePurgePageTests.swift`
- 问题：`testOptimizePlanMapsSkipReasonsAndDeletionRows` 的输入是自造的 `name: detail` 文本：
    ```
    DNS cache flush: would run
    Orphaned LaunchAgent: skipped, binary missing (would remove plist)
    Spotlight index: skipped, reason: index busy
    ```
    但 `preview.output` 来自 `MaintenanceOutput.summary(stdout:)`（`src/zmole/Features/MaintenanceOutput.swift:4`），只剥 ANSI，parser 收到的是 mole 原始文本。仓内已记录真实 V1.55.0 样本（`samples/optimize_dry_run.txt`），格式为 `➤ 段名` 段头 + `  → 描述` 行，无 `" — "`/`" - "`/`": "` 分隔符。把 parser 逻辑对真实样本逐行复跑，结果：
    - `→ Periodic maintenance skipped (not available on this macOS version)` → `willRun`、`reason` 为空（应为跳过且有原因）。
    - `→ Disk verify skipped (set MOLE_ENABLE_DISK_VERIFY=1 to enable)` → `willRun`、reason 空。
    - `→ Login items audit · skipped in test mode`、`- Notification Center database unavailable (...)` → 均 `willRun`、无原因。
    - 全部真实样本行 `deletesFiles == false`（真实文本无 `remove/delete/plist/launchagent` 子串，标记 `launchagent` 连写，真实为 `Launch Agents` 带空格）。
    - 段头 `➤ DNS & Spotlight Check` 与汇总行 `12 unchanged | 3 skipped | 2 unavailable` 都被当作任务行。
        即测试用例断言的是 parser 对自己手写格式的映射，期望值与被测实现同源（类似 t018_test_f003 的自指），一旦换真实输入即全线误判。AC-002（跳过原因出现在对应任务行）与 AC-003（会删文件任务有永久删除说明）在真实输入下均不成立，而测试全绿给出虚假信心。spec「可测试性声明」写 AC-001–007 可自动断言、未知契约清单写「无」，与事实不符——优化文本格式本身是未核实外部契约（finding d001 已记录「optimize dry-run 为文本」）。
- 建议：以仓内 `samples/optimize_dry_run.txt` 为 fixture 断言 parser 输出（真实跳过行 → `.skip` 且 reason 非空；段头/汇总行被过滤；真实删除行标注 deletesFiles）。若现有 parser 无法通过，则 parser 与 fixture 必须一起改到能匹配真实输出，而非迁就 fixture。

### t021_test_f002 - AC-003 行级「永久删除」文案从未断言

- 严重度：minor
- 锚点：`src/zmole/Features/Optimize/OptimizeView.swift:146`、`src/zmole/Resources/Localizable.xcstrings`（`optimize.row_deletes_permanently`）
- 位置：`tests/unit/OptimizePurgePageTests.swift:98-110`
- 问题：AC-003 要求「会删除文件的优化任务有可见的永久删除说明」。行上角标渲染 `optimize.row_deletes_permanently`（值「永久删除」），但 `testPermanentDeletionCopyUsesPermanentWording` 只校验页面级 `optimize.permanent_note` 与 `purge.permanent_note` 两键，未包含行级键。行级角标文案删除或改错都不会被捕获。
- 建议：把 `optimize.row_deletes_permanently` 纳入 `testPermanentDeletionCopyUsesPermanentWording` 的键列表（或单独断言）——该键可测，不受 GUI blackbox 限制。

### t021_test_f003 - AC-002 后半「无预览时不标成已执行」无断言

- 严重度：minor
- 锚点：`src/zmole/Features/Optimize/OptimizeView.swift:9-12`
- 位置：`tests/unit/OptimizePurgePageTests.swift`
- 问题：AC-002 含两半：(a) 跳过原因映射到任务行；(b) 没有预览时不把任务标成已执行。parser 的 `OptimizeRowStatus` 只有 `willRun`/`skip`，视图 `rows` 在 `preview == nil` 时返回 `[]`（显示空状态），(b) 结构上暂无「已执行」态，但无任何断言锁定这一行为。若日后新增态或视图改为无预览也渲染行，(b) 静默失效。
- 建议：对 `rows`/状态枚举加负向断言（如无 preview 时 `rows.isEmpty`，或断言状态集合不含 executed 语义），成本低。

### t021_test_f004 - AC-001 用例含自指冗余断言

- 严重度：minor
- 锚点：`tests/unit/OptimizePurgePageTests.swift:16-17`
- 位置：`tests/unit/OptimizePurgePageTests.swift`
- 问题：`testOptimizeArgsNeverIncludeSelectedTaskSubset` 先精确断言 `invocations == [["optimize","--dry-run"],["optimize"]]`，其后 `XCTAssertFalse(invocations.contains { $0.count > 1 && !$0.contains("--dry-run") })` 在前一断言成立时恒真，不提供独立信号。该用例亦与既有 `OptimizeTests.testOptimizeConfirmationExecutesWithoutDryRun` 大面积重复，未带来增量覆盖。
- 建议：删除冗余断言；若要专门表达「argv 不含子集」，改为对执行调用做参数集合断言并配注释，或直接复用既有用例。

## 结论

- 本轮新发现：4 条（0 critical / 1 important / 3 minor）。
- AC 覆盖：
    - AC-001：充分（`testOptimizeArgsNeverIncludeSelectedTaskSubset`，argv 无子集；断言冗余见 f004）。
    - AC-002：不足（f001 真实输入误判；f003 后半未测）。
    - AC-003：不足（f001 deletesFiles 在真实样本恒 false；f002 行级永久删除文案未断言）。
    - AC-004：充分（`testPurgeUsesYesAndCancelDoesNotExecute`，`purge --yes` 且无子集）。
    - AC-005：充分（同用例取消后 argv 仍只有 dry-run）。
    - AC-006：充分（`testPurgePathsStoreRoundTripAndValidation`、`testPurgePathsViewModelKeepsTextOnInvalidSave`，临时路径，非法保存保留编辑内容）。
    - AC-007：充分（`testPermanentDeletionCopyUsesPermanentWording` 校验两页 `permanent_note` 含「永久删除」且不含「移入废纸篓」；行级键缺测见 f002）。
- 未进表的提示：`PurgePathsEditorView`（sheet 编辑器）无任何测试，属 GUI；按约定不作为 blackbox 门禁。AppDependencies 未加「demo 模式 purge_paths 落 demo 目录、非 demo 落真实配置」的断言，但测试均注入临时 `fileURL`，无写开发者真实配置风险。
- 红绿灯归属：门禁全绿（159 / 147），无失败测试可归因；f001 属「绿灯不可信」——AC-002/003 的绿灯建立在自造 fixture 上，不能据此判定 AC 达成。
- 总体判断：argv 类 AC（001/004/005）与配置类 AC（006/007）测试可信；但优化计划解析是本 task 的核心（AC-002/003），其测试 fixture 与仓内记录的真实 mole V1.55.0 输出不符且已被证实对真实输入误判，属重要验证缺口，本轮不得 PASS。

verdict: FAIL

### Round 2 (2026-10-16T20:10:00+08:00)

#### 处置确认

|finding_id|severity|status|rationale|fix_ref|
|---|---|---|---|---|
|t021_test_f001|important|已修|新增 `testOptimizePlanParsesRealDryRunSample`，直接读入仓内真实样本 `docs/spikes/s001_mole_cli_fixtures/samples/optimize_dry_run.txt`；配合生产 parser 重写为 `➤ 段名` + 缩进明细行解析。逐条断言：首行 `DNS & Spotlight Check` 且 `willRun`；`Periodic Maintenance` 为 `skip` 且 `reason` 含 `skipped`；`Launch Agents Cleanup` `deletesFiles == true`；段头/汇总行不成行。|tests/unit/OptimizePurgePageTests.swift:41-62；src/zmole/Features/Optimize/OptimizePlan.swift:39-77|
|t021_test_f002|minor|已修|新增 `testDeletionRowCopyStatesPermanentDeletion`，读取 `Localizable.xcstrings` 断言 `optimize.row_deletes_permanently` 的 zh-Hans 含「永久」。|tests/unit/OptimizePurgePageTests.swift:118-130|
|t021_test_f003|minor|已修|真实样本用例内断言 `OptimizePlanParser.rows(from: "")` 为空，锁定「无预览即无任务行（不标成已执行）」。|tests/unit/OptimizePurgePageTests.swift:60-61|
|t021_test_f004|minor|撤回|`XCTAssertFalse(invocations.contains { $0.count > 1 && !$0.contains("--dry-run") })` 在前一精确相等断言成立时确为冗余，但语义正确、无害，且显式记录了「执行 argv 不含任务子集」这一 AC 意图，非缺陷，不再列为遗留。|tests/unit/OptimizePurgePageTests.swift:17|

#### 甄别度复核

- f001 具甄别力：把重写后的 parser 逻辑对真实样本复跑（脚本化验证），结果为首行 `DNS & Spotlight Check`/`willRun`、`Periodic Maintenance`/`skip` 且 reason 含 `skipped`、`Launch Agents Cleanup`/`deletes=true`、`Optimize`/`Dry Run Complete…`/`12 unchanged | 3 skipped | 2 unavailable` 等段头与汇总行均不成行。旧 parser 在同一输入下首行是 `➤ DNS & Spotlight Check`、`Launch Agents Cleanup` `deletes=false`，新用例在旧实现上必失败——测试对真实契约有判别力，不再自指。
- f002 独立：从真实 `Localizable.xcstrings` 取行级键值，删改该键即失败。仅断言含「永久」而非「永久删除」，覆盖略宽，对 AC-003 足够。
- f003 独立：空输入断言不依赖 parser 内部同源推导，锁定负向行为。
- 新增 `testSavingScanDirectoriesInvalidatesPurgePreview`（超出原 finding，属加强）：`PurgePathsViewModel.save()` 现经共享写租约（`coordinator.acquire(.purge)`）并 `invalidatePreviews()`；用例断言保存后 `purgeViewModel.canConfirm == false` 且 `preview == nil`，覆盖「保存扫描目录使既有 purge 预览失效」这一写入租约约束，具甄别力（若不失效则 `canConfirm` 保持 true 而失败）。
- 残留 nit（不进表）：真实样本用例含 `$0.name.contains("WORLD")` 这一无对应数据的占位判断，无实际断言价值，但无害。

#### 门禁复跑

- `xcodebuild test -scheme Zmole -destination 'platform=macOS'` → 161 passed，0 failures。
- `pytest .repo_template/tests -q -m contract` → 147 passed，367 deselected。
- 危险模式扫描：新用例仍只用临时目录 + 假 `MoleProcessControlling`，真实样本仅只读读取；无真实删除、无网络、无越界写入、无 sleep 竞态。

#### 结论

- 本轮新发现：0 条。
- AC 覆盖（复核后）：AC-001 充分；AC-002 充分（真实样本跳过行映射 reason + 空输入无行）；AC-003 充分（真实样本 deletes 标记 + 行级永久删除文案）；AC-004/005 充分；AC-006 充分（含写入租约使预览失效）；AC-007 充分。round 1 的 f001/f002/f003 全部已修，f004 撤回，无遗留 critical/important。
- 红绿灯归属：全部门禁绿灯，无失败测试需归因；round 1 的「绿灯不可信」缺口已闭合。
- 总体判断：优化计划解析现以真实 mole V1.55.0 样本为 fixture，对生产 parser 有判别力；其余 AC 断言独立可测。测试可信度达标。

reviewed_scope: c74a861

verdict: PASS

### Round 3 (2026-10-16T20:20:00+08:00)

#### 变更范围

- 新增 `testOptimizePlanRecognizesCurrentSkipWording`（覆盖当前 mole 源码措辞：`Close these apps before database optimization`、`database is healthy`，外加一条 willRun 行）。
- 生产 `OptimizePlanParser.noOpMarkers` 相应扩两条：`"is healthy"`、`"close these apps before"`（`src/zmole/Features/Optimize/OptimizePlan.swift:21-25`）。

#### 处置确认

|finding_id|severity|status|rationale|fix_ref|
|---|---|---|---|---|
|t021_test_f001|important|已修（round 2）|无回归；真实样本用例仍绿。|tests/unit/OptimizePurgePageTests.swift:41-62|
|t021_test_f002|minor|已修（round 2）|无回归。|tests/unit/OptimizePurgePageTests.swift:134-146|
|t021_test_f003|minor|已修（round 2）|无回归。|tests/unit/OptimizePurgePageTests.swift:60-61|
|t021_test_f004|minor|撤回（round 2）|维持。|—|

本轮无 finding 待处置。

#### 甄别度复核

- 新用例具甄别力：生产 noOpMarkers 未加 `is healthy`/`close these apps before` 时，rows[0]（`Database Optimization`）与 rows[1]（`Notifications`）会落 `willRun`，两条 `XCTAssertEqual(status, .skip)` 必失败；加了才绿。用例对被测行为有判别力，非自指。
- 措辞保真：新 fixture 文本与仓内 mole 源码一致——`src/zmole/Resources/mole/lib/optimize/tasks.sh:572`（`Close these apps before database optimization: ...`）、`:1485`（`Notification Center database is healthy (...)`）。逐条复跑新 parser 逻辑，输出 `Database Optimization`/skip+reason、`Notifications`/skip、`Launch Services Repair`/willRun，与断言相符。
- 无回归：`is healthy` 未误伤真实样本中的 `Launch Agents all healthy`（仍由 `all healthy` 命中），真实样本用例维持绿。

#### 门禁复跑

- `xcodebuild test -scheme Zmole -destination 'platform=macOS'` → 162 passed，0 failures。
- `pytest .repo_template/tests -q -m contract` → 147 passed，367 deselected。
- 危险模式扫描：新用例纯字符串输入、无 I/O；无真实删除、无网络、无越界写入。

#### 结论

- 本轮新发现：0 条。
- AC 覆盖（复核后，维持）：AC-001–007 全部充分，断言独立可测。
- 红绿灯归属：全部门禁绿灯，无失败测试需归因。
- 总体判断：新增措辞用例与源码对齐、对生产 parser 有判别力，round 1/2 结论无回归，测试可信度达标。

reviewed_scope: eeb3d26

reviewed_scope: 89a2686a8650fc3e

verdict: PASS

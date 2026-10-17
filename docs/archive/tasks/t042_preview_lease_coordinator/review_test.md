# Task review t042（reviewer_focus: 测试）

- task：`t042_preview_lease_coordinator`
- spec：`docs/tasks/t042_preview_lease_coordinator/spec.md`
- diff_anchor：`166a65b5f4492efb2506f901fd66c87f2044aaed`
- target：`git -C '/Users/karson/kar/code/zmole_t042' diff 166a65b5f4492efb2506f901fd66c87f2044aaed`
- round：1
- reviewed_at：2026-10-17T15:04:12+08:00

## Findings

### t042_test_f001 - AC-001 结构断言未覆盖 isCurrentPreview / operationID(for:) 命名重复项

- 严重度：minor
- 锚点：AC-001（三文件不含 `isCurrentPreview`/`releaseLease`/`operationID(for:)` 私有重复实现）
- 位置：`tests/unit/CommandConcurrencyTests.swift:112-130`
- 问题：结构测试只 grep 了 `private func releaseLease(clearPreviewGeneration`、`previewCoordinatorGeneration`、`coordinator.$invalidationGeneration.sink` 三类样板。AC-001 点名的另两处命名重复（私有 `isCurrentPreview`、`operationID(for:)`）无对应负断言：回归若以私有 `isCurrentPreview` 或 `operationID(for:)` 复活（前者可写成只转发 `leaseCoordinator.isCurrentPreview`，绕过 `previewCoordinatorGeneration` 检查），全量测试仍绿。当前实现已删除（独立 rg 三文件仅剩 `leaseCoordinator.isCurrentPreview` 调用点，无 `operationID(for`、无 `private var lease`），即断言面小于 AC 点名面，非假绿。
- 建议：负断言列表补 `private var isCurrentPreview` 与 `operationID(for:` 两条（直接 grep `isCurrentPreview` 会误伤转发调用点，须带 `private var` 前缀）。

### t042_test_f002 - AC-003 uninstall 腿无既有用例覆盖，而迁移重写了该订阅路径

- 严重度：minor
- 锚点：AC-003（「既有用例覆盖」三页面失效过期）；行为缺陷场景：迁移后 uninstall 失效回调漏接也无人发现
- 位置：`src/zmole/Features/Uninstall/UninstallViewModel.swift:49-53`；`tests/unit/UninstallTests.swift`、`BatchUninstallTests.swift`、`UninstallDetailTests.swift` 均无外部失效用例
- 问题：AC-003 声称既有用例覆盖三页面，实测只有两腿——clean：`CleanPageTests.testProtectingPathInvalidatesCurrentPreview:197`；maintenance（purge 代 opt/purge 共同基类）：`OptimizePurgePageTests.testSavingScanDirectoriesInvalidatesPurgePreview:119`。没有任何测试在 uninstall 预览就绪后由外部写/`invalidatePreviews()` 触发过期（全套 `rg` 无 UninstallViewModel + 共享 coordinator 的另一写方组合）。本 task 恰好把 UninstallViewModel 的订阅从 `expirePreviewIfNeeded` 搬进 `leaseCoordinator.onInvalidation`（`:49-53`）：若该闭包未赋值或恒返回 false，行为回归，而结构测试与 282 条全量用例都不会红。属既有覆盖缺口被本次迁移放大（本次未删除任何覆盖）。
- 建议：补一条用例：共享 coordinator 上 uninstall 预览就绪 → 另一写方（或 `coordinator.invalidatePreviews()`）→ 断言 `preview == nil`、`canConfirm == false`；若不补测，须在 AC-003 显式标注该腿为代码等价比对（非测试证据）。

### t042_test_f003 - 新交付文件未 git add -N，不在派审 diff 中

- 严重度：minor
- 锚点：review 协议「实施方派审前须对明确的新交付文件执行 git add -N，让它们同时出现在 reviewer 的 git diff 中」
- 位置：`src/zmole/Features/Operations/PreviewLeaseCoordinator.swift`（`git status --short` 显示 `??`，`git diff 166a65b5…` stat 与正文均不含该文件）
- 问题：共享组件本体是本次核心交付，却不在指定 diff 命令的输出内；任何仅按 `git diff <anchor>` 取数的 Reviewer/工具会漏看它（含其内含的 `PreviewOperationID.from` 与失效回调协议）。本轮已通过 `git status --short` 发现、全文读取并纳入审查；`reviewed_scope` 指纹按含 untracked 交付文件的完整 worktree 计算且与注入值一致，故未触发 INCOMPLETE。
- 建议：下一轮（若有）派审前先执行 `git add -N src/zmole/Features/Operations/PreviewLeaseCoordinator.swift`。

## 结论

- 前轮 finding 复核：Round 1，无。
- 改测方向复核：无。测试改动仅为新增 `testWriteViewModelsShareThePreviewLeaseCoordinator`（`tests/unit/CommandConcurrencyTests.swift:102-136`，+36 行，文件无删行）；全套件内既有断言/用例无任何修改、删除或弱化，无「迁就实现」的改测。
- 本轮新发现：3 条（均 minor）。
- 未进表的提示：
  - 危险模式逐条扫描 7 视角 0 命中：无恒真断言、删/反转 expect、注释断言、弱化断言、`.skip`/`.only`、类型/lint 抑制、mock 误用（新测试不 mock；既有 spy 为迁移前存量）、阈值掩盖、条件跳过、`.value =` 替代交互。结构测试的 `contains("PreviewLeaseCoordinator(")` 属 AC-001 声明的源码结构断言（可测试性声明原文「grep 私有重复定义消失、共享类型存在」），且与 4 条负断言 + 行为回归套件共同构成证据，不按「存在即通过」计。
  - 本轮复算 reviewed_scope 指纹与注入值一致（85d4d588605b1e85），untracked 交付文件已计入并已全文审查 → 不判 INCOMPLETE（f003 仅记流程偏差）。
  - 范围外观察：`PrewarmService.swift` 与 `OverviewViewModel.swift` 同样订阅 `invalidationGeneration`，用途为预暖重排/概览缓存，不在 spec 声明的三个写路径 VM 内，不进本表。
  - 覆盖扩展（不进表）：`PreviewOperationID.from` 无专测，由 confirm 流程用例间接触达（Clean/Uninstall 的 confirm 用例会红即证明可达），可接受。
- 总体判断：迁移为等价重构，行为回归由既有套件全量复验（282/282 绿）与三集成脚本独立重跑支撑；无未解决 critical/important，仅 3 条 minor → PASS。
- AC 复验方式：
  - AC-001 re_verified：重跑 `-only-testing:ZmoleTests/CommandConcurrencyTests` 7/7 通过（含新结构测试 `testWriteViewModelsShareThePreviewLeaseCoordinator`，0.005s passed）；独立 rg 三 VM 无 `previewCoordinatorGeneration` / `private func releaseLease` / `private var isCurrentPreview` / `operationID(for`，共享类型在 `PreviewLeaseCoordinator.swift:9`；断言面缺口见 f001。
  - AC-002 re_verified：`xcodebuild test -scheme Zmole -destination 'platform=macOS'` → `Test Suite 'ZmoleTests.xctest' passed`，`Executed 282 tests, with 0 failures`，`** TEST SUCCEEDED **`；10 个指定 suite 逐个 passed（CommandConcurrency 7、RecoverableBusy 3、CleanPage 12、CleanPreviewStore 5、Uninstall 10、UninstallDetail 13、BatchUninstall 5、Optimize 7、Purge 7、OptimizePurgePage 9）。
  - AC-003 re_verified（clean/maintenance 两腿）：重跑 `CleanPageTests.testProtectingPathInvalidatesCurrentPreview` 与 `OptimizePurgePageTests.testSavingScanDirectoriesInvalidatesPurgePreview` 通过；uninstall 腿无测试，仅代码审读（见 f002）。
  - AC-004 re_verified：全量 xcodebuild test 通过；三条集成脚本独立重跑退出码均 0——`clean_trash_test.sh`（8/8 ok）、`installer_interface_test.sh`（15/15 ok）、`uninstall_stream_test.sh`（7/7 ok），均输出 all cases passed。
  - coverage = 4/4 re_verified（trust_prior 0；AC-003 uninstall 腿的测试覆盖缺口见 f002，不计入 trust_prior）。
- 系统性 follow-up：无等价 task（`task.py list` 只读核对无匹配）。若 f002 本轮不补测，建议立 non-blocking follow-up：「补 uninstall 预览外部失效用例」，slug 建议 `uninstall_preview_invalidation_coverage`。

reviewed_scope: 85d4d588605b1e85

verdict: PASS

## Round 2 (2026-10-17T16:23:30+08:00)

### 前轮 finding 复核（以 diff/代码为准，不采信处置表自述）

- **t042_test_f001 已消除**。`tests/unit/CommandConcurrencyTests.swift:130-137` 新增 `private var isCurrentPreview` 与 `private func operationID(for` 两条负断言，仍对三 VM 逐个断言（结构测试现为 `102-144`）。独立 rg 五类模式对 CleanViewModel / UninstallViewModel / MaintenanceOperation 零命中（exit=1，断言与现状一致）；转发调用点（`CleanViewModel.swift:60`、`MaintenanceOperation.swift:72`、`UninstallViewModel.swift:77` 的 `leaseCoordinator.isCurrentPreview`）与 VM 内 `operationID` 局部变量不会被 `private ...` 前缀断言误伤。非「换形式弱化」：新断言以字面形式覆盖 AC-001 点名的私有重复项，负断言面补齐。
- **t042_test_f002 已消除**。`tests/unit/UninstallDetailTests.swift:196-210` 新增 `testAnotherWriteInvalidatesAnUninstallPreview`：真实 `OperationCoordinator` + 真实 `UninstallViewModel`（仅系统边界 `DetailProcessSpy` 替身）；先断言 `canConfirm == true`，再 `coordinator.invalidatePreviews()`（生产同源 API，InstallersViewModel.swift:160 / PurgePaths.swift:110 / WhitelistViewModel.swift:130 等真实写方均调用它），随后断言 `preview == nil`、`canConfirm == false`。链路真实：订阅 `PreviewLeaseCoordinator.swift:22` → VM `onInvalidation`（`UninstallViewModel.swift:51-55`）→ `session.expirePreview`（`OperationSession.swift:138-147`，ready/confirming→failed 使 preview 变 nil）；若订阅缺失或闭包恒 false，`XCTAssertNil(viewModel.preview)` 必红，非假绿。`makeViewModel` 新增 `coordinator` 可选参数不改变既有调用语义（其余调用点未传该参），无断言弱化。
- **t042_test_f003 已消除**。`git status --short` 中 `src/zmole/Features/Operations/PreviewLeaseCoordinator.swift` 现为 intent-to-add（` A`），本轮 `git diff 166a65b5…` 已含该文件（+85），共享组件本体进入派审 diff 取数面。

### 本轮新发现

0 条。两处修复全部为新增测试断言 / 新增用例 + index 标记：无删改既有断言、无危险模式命中（恒真断言、删/反转 expect、注释断言、弱化断言、`.skip`/`.only`、类型/lint 抑制、mock 误用、阈值掩盖、条件跳过、`.value =` 替代交互均未出现）。

### 本轮复验证据（独立重跑）

- `xcodebuild test -scheme Zmole -destination 'platform=macOS'` 全量独立重跑：`Executed 283 tests, with 0 failures (0 unexpected)`，`** TEST SUCCEEDED **`；`CommandConcurrencyTests` passed（7/7）、`UninstallDetailTests` passed（14/14，含新用例 `testAnotherWriteInvalidatesAnUninstallPreview`，0.002s passed）；全量 `Test Case ... passed` 计数 = 283，无 `failed` 行。
- 集成脚本：`clean_trash_test.sh` 本轮独立重跑 exit 0（all cases passed）；`installer_interface_test.sh` 与 `uninstall_stream_test.sh` 本轮重跑均在本机 `/usr/bin/trash <mktemp dir>` 清理步骤挂起不返回（进程树实证，两次复现），与 t042 diff 零交集（三脚本及 `src/zmole/Resources` 下 mole 资源均不在 diff），Round 1 对二者已独立跑通（15/15、7/7）。

reviewed_scope: d9603947f8282d74

### 结论（Round 2）

- 前轮 finding 复核：f001 / f002 / f003 均已消除（逐条以 diff/代码核实，见上）。
- 改测方向复核：无。本轮测试改动均为新增（`CommandConcurrencyTests.swift` 新增 8 行负断言；`UninstallDetailTests.swift` +18/-1 为 `makeViewModel` 增可选参数与新增用例），无「迁就实现」的预期改写。
- 本轮新发现：0 条。
- 未进表的提示：
  - 环境观察（非本 task 问题）：本机 `/usr/bin/trash` 在 `/private/var/folders/.../T/<mktemp dir>` 上挂起不返回，直接阻塞 installer / uninstall 两条集成脚本本轮重跑（clean 脚本正常，Round 1 三脚本均通过）。脚本与 mole 资源均不在本 diff，建议系统层面排查（~/.Trash 状态、mds/Finder 响应），与 t042 无关。
  - 覆盖小注（不阻断）：`operationID` 负断言以 `private func operationID(for` 锚定，仅覆盖私有函数形态；与 AC-001「私有重复」措辞一致，当前源码零命中，可接受。
- 总体判断：三项 minor 修复真实到位，修复引入零新问题，全量 283/0 独立复跑通过 → 无未解决 critical/important。
- AC 复验方式：
  - AC-001 re_verified：负断言面按前轮 f001 建议补齐，独立 rg 三 VM 五类模式零命中；结构测试随全量重跑通过。
  - AC-002 re_verified：全量 `xcodebuild test` 独立重跑 `Executed 283 tests, with 0 failures`，TEST SUCCEEDED。
  - AC-003 re_verified：clean/maintenance 两腿随全量重跑通过；uninstall 腿由新增用例 `testAnotherWriteInvalidatesAnUninstallPreview` 独立覆盖并通过（真实 coordinator/VM 路径）。
  - AC-004 re_verified：xcodebuild 本轮独立重跑通过；`clean_trash_test.sh` 本轮独立通过；installer / uninstall 两脚本沿用 Round 1 reviewer 独立复跑结果（本轮重跑受环境 trash 挂起阻塞，脚本与 diff 零交集，见提示）。
  - coverage = 4/4 re_verified（installer / uninstall 脚本腿为本轮环境阻塞、沿用 Round 1 独立复跑结果；说明见上）。
- 系统性 follow-up：无。

verdict: PASS

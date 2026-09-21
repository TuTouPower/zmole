# Task review t008（reviewer_focus: 测试）

- task：`t008_clean_run`
- spec：`docs/tasks/t008_clean_run/spec.md`
- diff_anchor：`e1bfc29e87ddc097449c5b2218997626026faca4`
- target：`git -C '/Users/karson/kar/code/zmole_t008' diff e1bfc29e87ddc097449c5b2218997626026faca4`
- round：1
- reviewed_at：2026-09-21 20:22 UTC+8

reviewed_scope: 153bc8dbe312cb55

## Findings

### t008_test_f001 - AC-005 没有 UI 文案或 snapshot 测试

- 严重度：important
- 锚点：AC-005；预览 UI 必须说明执行时会重新扫描、列表可能变化
- 位置：`tests/unit/ZmoleTests.swift:327-480`；`src/zmole/Features/Clean/CleanView.swift:48`
- 问题：新增 clean 测试只覆盖 `CleanViewModel`、Bridge spy 和文件读取，没有 UI 文案测试或 snapshot。当前 `CleanView.swift:48` 使用 `clean.execution_note`，但测试不会在 key 被删除、改错或视图未展示时失败；36/36 仍可通过，无法证明用户可观察的 AC-005。
- 建议：增加 UI 文案测试或 snapshot，断言预览页展示“执行时会重新扫描、列表可能变化”的本地化文本。

### t008_test_f002 - AC-006 未覆盖 dry-run 非零和旧列表场景

- 严重度：important
- 锚点：AC-006；dry-run 非零或未写出本次 list 时不得展示目录里的旧 `clean-list.txt`
- 位置：`tests/unit/ZmoleTests.swift:389-404`、`tests/unit/ZmoleTests.swift:744-775`
- 问题：`testCleanPreviewFailureOrMissingListCannotConfirm` 使用 spy 默认 `dryRunResult.exitCode == 0`，只把 `writesPreviewFile` 设为 `false`，因此只验证“没有任何文件”分支。测试没有预先写入旧列表，也没有让 dry-run 返回非零；删除 `CleanPreviewStore.begin()` 的旧文件清理，或非零退出后错误读取旧文件，均可能继续通过现有测试，AC-006 的核心防回读约束未被验证。
- 建议：拆分非零退出与缺失文件用例；预先写入带有旧内容的 `clean-list.txt`，断言预览失败、确认不可用、旧内容不出现在预览中，并断言不产生无 `--dry-run` 的 clean。

### t008_test_f003 - AC-009 失败摘要断言过弱

- 严重度：important
- 锚点：AC-009；执行非零退出时展示 mole 输出摘要，不假装成功
- 位置：`tests/unit/ZmoleTests.swift:457-480`
- 问题：测试注入了 `stdout = "partial output"`、`stderr = "clean failed"` 和退出码 9，却只断言 `errorMessage` 包含 `"9"`。只显示退出码、丢失 stdout/stderr 摘要的实现仍会通过；测试也没有断言失败摘要实际可展示或成功摘要未被设置，因此无法保护本轮补充的失败 stdout 摘要行为。
- 建议：断言 `executionSummary` 或错误展示内容包含注入的 stdout、stderr，且 preview 被清除、成功状态未设置；不要用只匹配退出码的弱断言替代摘要断言。

### t008_test_f004 - AC-007 的并发测试静默吞掉等待超时

- 严重度：important
- 锚点：AC-007；执行过程中再次点击执行不得创建第二个 Process
- 位置：`tests/unit/ZmoleTests.swift:420-429`、`tests/unit/ZmoleTests.swift:798-803`
- 问题：`testCleanDuplicateExecutionCreatesOneProcess` 依赖 `waitForArgumentCount(2)`，但该 helper 超过 1 秒后直接返回且不失败。若首个 Task 尚未真正进入执行，第二个 Task 可能成为唯一的 clean 调用，随后首个 Task 被 busy 状态拦截，参数仍为 `[clean --dry-run, clean]`，测试会通过，却没有验证第二次点击被忽略，形成异步时序假绿。
- 建议：用可等待的 spy continuation 或 XCTest fulfillment 明确等待首个 clean 已进入 blocked 状态；等待超时必须失败，并在发起第二次确认前断言 `isExecuting` 或等价的“首个执行已占用”证据。

## 结论

### AC 复验方式

- AC-001：`re_verified`；独立运行 XCTest，`testCleanPreviewUsesDryRunAndCurrentList` 对 argv 精确断言为 `["clean", "--dry-run"]`。
- AC-002：`re_verified`；`testCleanConfirmationCancelExpiresPreviewWithoutExecution` 复验取消确认后的参数列表无无 `--dry-run` 的 clean。
- AC-003：`re_verified`；同一测试复验取消确认后 preview 清除、`canConfirm == false`，再次确认不产生执行调用。
- AC-004：`re_verified`；`testCleanConfirmationRunsCleanWithoutDryRun` 对 `["clean"]` 做精确 argv 断言。
- AC-005：`trust_prior`；独立查证 `CleanView.swift:48` 与三语 String Catalog 文案，但没有 UI 文案测试或 snapshot，无法独立证明渲染结果。
- AC-006：`re_verified`；独立运行缺失文件用例并核对测试代码，确认仅覆盖缺失分支，非零退出和旧列表分支未被复验。
- AC-007：`re_verified`；独立运行并检查并发用例，但发现等待 helper 静默超时，当前测试证据不足以证明第二次点击确实发生在首个执行已占用之后。
- AC-008：`re_verified`；`testCleanCancelCallsBridgeCancelAndEndsExecution` 复验 cancel 调用次数为 1 且执行结束不再忙碌。
- AC-009：`re_verified`；独立运行失败用例，但确认其只断言退出码，未复验 stdout/stderr 摘要内容。

coverage = 8 / 9

七视角扫描已完成：安全、正确性、契约·Breaking、性能·资源、架构·可维护性、健壮性·可观测、测试·文档·规格。测试范围外未发现需新增 finding 的问题；真机删除效果按上下文“有意不测”处理，`blackbox_verify` 为“无”。

- 前轮 finding 复核：无，首轮审查。
- 改测方向复核：无；相对 diff anchor 未发现既有测试断言被迁就实现、删除或反转，clean 测试均为新增。
- 本轮新发现：4 条（4 important）。
- 未进表的提示：无。
- 总体判断：AC-005、AC-006、AC-009 的关键行为缺少可靠测试证据，AC-007 还存在异步假绿路径，判定 FAIL。
- 系统性 follow-up：无。

verdict: FAIL

## Round 2 (2026-09-21 20:31 UTC+8)

reviewed_scope: 9a29848df84d5ddf

### 前轮 finding 复核

- `t008_test_f001`：修不彻底。`tests/unit/ZmoleTests.swift:430-449` 仅断言 `CleanViewCopy.executionNoteKey` 等于 key，并断言三种本地化值非空；若文案改成任意无关文本，或 `CleanView` 删除 `Text(LocalizedStringKey(CleanViewCopy.executionNoteKey))`，该测试仍可通过，不能证明 AC-005 指定说明已展示。
- `t008_test_f002`：已消除。`testCleanPreviewFailureOrMissingListCannotConfirm` 预置旧文件并模拟本次未写文件，`testCleanNonZeroDryRunCannotConfirmOrExecute` 模拟非零退出；两者均断言预览为空、不可确认，且后者断言未产生无 `--dry-run` 调用。
- `t008_test_f003`：已消除。`tests/unit/ZmoleTests.swift:503-528` 同时精确断言 `executionSummary == "partial output\\nclean failed"` 与退出码错误，覆盖 stdout/stderr 摘要。
- `t008_test_f004`：已消除。`tests/unit/ZmoleTests.swift:452-477` 在第二次点击前断言执行中，`CleanProcessSpy.waitForArgumentCount` 超时会抛错（`tests/unit/ZmoleTests.swift:846-851`），并精确断言只有一条执行调用。

### AC 复验方式

- AC-001：`re_verified`；独立运行 XCTest，`testCleanPreviewUsesDryRunAndCurrentList` 精确断言 `clean --dry-run` argv。
- AC-002：`re_verified`；`testCleanConfirmationCancelExpiresPreviewWithoutExecution` 的调用记录只含预览调用，无无 `--dry-run` 的 clean。
- AC-003：`re_verified`；同一测试断言取消确认后 preview 为空、不可确认，再次确认不产生执行调用。
- AC-004：`re_verified`；`testCleanConfirmationRunsCleanWithoutDryRun` 精确断言执行 argv 为 `clean`。
- AC-005：`trust_prior`；代码显示 `CleanView` 使用文案 key，String Catalog 含三种本地化值，但当前测试未验证指定文本或实际渲染。
- AC-006：`re_verified`；独立检查旧 list、未写 list、dry-run 非零三条路径的测试断言，确认预览为空且不可确认。
- AC-007：`re_verified`；独立运行并检查阻塞 spy、执行中断言、超时抛错和调用记录。
- AC-008：`re_verified`；`testCleanCancelCallsBridgeCancelAndEndsExecution` 断言 cancel 次数为 1 且执行结束。
- AC-009：`re_verified`；`testCleanExecutionFailureShowsSummaryError` 精确断言 stdout/stderr 摘要和退出码错误。

coverage = 8 / 9

建议合并前人工抽查 trust_prior 项。

- 改测方向复核：无；本轮新增测试未删除、反转或迁就既有断言。
- 独立测试：`xcodebuild -project Zmole.xcodeproj -scheme Zmole -configuration Debug -destination 'platform=macOS' test`，38/38 通过。
- 七视角扫描：已复核安全、正确性、契约·Breaking、性能·资源、架构·可维护性、健壮性·可观测、测试·文档·规格；除前轮 `t008_test_f001` 未充分修复外，无本轮新 finding。真机删除效果按上下文“有意不测”处理。
- 本轮新发现：0 条。
- 未进表的提示：无。
- 总体判断：AC-005 仍缺少可靠测试证据，前轮 important finding 未消除，判定 FAIL。
- 系统性 follow-up：无。

verdict: FAIL

## Round 3 (2026-09-21 20:38 UTC+8)

reviewed_scope: 430fc0704877cb0e

### 前轮 finding 复核

- `t008_test_f001`：仍存在，未修复。`tests/unit/ZmoleTests.swift:430-462` 现在断言 `CleanViewCopy.executionNoteKey` 和三种语言目录中的 `rescan` / `list may change`、`重新扫描` / `列表可能变化`、`重新掃描` / `列表可能變化`，因此指定语义在 String Catalog 中有测试；但没有 snapshot、ViewInspector 或等价断言证明 `CleanView` 展示该文案。`src/zmole/Features/Clean/CleanView.swift:49-53` 当前确实把 key 接到 `Text`，但删除或改写这段视图接入后该测试仍会通过，AC-005 的 UI 可观察行为仍缺可靠测试证据。该 finding 保持 important。
- `t008_test_f002`：已消除。`tests/unit/ZmoleTests.swift:389-405` 预置旧 `clean-list.txt` 并令本次 dry-run 不写文件，断言预览为空且不可确认；`tests/unit/ZmoleTests.swift:408-428` 覆盖 dry-run 退出码 7，并精确断言没有无 `--dry-run` 的执行调用。
- `t008_test_f003`：已消除。`tests/unit/ZmoleTests.swift:516-540` 注入 stdout、stderr 和退出码，精确断言 `executionSummary == "partial output\\nclean failed"`，同时断言错误包含退出码且预览被清除。
- `t008_test_f004`：已消除。`tests/unit/ZmoleTests.swift:464-489` 在第二次点击前等待执行调用并断言 `isExecuting`；`tests/unit/ZmoleTests.swift:858-863` 等待超时会抛错，不再静默通过，并精确断言只有一次无 `--dry-run` 的执行调用。

### AC 复验方式

- AC-001：`re_verified`；独立运行 XCTest，`testCleanPreviewUsesDryRunAndCurrentList` 对 argv 精确断言为 `[["clean", "--dry-run"]]`。
- AC-002：`re_verified`；`testCleanConfirmationCancelExpiresPreviewWithoutExecution` 的调用记录在确认前及取消确认后均没有无 `--dry-run` 的 clean。
- AC-003：`re_verified`；同一测试断言取消确认后 preview 为空、`canConfirm == false`，再次调用确认不会创建执行调用。
- AC-004：`re_verified`；`testCleanConfirmationRunsCleanWithoutDryRun` 精确断言调用序列为预览 `clean --dry-run` 后执行 `clean`。
- AC-005：`trust_prior`；独立查证 `CleanView.swift:52` 使用 `clean.execution_note`，并重跑 `testCleanExecutionNoteUsesLocalizedCatalogKey` 查证三语指定语义；没有 UI 文案测试或 snapshot，无法独立复验实际渲染接入。
- AC-006：`re_verified`；独立检查并运行旧 list、未写本次 list、dry-run 非零三条路径，测试均断言 preview 为空、确认不可用；非零路径还断言不产生执行 clean。
- AC-007：`re_verified`；`testCleanDuplicateExecutionCreatesOneProcess` 使用阻塞 spy，在首个执行占用后再次确认，并断言最终只有一条执行 argv。
- AC-008：`re_verified`；`testCleanCancelCallsBridgeCancelAndEndsExecution` 断言 Bridge spy 的 cancel 次数为 1，且执行结束后不再 busy。
- AC-009：`re_verified`；`testCleanExecutionFailureShowsSummaryError` 精确断言 stdout/stderr 摘要和退出码错误，确认失败不会被当作成功。

coverage = 8 / 9

- 改测方向复核：无；相对 diff anchor 未发现既有测试断言被删除、反转或改写为迁就实现，本轮新增测试均直接验证生产 ViewModel 与 Bridge 边界行为。
- 独立测试：`xcodebuild -project '/Users/karson/kar/code/zmole_t008/Zmole.xcodeproj' -scheme Zmole -configuration Debug -destination 'platform=macOS' test`，38/38 通过。
- 危险模式扫描：未发现恒真断言、弱化既有断言、删除测试、`.skip` / `.only`、静默超时或 mock 被测逻辑本身；`CleanProcessSpy` 仅替代外部进程边界。
- 七视角扫描：已复核安全、正确性、契约·Breaking、性能·资源、架构·可维护性、健壮性·可观测、测试·文档·规格；除持续存在的 AC-005 测试证据缺口外，无本轮新 finding。真机删除效果按上下文“有意不测”处理。
- 本轮新发现：0 条。
- 未进表的提示：无。
- 总体判断：前轮 `t008_test_f001` 仍未消除，AC-005 尚未同时由测试证明指定语义与视图接入，判定 FAIL。
- 系统性 follow-up：无。

verdict: FAIL

## Round 4 (2026-09-21 20:42 UTC+8)

reviewed_scope: 8fd864b3141598ba

### 前轮 finding 复核

- `t008_test_f001`：已消除。`tests/unit/ZmoleTests.swift:430-471` 的 `testCleanExecutionNoteUsesLocalizedCatalogKey` 同时锁定三种语言中的“执行时重新扫描、列表可能变化”语义，并读取 `CleanView.swift` 源码，精确断言 `Text(LocalizedStringKey(CleanViewCopy.executionNoteKey))` 接入实际视图。AC-005 的指定语义与 CleanView 接入均有测试保护。
- `t008_test_f002`：已消除。旧 `clean-list.txt` 夹具与本次 dry-run 不写文件场景在 `tests/unit/ZmoleTests.swift:389-405` 覆盖；`tests/unit/ZmoleTests.swift:408-428` 另覆盖 dry-run 非零退出，并精确断言没有无 `--dry-run` 的执行调用。
- `t008_test_f003`：已消除。 `tests/unit/ZmoleTests.swift:525-549` 精确断言 `executionSummary == "partial output\\nclean failed"`，同时验证非零退出错误与预览清除，保护 stdout/stderr 摘要不丢失。
- `t008_test_f004`：已消除。 `tests/unit/ZmoleTests.swift:474-498` 在第二次确认前等待首个执行调用并断言 `isExecuting`；`tests/unit/ZmoleTests.swift:867-873` 超时抛错，最终 argv 精确只有一条 `["clean"]`。

### AC 复验方式

- AC-001：`re_verified`；`testCleanPreviewUsesDryRunAndCurrentList` 精确断言 argv 为 `["clean", "--dry-run"]`。
- AC-002：`re_verified`；`testCleanConfirmationCancelExpiresPreviewWithoutExecution` 的调用记录没有无 `--dry-run` 的 clean。
- AC-003：`re_verified`；同一测试断言取消确认后 preview 清除、`canConfirm == false`，再次确认不产生执行调用。
- AC-004：`re_verified`；`testCleanConfirmationRunsCleanWithoutDryRun` 精确断言调用序列为预览后 `["clean"]`。
- AC-005：`re_verified`；`testCleanExecutionNoteUsesLocalizedCatalogKey` 验证三语指定语义，并精确查证该 key 已接入 `CleanView` 的 `Text`。
- AC-006：`re_verified`；旧列表未被本次写出与 dry-run 非零两条路径均验证预览为空、确认不可用；非零路径还验证没有执行 clean。
- AC-007：`re_verified`；阻塞 spy、执行中状态、超时失败和最终调用序列共同验证重复确认不创建第二个 Process。
- AC-008：`re_verified`；`testCleanCancelCallsBridgeCancelAndEndsExecution` 断言 cancel 调用一次且执行结束。
- AC-009：`re_verified`；`testCleanExecutionFailureShowsSummaryError` 精确验证 stdout/stderr 摘要、非零错误和失败后的预览清除。

coverage = 9 / 9

- 改测方向复核：无；本轮未发现迁就实现、删除、反转或弱化既有断言。
- 独立测试：`xcodebuild -project '/Users/karson/kar/code/zmole_t008/Zmole.xcodeproj' -scheme Zmole -configuration Debug -destination 'platform=macOS' test`，38/38 通过。
- 危险模式扫描：未发现恒真断言、静默超时、删断言、`.skip` / `.only`、mock 被测逻辑或假交互；`CleanProcessSpy` 仅替代外部 mole 进程边界。
- 七视角扫描：已复核安全、正确性、契约·Breaking、性能·资源、架构·可维护性、健壮性·可观测、测试·文档·规格；未发现新 finding。真机删除效果按上下文“有意不测”处理。
- 本轮新发现：0 条。
- 未进表的提示：无。
- 总体判断：前轮四条 important finding 均已消除，AC-001–AC-009 均有可信自动测试证据。
- 系统性 follow-up：无。

verdict: PASS

## Round 5 (2026-09-21 20:47 UTC+8)

reviewed_scope: b3700c2d73fcb37c

### 前轮 finding 复核

- `t008_test_f001`：已消除。`tests/unit/ZmoleTests.swift:430-471` 的 `testCleanExecutionNoteUsesLocalizedCatalogKey` 精确断言英文、简体中文、繁体中文均包含“执行时重新扫描、列表可能变化”的语义，并断言 `CleanView.swift:52` 使用 `Text(LocalizedStringKey(CleanViewCopy.executionNoteKey))` 接入视图。
- `t008_test_f002`：已消除。`tests/unit/ZmoleTests.swift:389-405` 预置旧 list 并模拟本次 dry-run 不写文件；`tests/unit/ZmoleTests.swift:408-428` 覆盖 dry-run 非零退出，两条路径均断言不可确认且不会执行 clean。
- `t008_test_f003`：已消除。`tests/unit/ZmoleTests.swift:525-549` 精确断言 stdout/stderr 摘要为 `partial output\nclean failed`，同时验证非零错误。
- `t008_test_f004`：已消除。`tests/unit/ZmoleTests.swift:474-498` 在首次执行占用后再发起第二次确认；`tests/unit/ZmoleTests.swift:867-873` 等待超时抛错，最终只记录一条 `clean` 执行调用。

### AC 复验方式

- AC-001：`re_verified`；`testCleanPreviewUsesDryRunAndCurrentList` 精确断言 argv 为 `["clean", "--dry-run"]`。
- AC-002：`re_verified`；确认前调用记录只有预览调用，没有无 `--dry-run` 的 clean。
- AC-003：`re_verified`；`testCleanConfirmationCancelExpiresPreviewWithoutExecution` 断言取消后 preview 清除、不可确认且不产生执行调用。
- AC-004：`re_verified`；`testCleanConfirmationRunsCleanWithoutDryRun` 精确断言预览后执行 argv 为 `["clean"]`。
- AC-005：`re_verified`；独立重跑 XCTest 通过，并核对测试同时验证三语说明语义与 `CleanView` 的实际 `Text` 接入。
- AC-006：`re_verified`；旧 list、未写出本次 list、dry-run 非零三条路径均被覆盖，失败后 preview 为空且不可确认。
- AC-007：`re_verified`；阻塞 spy、执行中断言、超时抛错与最终调用序列共同证明没有第二个 Process。
- AC-008：`re_verified`；`testCleanCancelCallsBridgeCancelAndEndsExecution` 验证 cancel 调用一次且 busy 结束。
- AC-009：`re_verified`；`testCleanExecutionFailureShowsSummaryError` 验证 stdout/stderr 摘要、非零错误与失败状态。

coverage = 9 / 9

- 改测方向复核：无；本轮未发现迁就实现、删除、反转或弱化既有断言。
- 独立测试：`xcodebuild test -project Zmole.xcodeproj -scheme Zmole -destination 'platform=macOS' -derivedDataPath .scratch/xcode-derived`，38/38 通过。
- 危险模式扫描：未发现恒真断言、静默超时、删断言、`.skip` / `.only`、mock 被测逻辑或假交互；`CleanProcessSpy` 仅替代外部 mole 进程边界。
- 七视角扫描：已复核安全、正确性、契约·Breaking、性能·资源、架构·可维护性、健壮性·可观测、测试·文档·规格；未发现新 finding。真机删除效果按上下文“有意不测”处理。
- 本轮新发现：0 条。
- 未进表的提示：无。
- 总体判断：前轮四条 important finding 均已消除，AC-001–AC-009 均有可信自动测试证据。
- 系统性 follow-up：无。

verdict: PASS

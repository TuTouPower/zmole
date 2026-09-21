# Task review t008（reviewer_focus: 代码）

- task：`t008_clean_run`
- spec：`docs/tasks/t008_clean_run/spec.md`
- diff_anchor：`e1bfc29e87ddc097449c5b2218997626026faca4`
- target：`git -C '/Users/karson/kar/code/zmole_t008' diff e1bfc29e87ddc097449c5b2218997626026faca4`
- round：1
- reviewed_at：2026-09-21 20:16 UTC+8

reviewed_scope: 76ae8b26766af9a6

## Findings

### t008_code_f001 - clean 失败时丢失 stdout 摘要

- 严重度：important
- 锚点：AC-009；执行失败或部分完成应展示 mole 输出摘要
- 位置：`src/zmole/Features/Clean/CleanViewModel.swift:127-139`、`src/zmole/Features/Clean/CleanView.swift:73-81`、`src/zmole/MoleBridge/MoleBridgeError.swift:12-21`
- 问题：`executionSummary` 只在退出码为 0 的路径保存 `result.stdout`。真实 `MoleBridge` 遇到非零退出会抛出 `MoleBridgeError.commandFailed`，该错误描述只保留 stderr；stderr 为空时只显示退出码。若 clean 已将部分完成信息写入 stdout 后以非零退出，界面最终只显示“退出码”，不显示 mole 输出摘要，无法判断已完成部分。复现输入：执行结果 `stdout = "removed cache A"`、`stderr = ""`、`exitCode = 9`。
- 建议：失败路径保留 `MoleCommandResult` 的 stdout/stderr，并在错误状态展示合并后的输出摘要（至少保留非空 stdout，必要时追加 stderr）；保持预览失效且不显示成功状态。

### t008_code_f002 - clean 新增错误消息未走 String Catalog

- 严重度：minor
- 锚点：行为缺陷；英文或繁体界面遇到 clean 专属错误时显示中文
- 位置：`src/zmole/Features/Clean/CleanPreview.swift:9-18`、`src/zmole/Features/Clean/CleanViewModel.swift:135`
- 问题：`CleanPreviewStoreError.errorDescription` 与取消提示直接写死简体中文；这些字符串经 `error.localizedDescription` 进入 UI，而本 task 新增的按钮、标题和说明已进入三语 String Catalog。英文、繁体用户触发缺文件、空文件、编码错误或取消时仍看到中文。
- 建议：为 clean 错误和取消状态增加 `en`、`zh-Hans`、`zh-Hant` 文案，并通过本地化 key 或本地化错误状态交给视图渲染。

## 结论

### AC 复验方式

- AC-001：`re_verified`；`CleanViewModel.swift:64-68` 预览调用参数为 `clean --dry-run`。
- AC-002：`re_verified`；确认入口 `CleanViewModel.swift:90-93` 只设置确认状态，无执行调用。
- AC-003：`re_verified`；`CleanViewModel.swift:95-99` 取消确认后清除 preview，且无无 dry-run 的 clean 调用。
- AC-004：`re_verified`；`CleanViewModel.swift:124-125` 确认执行参数为 `clean`，不含 `--dry-run`。
- AC-005：`re_verified`；`CleanView.swift:48` 展示执行时重扫说明，`Localizable.xcstrings:16,21` 提供确认页与预览页三语文案。
- AC-006：`re_verified`；`CleanPreview.swift:47-65` 先移除旧文件并拒绝缺失、空内容或无效 UTF-8，`CleanViewModel.swift:70-78` 在非零退出后不读取预览文件。
- AC-007：`re_verified`；`CleanViewModel.swift:18-19,101-115` 以 `isExecuting` 门禁并在首次 await 前置忙碌状态。
- AC-008：`re_verified`；`CleanViewModel.swift:143-145` 调用 Bridge 的 `cancel`，`MoleBridge.swift:80-85` 转发到活动进程。
- AC-009：`re_verified`；`CleanViewModel.swift:127-139` 会清除 preview 并展示错误，但 `t008_code_f001` 证明非零退出时未完整展示 mole 输出摘要。

coverage = 9 / 9

安全、契约与 Breaking、性能与资源、架构与可维护性、健壮性与可观测性、文档与规格一致性均已扫描；除上述 finding 外未发现新增阻断问题。未进表提示：`tests/unit/ZmoleTests.swift` 当前 804 行，本 task 净增 227 行，达到测试源码文件过大阈值；按审查规则仅在此提示，不单列 finding。新增实现文件均低于文件过大阈值，未发现函数圈复杂度达到出表阈值。

独立执行 `xcodebuild test -scheme Zmole -destination 'platform=macOS'` 通过，36/36；该结果不改变 f001，因为现有失败用例未验证 stdout 摘要。

- 前轮 finding 复核：无，首轮审查。
- 本轮新发现：2 条（1 important，1 minor）。
- 未进表的提示：见上文文件规模与复杂度说明。
- 总体判断：clean 失败路径仍无法可靠展示部分完成摘要，存在未解决 important finding，判定 FAIL。
- 系统性 follow-up：无。

verdict: FAIL

## Round 2 (2026-09-21 20:33 UTC+8)

reviewed_scope: 9a29848df84d5ddf

### 前轮 finding 复核

- `t008_code_f001`：已消除。`CleanViewModel.swift:143-145` 在非零退出的 `MoleBridgeError.commandFailed` 路径保留 `MoleCommandResult`，`outputSummary`（`CleanViewModel.swift:170-175`）合并非空 stdout 与 stderr；`CleanView.swift:84-88` 展示该摘要。stdout 只有部分完成信息、stderr 为空时也会保留 stdout。
- `t008_code_f002`：修不彻底。预览失败与取消已新增三语 catalog key，且 `CleanViewModel.swift:160-167` 对 `CleanPreviewStoreError` 使用 key；但确认前校验失败走 `CleanViewModel.swift:106-110`，直接展示 `error.localizedDescription`。因此 `changedSincePreview`、文件缺失或编码错误发生在确认阶段时，仍会显示 `CleanPreview.swift:22-32` 的简体中文；初始化失败也仍使用 `CleanViewModel.swift:39` 的硬编码中文。该 minor finding 仍存在。

### 本轮新发现

无。最终 diff 未引入新的 critical / important 问题。

## 结论

- 前轮 finding 复核：`t008_code_f001` 已消除；`t008_code_f002` 修不彻底，仍为 minor。
- 本轮新发现：0 条。
- 未进表的提示：`tests/unit/ZmoleTests.swift` 当前 857 行，达到测试源码文件过大提示阈值；按规则仅提示。新增 clean 实现文件均低于 400 行，未发现函数圈复杂度达到出表阈值。
- 安全、契约与 Breaking、性能与资源、架构与可维护性、健壮性与可观测性、文档与规格一致性均已扫描，除上述前轮 minor 外无新问题。
- 总体判断：stdout 失败摘要已补齐；仅余本地化路径未完全收口，无 critical / important，代码轴通过。
- 系统性 follow-up：无。

### AC 复验方式

- AC-001：`re_verified`；`CleanViewModel.swift:67-70` 预览 argv 为 `clean --dry-run`。
- AC-002：`re_verified`；`CleanViewModel.swift:92-95` 仅进入确认状态，不调用执行 Bridge。
- AC-003：`re_verified`；`CleanViewModel.swift:97-100` 取消确认后清除预览，后续确认入口不可用。
- AC-004：`re_verified`；`CleanViewModel.swift:128` 执行 argv 为 `clean`，不含 `--dry-run`。
- AC-005：`re_verified`；`CleanView.swift:52` 使用 `clean.execution_note`，catalog 在 `Localizable.xcstrings:21` 提供三语说明。
- AC-006：`re_verified`；`CleanPreview.swift:60-78` 先移除旧文件并拒绝缺失、空文件或无效 UTF-8，`CleanViewModel.swift:73-80` 失败时清除预览。
- AC-007：`re_verified`；`CleanViewModel.swift:43-44` 拒绝重复操作，`CleanViewModel.swift:117` 在第一次 await 前置执行状态。
- AC-008：`re_verified`；`CleanViewModel.swift:150-153` 调用 `cancel`，`MoleBridge.swift:80-81` 转发至活动进程。
- AC-009：`re_verified`；`CleanViewModel.swift:130-146` 非零退出进入失败路径并保留 stdout/stderr 摘要，`CleanView.swift:84-88` 展示摘要。

coverage = 9 / 9

verdict: PASS

## Round 3 (2026-09-21 20:39 UTC+8)

reviewed_scope: 430fc0704877cb0e

### 前轮 finding 复核

- `t008_code_f001`：已消除。非零退出路径在 `src/zmole/Features/Clean/CleanViewModel.swift:140-146` 捕获 `MoleBridgeError.commandFailed`，通过 `outputSummary` 合并 stdout 与 stderr；`CleanView.swift:84-88` 展示摘要。当前测试 `testCleanExecutionFailureShowsSummaryError` 独立验证了部分完成 stdout、stderr 与失败码同时可见。
- `t008_code_f002`：修不彻底，仍为 minor。预览失败、确认前列表校验和取消状态已改用 String Catalog；但 `src/zmole/Features/Clean/CleanViewModel.swift:39` 仍把 Bridge 初始化失败写成硬编码简体中文，`CleanView.swift:80-82` 直接显示该文本。Bridge 初始化失败时英文或繁体界面仍会看到中文。最小修复是为该状态增加 catalog key，并让初始化错误与其它 clean 错误走同一 key 路径。

### 本轮新发现

无。当前 diff 未引入新的 critical 或 important 问题。

## 结论

- 前轮 finding 复核：`t008_code_f001` 已消除；`t008_code_f002` 仍存在上述 minor，确认前列表错误本身已收口，剩余初始化失败文案未本地化。
- 本轮新发现：0 条。
- 未进表的提示：`tests/unit/ZmoleTests.swift` 当前 869 行，达到测试源码文件过大提示阈值；按规则仅作结论提示。三个新增 clean 实现文件均低于 400 行，未发现函数圈复杂度达到出表阈值。
- 安全、契约与 Breaking、性能与资源、架构与可维护性、健壮性与可观测性、文档与规格一致性均已扫描；未发现新增问题。路径通过 Bridge 参数数组传递，没有新增 shell 拼接、凭据或敏感数据落盘。
- 独立执行 `xcodebuild test -scheme Zmole -destination 'platform=macOS'`，38/38 通过；`git diff --check` 通过。
- 总体判断：clean 预览、确认、执行、取消和失败摘要均符合契约；仅遗留初始化失败文案本地化 minor，无未解决 critical / important，代码轴通过。
- 系统性 follow-up：无。

### AC 复验方式

- AC-001：`re_verified`；`CleanViewModel.swift:65-70` 调用 argv 为 `clean --dry-run`，`testCleanPreviewUsesDryRunAndCurrentList` 断言完整参数。
- AC-002：`re_verified`；`CleanViewModel.swift:92-95` 的确认请求只设置确认状态，执行入口在 `CleanViewModel.swift:127-128`；预览测试的 spy 调用记录在确认前只有 dry-run。
- AC-003：`re_verified`；`CleanViewModel.swift:97-100` 取消确认会清除 preview，`testCleanConfirmationCancelExpiresPreviewWithoutExecution` 断言没有无 dry-run 的调用且不可再次确认。
- AC-004：`re_verified`；`CleanViewModel.swift:127-134` 确认后只调用 `clean`，`testCleanConfirmationRunsCleanWithoutDryRun` 断言 argv。
- AC-005：`re_verified`；`CleanView.swift:52` 使用 `clean.execution_note`，String Catalog 提供三语“重新扫描/列表可能变化”文案，`testCleanExecutionNoteUsesLocalizedCatalogKey` 独立检查三语内容。
- AC-006：`re_verified`；`CleanPreviewStore.swift:60-64` 先删除旧列表，`CleanViewModel.swift:72-80` 拒绝 dry-run 非零或新列表读取失败并清除 preview；`testCleanPreviewFailureOrMissingListCannotConfirm` 和 `testCleanNonZeroDryRunCannotConfirmOrExecute` 覆盖旧文件与非零场景。
- AC-007：`re_verified`；`CleanViewModel.swift:43-44,117-124` 在首次执行 await 前设置 busy 门禁，`testCleanDuplicateExecutionCreatesOneProcess` 通过阻塞 spy 验证只有一个 `clean` Process。
- AC-008：`re_verified`；`CleanViewModel.swift:150-153` 调用 Bridge 的 `cancel`，`MoleBridge.swift:80-85` 转发到活动 runner，`testCleanCancelCallsBridgeCancelAndEndsExecution` 验证取消计数和 busy 结束。
- AC-009：`re_verified`；`CleanViewModel.swift:130-146` 对非零退出保留 stdout/stderr 摘要并设置错误，`testCleanExecutionFailureShowsSummaryError` 断言 `partial output\nclean failed` 与失败码。

coverage = 9 / 9

verdict: PASS

## Round 4 (2026-09-21 20:43 UTC+8)

reviewed_scope: 8fd864b3141598ba

### 前轮 finding 复核

- `t008_code_f001`：已消除。执行非零退出时，`src/zmole/Features/Clean/CleanViewModel.swift:140-146` 捕获 `MoleBridgeError.commandFailed`，通过 `outputSummary` 合并非空 stdout 与 stderr；`CleanView.swift:84-88` 展示摘要。当前独立测试 `testCleanExecutionFailureShowsSummaryError` 验证部分完成 stdout、stderr 与失败码同时可见。
- `t008_code_f002`：仍存在，严重度为 minor。`src/zmole/Features/Clean/CleanViewModel.swift:34-40` 的 Bridge 初始化失败路径仍写入硬编码简体中文 `"找不到捆绑 mole"`，随后由 `CleanView.swift:80-82` 直接展示；英文或繁体界面遇到该路径仍显示中文。预览文件错误与取消提示已走 String Catalog，但该初始化路径尚未收口。

### 本轮新发现

无。

## 结论

- 前轮 finding 复核：`t008_code_f001` 已消除；`t008_code_f002` 仍为 minor，未引入新的 critical / important。
- 未进表的提示：`tests/unit/ZmoleTests.swift` 当前 878 行，达到测试源码文件过大提示阈值；按规则仅作提示。三个新增 clean 实现文件均低于 400 行，未发现函数圈复杂度达到出表阈值。
- 安全、契约与 Breaking、性能与资源、架构与可维护性、健壮性与可观测性、文档与规格一致性均已扫描。Bridge 仍通过参数数组传递，无新增 shell 拼接、凭据或敏感数据落盘。
- 独立执行 `xcodebuild test -scheme Zmole -destination 'platform=macOS'`，38/38 通过；`git diff --check` 通过。
- 总体判断：clean 预览、确认、执行、取消与失败摘要符合契约；仅遗留初始化失败文案本地化 minor。按共享规则无 critical / important，代码评审通过。
- 系统性 follow-up：无。

### AC 复验方式

- AC-001：`re_verified`；`CleanViewModel.swift:65-70` 调用 argv 为 `clean --dry-run`，`testCleanPreviewUsesDryRunAndCurrentList` 断言参数。
- AC-002：`re_verified`；`CleanViewModel.swift:92-95` 的确认入口只设置确认状态，不调用执行 Bridge；测试 spy 在确认前仅记录 dry-run。
- AC-003：`re_verified`；`CleanViewModel.swift:97-100` 取消确认会清除 preview，`testCleanConfirmationCancelExpiresPreviewWithoutExecution` 断言没有无 dry-run 的调用且不可再次确认。
- AC-004：`re_verified`；`CleanViewModel.swift:127-134` 确认后只调用 `clean`，`testCleanConfirmationRunsCleanWithoutDryRun` 断言 argv。
- AC-005：`re_verified`；`CleanView.swift:52` 通过 `clean.execution_note` 渲染重新扫描说明，`testCleanExecutionNoteUsesLocalizedCatalogKey` 独立检查 UI 接入与三语文案。
- AC-006：`re_verified`；`CleanPreview.swift:60-79` 预览前移除旧文件，并拒绝非零 dry-run、缺失、空内容或无效 UTF-8；`testCleanPreviewFailureOrMissingListCannotConfirm` 与 `testCleanNonZeroDryRunCannotConfirmOrExecute` 覆盖旧文件和失败场景。
- AC-007：`re_verified`；`CleanViewModel.swift:103-124` 以确认状态和 `isExecuting` 门禁，在首次 await 前设置 busy；`testCleanDuplicateExecutionCreatesOneProcess` 验证只创建一个执行 Process。
- AC-008：`re_verified`；`CleanViewModel.swift:150-153` 调用 Bridge `cancel`，`MoleBridge.swift:80-85` 转发到活动 runner；`testCleanCancelCallsBridgeCancelAndEndsExecution` 验证取消计数和 busy 结束。
- AC-009：`re_verified`；`CleanViewModel.swift:130-146` 对非零退出保留 stdout/stderr 摘要并设置错误，`testCleanExecutionFailureShowsSummaryError` 断言 `partial output\nclean failed` 与失败码。

coverage = 9 / 9

verdict: PASS

## Round 5 (2026-09-21 20:50 UTC+8)

reviewed_scope: b3700c2d73fcb37c

### 前轮 finding 复核

- `t008_code_f001`：已消除。非零执行结果在 `src/zmole/Features/Clean/CleanViewModel.swift:140-146` 捕获 `MoleBridgeError.commandFailed`，`outputSummary` 在 `170-174` 合并非空 stdout/stderr；`CleanView.swift:84-88` 展示摘要。当前 `testCleanExecutionFailureShowsSummaryError` 仍验证部分完成输出、stderr 与退出码。
- `t008_code_f002`：已消除。Bridge 初始化失败在 `CleanViewModel.swift:37-40` 只保存 `clean.error.missing_mole` key，`CleanView.swift:77-82` 通过 `LocalizedStringKey` 渲染；`Localizable.xcstrings:26` 为 en、zh-Hans、zh-Hant 提供文案。预览文件错误也由 `CleanViewModel.swift:160-167` 映射到 String Catalog key，取消状态使用 `clean.cancelled`。

### 本轮新发现

无。

## 结论

- 前轮 finding 复核：`t008_code_f001`、`t008_code_f002` 均已消除。初始化失败提示已完全走 String Catalog，三种语言均有对应值；当前 diff 未引入新的 critical / important / minor finding。
- 未进表的提示：`tests/unit/ZmoleTests.swift` 当前 878 行，达到测试源码文件过大提示阈值；按规则仅作结论提示。三个新增 clean 实现文件均低于 400 行，未发现函数圈复杂度达到出表阈值。
- 安全、契约与 Breaking、性能与资源、架构与可维护性、健壮性与可观测性、文档与规格一致性均已扫描。命令参数仍通过数组传递，无新增 shell 拼接、凭据或敏感数据落盘。
- 独立执行 `xcodebuild test -scheme Zmole -destination 'platform=macOS' -quiet` 通过；`git diff --check` 与 String Catalog JSON 校验通过。
- 总体判断：clean 预览、确认、执行、取消、失败摘要和初始化失败本地化均符合契约，代码轴通过。
- 系统性 follow-up：无。

### AC 复验方式

- AC-001：`re_verified`；`CleanViewModel.swift:65-70` 调用 argv 为 `clean --dry-run`，`testCleanPreviewUsesDryRunAndCurrentList` 断言参数。
- AC-002：`re_verified`；`CleanViewModel.swift:92-94` 的确认入口只设置确认状态；确认前 spy 只记录 dry-run 调用。
- AC-003：`re_verified`；`CleanViewModel.swift:97-100` 取消确认会清除 preview，`testCleanConfirmationCancelExpiresPreviewWithoutExecution` 断言不会创建无 dry-run 的 clean。
- AC-004：`re_verified`；`CleanViewModel.swift:127-134` 确认后只调用 `clean`，`testCleanConfirmationRunsCleanWithoutDryRun` 断言 argv。
- AC-005：`re_verified`；`CleanView.swift:52` 渲染 `clean.execution_note`，`Localizable.xcstrings:21` 提供三语“重新扫描/列表可能变化”文案，`testCleanExecutionNoteUsesLocalizedCatalogKey` 检查 UI 接入与文案。
- AC-006：`re_verified`；`CleanPreview.swift:60-78` 预览前移除旧列表并拒绝缺失、空文件或无效 UTF-8，`CleanViewModel.swift:72-80` 在 dry-run 失败时清除 preview；`testCleanPreviewFailureOrMissingListCannotConfirm` 与 `testCleanNonZeroDryRunCannotConfirmOrExecute` 覆盖旧文件和非零场景。
- AC-007：`re_verified`；`CleanViewModel.swift:103-124` 在首次执行 await 前设置 busy 门禁，`testCleanDuplicateExecutionCreatesOneProcess` 验证重复点击只创建一个 Process。
- AC-008：`re_verified`；`CleanViewModel.swift:150-153` 调用 Bridge cancel，`MoleBridge.swift:80-85` 转发到活动 runner，`testCleanCancelCallsBridgeCancelAndEndsExecution` 验证取消计数和 busy 结束。
- AC-009：`re_verified`；`CleanViewModel.swift:130-146` 对非零退出保留 stdout/stderr 摘要，`CleanView.swift:84-88` 展示摘要，`testCleanExecutionFailureShowsSummaryError` 断言失败码与输出内容。

coverage = 9 / 9

verdict: PASS

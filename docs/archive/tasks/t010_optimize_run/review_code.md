# Task review t010（reviewer_focus: 代码）

- task：t010_optimize_run
- spec：docs/tasks/t010_optimize_run/spec.md
- diff_anchor：77e50adba0415afd1e5ea5fa896529edc60f47b4
- target：git -C '/Users/karson/kar/code/zmole_t010' diff 77e50adba0415afd1e5ea5fa896529edc60f47b4
- round：1
- reviewed_at：2026-09-22 05:07 UTC+8

reviewed_scope: 8fae6d9b9fe1fe79

## Findings

### t010_code_f001 - Optimize Bridge 错误路径未完全本地化

- 严重度：minor
- 锚点：本地化；Optimize 的执行失败、预览失败等错误路径在英文或繁体中文界面显示简体中文 Bridge 文案
- 位置：src/zmole/Features/Optimize/OptimizeViewModel.swift:161-168
- 问题：setError(\_:) 仅为 OptimizeViewModelError 使用 String Catalog；MoleBridgeError 会直接透传 localizedDescription。该路径会展示 MoleBridgeError.errorDescription 中的硬编码简体中文（src/zmole/MoleBridge/MoleBridgeError.swift:12-31），因此 Optimize 的命令失败、超时、启动失败等提示不随当前语言切换。
- 建议：为 Bridge 错误类别映射 optimize.error.\* 本地化 key；命令 stdout/stderr 继续保留在已剥 ANSI 的执行摘要中。

## 结论

- AC 复验方式：
    - AC-001：re_verified；OptimizeViewModel.previewOptimize() 调用 ["optimize", "--dry-run"]，且 OptimizeTests.testOptimizePreviewUsesDryRunAndDisplaysStrippedOutput 断言 argv。
    - AC-002：re_verified；预览开始先 invalidatePreview()，非零结果进入失败分支并清空 preview，testOptimizePreviewFailureExpiresPreviousPreview 复验执行按钮不可确认。
    - AC-003：re_verified；执行只在 confirmExecution() 中调用，确认前测试只观察到 dry-run argv。
    - AC-004：re_verified；确认执行调用 ["optimize"]，无 --dry-run；testOptimizeConfirmationExecutesWithoutDryRun 通过。
    - AC-005：re_verified；cancelConfirmation() 清空 preview，后续 confirmExecution() 被 guard 拦截；testOptimizeConfirmationCancelRequiresNewPreview 通过。
    - AC-006：re_verified；执行期间 isExecuting 使重复确认提前返回，cancelExecution() 调用 process.cancel()；testOptimizeBusyExecutionCannotStartTwiceAndCanCancel 通过。
    - coverage = 6 / 6
- 本轮新发现：1 条 minor；无 critical/important。
- 未进表的提示：已扫描安全、正确性、契约与 Breaking、性能与资源、架构可维护性、健壮性可观测、文档规格一致性；无新增阻断问题。Optimize 实现文件与测试文件均低于 prompt 规定的文件规模阈值；ANSI 清理覆盖 mole 当前使用的 CSI/SGR 序列，预览 stdout 进入可滚动 ScrollView。
- 总体判断：AC 全部满足；仅有 Bridge 动态错误提示未完全本地化的 minor，当前 verdict 可 PASS。
- 系统性 follow-up：无

verdict: PASS

## Round 2 (2026-09-22 05:12 UTC+8)

reviewed_scope: 85e59e22dd586fd1

## Findings

无。

## 结论

- 前轮 finding 复核：t010_code_f001 已消除。OptimizeViewModel.setError(\_:) 将所有 MoleBridgeError 映射到 optimize.error.failed（src/zmole/Features/Optimize/OptimizeViewModel.swift:167-177）；该 key 已提供英文、简体中文、繁体中文值（src/zmole/Resources/Localizable.xcstrings:54）。预览和执行的 commandFailed 分支在设置错误前分别保留 stdout/stderr 摘要（src/zmole/Features/Optimize/OptimizeViewModel.swift:75-81、142-148），失败摘要测试也通过（tests/unit/OptimizeTests.swift:118-135）。
- 本轮新发现：0 条。
- 未进表的提示：已扫描安全、正确性、契约与 Breaking、性能与资源、架构可维护性、健壮性可观测、测试与文档规格一致性；无新增问题。Optimize 实现文件（47/91/179 行）和测试文件（229 行）均未达到 prompt 文件规模阈值。
- 总体判断：前轮本地化问题已修复，6/6 AC 满足，无未解决 critical/important/minor finding。
- 系统性 follow-up：无。

### AC 复验方式

- AC-001：re_verified；OptimizeViewModel.previewOptimize() 调用 ["optimize", "--dry-run"]（src/zmole/Features/Optimize/OptimizeViewModel.swift:58-63），testOptimizePreviewUsesDryRunAndDisplaysStrippedOutput 精确断言 argv（tests/unit/OptimizeTests.swift:6-21）。
- AC-002：re_verified；预览开始先清除旧 preview，非零退出进入失败分支并使 canConfirm 为 false（src/zmole/Features/Optimize/OptimizeViewModel.swift:37-40、64-82、18-20），testOptimizePreviewFailureExpiresPreviousPreview 复验旧文本不保留（tests/unit/OptimizeTests.swift:34-50）。
- AC-003：re_verified；未确认时 confirmExecution() 的入口 guard 阻止执行（src/zmole/Features/Optimize/OptimizeViewModel.swift:103-105），testOptimizeDoesNotExecuteBeforeConfirmation 只观察到 dry-run argv（tests/unit/OptimizeTests.swift:52-64）。
- AC-004：re_verified；确认后的执行调用 ["optimize"]，不含 --dry-run（src/zmole/Features/Optimize/OptimizeViewModel.swift:124-125），testOptimizeConfirmationExecutesWithoutDryRun 精确断言调用序列（tests/unit/OptimizeTests.swift:66-89）。
- AC-005：re_verified；取消确认会使 preview 失效，后续确认被入口 guard 拦截（src/zmole/Features/Optimize/OptimizeViewModel.swift:98-105），testOptimizeConfirmationCancelRequiresNewPreview 复验必须重新预览（tests/unit/OptimizeTests.swift:91-115）。
- AC-006：re_verified；预览或执行期间的入口 guard 阻止重复调用，取消执行调用 process.cancel()（src/zmole/Features/Optimize/OptimizeViewModel.swift:37-38、103-105、152-155），testOptimizeBusyExecutionCannotStartTwiceAndCanCancel 断言单次执行、一次取消和 busy 结束（tests/unit/OptimizeTests.swift:138-163）。独立 XCTest 结果为 56/56 通过。
- coverage = 6 / 6

verdict: PASS

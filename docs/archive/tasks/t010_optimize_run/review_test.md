# Task review t010（reviewer_focus: 测试）

- task：`t010_optimize_run`
- spec：`docs/tasks/t010_optimize_run/spec.md`
- diff_anchor：`77e50adba0415afd1e5ea5fa896529edc60f47b4`
- target：`git -C '/Users/karson/kar/code/zmole_t010' diff 77e50adba0415afd1e5ea5fa896529edc60f47b4`
- round：1
- reviewed_at：2026-09-22 05:06 UTC+8

reviewed_scope: 8fae6d9b9fe1fe79

## Findings

无。

## 结论

### AC 复验方式

- AC-001：`re_verified`；独立运行 XCTest 56/56 通过；`testOptimizePreviewUsesDryRunAndDisplaysStrippedOutput`（`tests/unit/OptimizeTests.swift:6-21`）对 argv 精确断言为 \[`["optimize", "--dry-run"]`\]，并断言 stdin 为空。
- AC-002：`re_verified`；`testOptimizePreviewFailureExpiresPreviousPreview`（`tests/unit/OptimizeTests.swift:34-49`）先生成 `old plan`，再注入退出码 7；断言当前 preview 为 nil、`canConfirm == false`，旧文本不能继续作为当前预览，执行按钮对应状态不可确认。
- AC-003：`re_verified`；`testOptimizeDoesNotExecuteBeforeConfirmation`（`tests/unit/OptimizeTests.swift:52-63`）在未请求确认时精确断言调用列表只有 dry-run，未产生无 `--dry-run` 的 optimize。
- AC-004：`re_verified`；`testOptimizeConfirmationExecutesWithoutDryRun`（`tests/unit/OptimizeTests.swift:66-88`）确认后精确断言调用序列为 dry-run 后 `["optimize"]`。
- AC-005：`re_verified`；`testOptimizeConfirmationCancelRequiresNewPreview`（`tests/unit/OptimizeTests.swift:91-114`）取消确认后再次确认不产生执行调用，只有重新预览后才出现一次无 `--dry-run` 的 optimize。
- AC-006：`re_verified`；`testOptimizeBusyExecutionCannotStartTwiceAndCanCancel`（`tests/unit/OptimizeTests.swift:138-161`）使用阻塞 spy，等待首个执行调用后断言 `isExecuting`，重复确认后执行 argv 仍只有一条；取消后断言 Bridge spy cancel 次数为 1、busy 结束且显示取消状态。等待 helper 超时会抛错（`tests/unit/OptimizeTests.swift:217-222`），没有静默放行异步竞态。

coverage = 6 / 6

独立测试：`xcodebuild test -project '/Users/karson/kar/code/zmole_t010/Zmole.xcodeproj' -scheme Zmole -configuration Debug -destination 'platform=macOS' -derivedDataPath '/Users/karson/kar/code/zmole_t010/.scratch/review-t010-derived'`，56/56 通过；其中 OptimizeTests 7/7 通过。

危险模式扫描：未发现恒真断言、删/反转/注释断言、无理由弱化断言、`.skip` / `.only`、静默超时、mock 被测逻辑本身或用赋值冒充交互。OptimizeProcessSpy 仅替代外部 mole 进程边界；取消通过 checked continuation 恢复真实异步路径。ANSI 输出场景有精确结果断言；预览失败、确认取消、重复执行与取消执行均有失败路径和时序证据。

七视角扫描已完成：安全、正确性、契约·Breaking、性能·资源、架构·可维护性、健壮性·可观测、测试·文档·规格。各维护任务副作用属于 spec 上下文“有意不测”；未知契约清单为“无”；未发现范围内问题。

- 前轮 finding 复核：无，首轮审查。
- 改测方向复核：无；相对 diff anchor 仅新增 OptimizeTests.swift，没有既有测试断言被删除、反转或迁就当前实现。
- 本轮新发现：0 条。
- 未进表的提示：无。
- 总体判断：AC-001..AC-006 均有可信自动测试证据，当前测试通过，判定 PASS。
- 系统性 follow-up：无。

verdict: PASS

## Round 2 (2026-09-22 05:11 UTC+8)

reviewed_scope: 85e59e22dd586fd1

## Findings

无。

## 结论

### AC 复验方式

- AC-001：`re_verified`；独立运行 XCTest 56/56 通过；`testOptimizePreviewUsesDryRunAndDisplaysStrippedOutput`（`tests/unit/OptimizeTests.swift:6-31`）对调用参数精确断言为 `["optimize", "--dry-run"]`，并断言 stdin 为空。
- AC-002：`re_verified`；`testOptimizePreviewFailureExpiresPreviousPreview`（`tests/unit/OptimizeTests.swift:34-49`）先建立成功预览，再注入非零退出；断言当前 preview 为 nil、`canConfirm == false`，并断言失败摘要来自本次输出，旧预览文本没有继续作为当前预览。
- AC-003：`re_verified`；`testOptimizeDoesNotExecuteBeforeConfirmation`（`tests/unit/OptimizeTests.swift:52-63`）在未请求确认时精确断言调用列表只有 dry-run optimize。
- AC-004：`re_verified`；`testOptimizeConfirmationExecutesWithoutDryRun`（`tests/unit/OptimizeTests.swift:66-88`）确认后精确断言调用序列为 dry-run 后的 `["optimize"]`，无 `--dry-run`。
- AC-005：`re_verified`；`testOptimizeConfirmationCancelRequiresNewPreview`（`tests/unit/OptimizeTests.swift:91-114`）取消确认后立即确认不产生执行调用，重新预览后才产生一次无 `--dry-run` 的 optimize。
- AC-006：`re_verified`；`testOptimizeBusyExecutionCannotStartTwiceAndCanCancel`（`tests/unit/OptimizeTests.swift:138-161`）用阻塞 spy 等待首个执行调用，断言重复提交只保留一个执行 argv，并断言取消调用 Bridge spy cancel 一次、busy 结束且显示取消状态；等待 helper 超时会抛错（`tests/unit/OptimizeTests.swift:217-222`），没有静默放行异步竞态。

coverage = 6 / 6

独立测试：`xcodebuild test -project '/Users/karson/kar/code/zmole_t010/Zmole.xcodeproj' -scheme Zmole -configuration Debug -destination 'platform=macOS' -derivedDataPath '/Users/karson/kar/code/zmole_t010/.scratch/review-t010-derived'`，56/56 通过；其中 OptimizeTests 7/7 通过。

危险模式扫描：未发现恒真断言、删/反转/注释断言、无理由弱化断言、`.skip` / `.only`、静默超时、mock 被测逻辑本身或用赋值冒充交互。OptimizeProcessSpy 仅替代 mole 进程边界；取消通过 checked continuation 恢复真实异步路径。

七视角扫描已完成：安全、正确性、契约·Breaking、性能·资源、架构·可维护性、健壮性·可观测、测试·文档·规格。上下文区列出的维护任务副作用属于“有意不测”；未知契约清单为“无”；未发现范围内问题。

- 前轮 finding 复核：Round 1 无 finding，当前 diff 未改变测试结论。
- 改测方向复核：无；OptimizeTests.swift 为新增测试文件，未删除、反转或就地改写既有测试断言。
- 本轮新发现：0 条。
- 未进表的提示：无。
- 总体判断：AC-001..AC-006 均有可信自动测试证据，当前测试通过，判定 PASS。
- 系统性 follow-up：无。

verdict: PASS

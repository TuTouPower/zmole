# Task review t011（reviewer_focus: 测试）

- task：`t011_purge_run`
- spec：`docs/tasks/t011_purge_run/spec.md`
- diff_anchor：`ff5317f1eb1a4f28cfcc2e38bcd931f5a836866c`
- target：`git -C '/Users/karson/kar/code/zmole_t011' diff ff5317f1eb1a4f28cfcc2e38bcd931f5a836866c`
- round：1
- reviewed_at：2026-09-22 05:29 UTC+8

reviewed_scope: bff74dd02f2ad0e3

## Findings

无。

## 结论

- 前轮 finding 复核：本轮无前轮报告；当前交付文件已进入相对基线的完整 diff，未跟踪交付文件不存在审查缺口。`git diff --check` 通过。
- 改测方向复核：无。当前 diff 新增 `PurgeTests.swift`，未就地修改或删除既有测试预期。
- 本轮新发现：0 条。
- 未进表的提示：已扫描安全、正确性、契约/Breaking、性能/资源、架构/可维护性、健壮性/可观测、测试/文档/规格七个视角。`PurgeTests.swift:23-30` 的源文件字符串断言仅作视图结构辅助检查，AC 证据来自真实 `PurgeViewModel` 调用、状态断言与精确 argv 断言，不构成阻断问题。
- 总体判断：7 条 AC 均有可执行测试覆盖；dry-run 与 `--yes` 参数严格分离，确认取消后旧预览失效并要求新预览，重复执行与取消异步时序均有真实等待和失败可见断言。
- 系统性 follow-up：无。

### AC 复验方式

- AC-001：`re_verified`。`PurgeTests.swift:6-21` 通过 `PurgeProcessSpy` 断言预览唯一调用为 `["purge", "--dry-run"]`，并断言 stdin 为 nil；独立运行通过。
- AC-002：`re_verified`。`PurgeTests.swift:67-89` 断言调用序列为预览 `["purge", "--dry-run"]` 后执行 `["purge", "--yes"]`，执行参数不含 `--dry-run`；独立运行通过。
- AC-003：`re_verified`。`PurgeTests.swift:53-64` 在未请求确认时断言只有 dry-run 调用；`PurgeTests.swift:92-115` 还验证确认取消后不会提前执行；独立运行通过。
- AC-004：`re_verified`。已检查 `PurgeViewModel.swift:59-62` 与 `PurgeViewModel.swift:125`，两条 purge 执行路径分别固定为 dry-run 与 yes；未发现无参数 purge 路径。测试对完整调用序列做精确相等断言；独立运行通过。
- AC-005：`re_verified`。`PurgeTests.swift:34-50` 先建立成功预览，再注入非零 dry-run，断言旧预览失效、`canConfirm == false`，并保留失败摘要；独立运行通过。
- AC-006：`re_verified`。`PurgeTests.swift:92-115` 取消确认后立即调用确认不会执行，之后重新预览才允许 `["purge", "--yes"]`；完整调用序列精确断言，独立运行通过。
- AC-007：`re_verified`。`PurgeTests.swift:139-163` 使用 actor spy 的阻塞执行与 `CheckedContinuation` 建立真实异步时序，等待第二次调用进入后再次提交，断言 `--yes` 进程数仍为 1；随后取消，断言 Bridge cancel 次数为 1、执行结束且展示取消错误。等待超时会抛错，不会静默通过；独立运行通过。

coverage = 7 / 7

验证命令：`xcodebuild test -scheme Zmole -destination 'platform=macOS' -only-testing:ZmoleTests/PurgeTests`；`PurgeTests` 7/7 通过。

verdict: PASS

## Round 2 (2026-09-22 05:34 UTC+8)

reviewed_scope: 97a6e83192bbb17b

## Findings

无。

## 结论

- 前轮 finding 复核：Round 1 无 finding；本轮按完整 diff 重新核对，未发现遗漏。交付文件均已纳入相对基线 diff；未跟踪项只有本评审报告与代码评审报告，属于流程文件。`git diff --check` 通过。
- 改测方向复核：无。当前 diff 只新增 `PurgeTests.swift`，未就地修改或删除既有测试预期，未发现弱化断言、跳过测试、恒真断言或 mock 被测逻辑。
- 本轮新发现：0 条。
- 未进表的提示：`PurgeTests.swift:29-30` 的源文件字符串断言只作视图接线辅助检查；AC 证据仍来自 `PurgeViewModel` 的真实调用、状态断言、精确 argv 断言和异步取消时序，不构成阻断问题。七个评审视角均已扫描。
- 总体判断：AC-001..AC-007 均有可信测试覆盖；预览与执行 argv 严格分离，确认取消及重预览会失效旧状态，重复执行不会创建第二进程，取消会调用 Bridge cancel。
- 系统性 follow-up：无。

### AC 复验方式

- AC-001：`re_verified`。`PurgeTests.swift:18-21` 精确断言预览调用为 `["purge", "--dry-run"]`、stdin 为 nil；生产路径见 `PurgeViewModel.swift:59-62`。
- AC-002：`re_verified`。`PurgeTests.swift:82-88` 精确断言成功流程为 dry-run 后 `["purge", "--yes"]`；生产路径见 `PurgeViewModel.swift:124-125`。
- AC-003：`re_verified`。`PurgeTests.swift:53-63` 在未确认时只允许 dry-run；`PurgeTests.swift:92-114` 还验证取消确认后不会执行旧预览。
- AC-004：`re_verified`。检查 `PurgeViewModel.swift:59-62` 与 `PurgeViewModel.swift:124-125`，应用代码只有 dry-run 与 yes 两条 purge 调用路径；测试对调用序列做精确相等断言。
- AC-005：`re_verified`。`PurgeTests.swift:34-49` 注入非零预览结果，断言旧预览失效、`canConfirm == false`、错误 key 与失败摘要均存在。
- AC-006：`re_verified`。`PurgeTests.swift:92-114` 取消确认后立即确认不会执行，只有再次成功预览后才执行 `["purge", "--yes"]`。
- AC-007：`re_verified`。`PurgeTests.swift:139-162` 使用 actor spy、阻塞 continuation 和抛错超时等待，断言重复提交只有一个 yes 进程、Bridge cancel 调用一次、执行结束并显示取消状态。

coverage = 7 / 7

验证命令：`xcodebuild test -scheme Zmole -destination 'platform=macOS'`；63/63 tests passed（PurgeTests 7/7）。

verdict: PASS

# Task review t011（reviewer_focus: 代码）

- task：`t011_purge_run`
- spec：`docs/tasks/t011_purge_run/spec.md`
- diff_anchor：`ff5317f1eb1a4f28cfcc2e38bcd931f5a836866c`
- target：`git -C '/Users/karson/kar/code/zmole_t011' diff ff5317f1eb1a4f28cfcc2e38bcd931f5a836866c`
- round：1
- reviewed_at：2026-09-22 05:30 UTC+8

reviewed_scope: bff74dd02f2ad0e3

## Findings

### t011_code_f001 - Purge 输出摘要逻辑与 Optimize 重复

- 严重度：minor
- 锚点：行为风险；未来摘要或 ANSI 清理规则修改时，两条功能路径可能分叉
- 位置：`src/zmole/Features/Purge/PurgeSnapshot.swift:19-47`；对照 `src/zmole/Features/Optimize/OptimizeSnapshot.swift:19-47`
- 问题：`PurgeOutput.summary` 与 `OptimizeOutput.summary` 及其 `stripANSI` 实现逐行重复。当前行为正确，但同一摘要规则需要维护两份，后续修复或扩展容易遗漏一条路径。
- 建议：抽取到共享的命令输出摘要工具，由 Purge 和 Optimize 复用；保持本 task 的 stdout/stderr 拼接语义不变。

## 结论

- 前轮 finding 复核：Round 1，无前轮 finding。
- 本轮新发现：1 条，均为 minor；无 critical / important。
- 未进表的提示：实现源码与测试源码均未达到文件过大阈值；新增方法未达到需要拆分的圈复杂度阈值；未发现范围外改动、裸 purge 调用、安全注入、同步阻塞 IO 或未处理关键错误。
- 总体判断：Purge 预览、确认执行、`--yes` 门禁、预览失效、忙碌与取消状态均符合契约；仅有一条不阻断的摘要逻辑重复。
- 系统性 follow-up：无。

### AC 复验方式

- AC-001：`re_verified`；`PurgeViewModel.swift:58-63` 只以 `["purge", "--dry-run"]` 发起预览，`PurgeTests.swift:18-21` 独立断言 argv 不含 `--yes`。
- AC-002：`re_verified`；`PurgeViewModel.swift:124-125` 只以 `["purge", "--yes"]` 发起执行，`PurgeTests.swift:82-88` 独立断言不含 `--dry-run`。
- AC-003：`re_verified`；`PurgeViewModel.swift:103-105` 要求 `isConfirmationPresented` 且 `canConfirm` 才能进入执行路径，`PurgeTests.swift:52-64` 在未请求确认时只观察到 dry-run 调用。
- AC-004：`re_verified`；扫描完整 diff 与 `src/zmole` 中的 purge 调用，执行路径只有 `PurgeViewModel.swift:60` 的 dry-run 和 `PurgeViewModel.swift:125` 的 `--yes`，不存在裸 purge argv。
- AC-005：`re_verified`；`PurgeViewModel.swift:65-81` 将非零预览转为失败并清除 preview，`canConfirm` 随之为 false；`PurgeTests.swift:34-50` 复验旧预览失效、确认不可用和失败摘要。
- AC-006：`re_verified`；`PurgeViewModel.swift:37-41` 新预览开始时失效旧 preview，`PurgeViewModel.swift:68-70` 生成新 UUID，`PurgeViewModel.swift:98-101` 取消确认时清除 preview；`PurgeTests.swift:92-114` 复验取消后必须重新 dry-run 才能执行。
- AC-007：`re_verified`；`PurgeViewModel.swift:38`、`103-105` 阻止忙碌或重复执行，`PurgeViewModel.swift:152-155` 将取消转发到 Bridge；`PurgeTests.swift:138-163` 复验只创建一个 `--yes` 调用、调用 cancel 且最终退出忙碌态。

coverage = 7 / 7

XCTest 独立复验：`xcodebuild -project Zmole.xcodeproj -scheme Zmole -configuration Debug -destination 'platform=macOS' test`，63/63 通过。

verdict: PASS

## Round 2 (2026-09-22 05:34 UTC+8)

reviewed_scope: 97a6e83192bbb17b

## Findings

无。

## 结论

- 前轮 finding 复核：`t011_code_f001` 已消除。`src/zmole/Features/MaintenanceOutput.swift:3-31` 现在集中实现摘要拼接与 ANSI 清理；`src/zmole/Features/Optimize/OptimizeViewModel.swift:70,76,130,143` 和 `src/zmole/Features/Purge/PurgeViewModel.swift:70,76,130,143` 均调用同一实现，未发现行为分叉。
- 本轮新发现：0 条。
- 未进表的提示：已扫描正确性、并发与状态、错误处理、契约与 Breaking、安全输入、性能与资源、架构维护性、可观测性及文档/规格一致性；实现源码与测试源码均未达到文件过大阈值，未发现需要拆分的高圈复杂度函数。真删 `node_modules` 按 spec 上下文有意不测。
- 总体判断：Purge 的两套 argv、确认门禁、预览失效、重复执行保护、取消转发和失败摘要均符合 AC；无 critical / important / minor finding。
- 系统性 follow-up：无。

### AC 复验方式

- AC-001：`re_verified`；`src/zmole/Features/Purge/PurgeViewModel.swift:58-63` 使用 `["purge", "--dry-run"]`，不含 `--yes`；`tests/unit/PurgeTests.swift:18-21` 断言 argv 与 stdin。
- AC-002：`re_verified`；`src/zmole/Features/Purge/PurgeViewModel.swift:124-125` 使用 `["purge", "--yes"]`，不含 `--dry-run`；`tests/unit/PurgeTests.swift:82-88` 断言调用序列。
- AC-003：`re_verified`；`src/zmole/Features/Purge/PurgeViewModel.swift:103-105` 要求确认态与 `canConfirm`，未确认路径不会进入执行；`tests/unit/PurgeTests.swift:52-63` 只观察到 dry-run 调用。
- AC-004：`re_verified`；扫描完整 diff 与 `src/zmole` 中的 Purge 调用，执行路径仅有 `PurgeViewModel.swift:60` 的 dry-run 和 `PurgeViewModel.swift:125` 的 `--yes`，不存在裸 purge argv。
- AC-005：`re_verified`；`src/zmole/Features/Purge/PurgeViewModel.swift:64-81` 对非零预览抛出命令失败、清除 preview 并禁止确认；`tests/unit/PurgeTests.swift:34-49` 复验旧 preview 失效与错误摘要。
- AC-006：`re_verified`；`src/zmole/Features/Purge/PurgeViewModel.swift:37-41` 新预览先失效旧 preview，`98-101` 确认取消清除 preview；`tests/unit/PurgeTests.swift:92-114` 复验取消后必须重新 dry-run 才能执行。
- AC-007：`re_verified`；`src/zmole/Features/Purge/PurgeViewModel.swift:38,103-105` 阻止忙碌与重复执行，`152-155` 转发 Bridge cancel；`tests/unit/PurgeTests.swift:138-163` 复验只创建一个 `--yes` 调用、调用 cancel 且最终退出忙碌态。

coverage = 7 / 7

独立验证：`xcodebuild -project Zmole.xcodeproj -scheme Zmole -configuration Debug -destination 'platform=macOS' test`，63/63 通过；`git diff --check` 与 String Catalog JSON 校验通过。

verdict: PASS

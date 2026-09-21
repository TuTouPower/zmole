# Task review t005（reviewer_focus: 通用）

- task：`t005_history_list`
- spec：`docs/tasks/t005_history_list/spec.md`
- diff_anchor：`2c3240d7f0c24376ef615db252aa20ec26f9d958`
- target：`git -C '/Users/karson/kar/code/zmole_t005' diff 2c3240d7f0c24376ef615db252aa20ec26f9d958`
- round：1
- reviewed_at：2026-09-21 18:30 UTC+8

reviewed_scope: 997d6168918ed989

## Findings

### t005_gen_f001 - 空 ended_at 会遮蔽有效 started_at

- 严重度：important
- 锚点：AC-001；源码允许未结束 session 只有非空 `started_at`，列表仍必须展示时间之一。
- 位置：`src/zmole/Features/History/HistorySnapshot.swift:22`、`src/zmole/Features/History/HistorySnapshot.swift:42`、`src/zmole/Features/History/HistoryView.swift:94`
- 问题：`dateText` 使用 `endedAt ?? startedAt`。当 JSON 含 `ended_at: ""`、`started_at` 有值时，空字符串是非 nil，导致 `dateText` 为空；校验也只判断 `dateText != nil`，因此该记录通过解码，UI 随后渲染 `Text("")`，用户看不到会话时间。相同校验只用 `command.isEmpty`，空白 command 也会通过。
- 建议：先 trim，再从非空 `ended_at` 回退到非空 `started_at`；两者都为空或 command 为空白时拒绝记录或进入失败态，并补充对应 fixture/test。

### t005_gen_f002 - UI 展示分支没有渲染级测试

- 严重度：minor
- 锚点：AC-001、AC-002；spec 声明全部 AC 可自动测试。
- 位置：`tests/unit/ZmoleTests.swift:91`、`tests/unit/ZmoleTests.swift:119`、`src/zmole/Features/History/HistoryView.swift:48`
- 问题：现有测试只验证 loader 参数、解码结果和 ViewModel 的数组状态，没有触达 `HistorySessionRow` 的 command/时间展示，也没有验证 `HistorySnapshotContent` 的空态文本；实现改动可能让 UI 分支失效而测试仍通过。
- 建议：增加可测试的 UI 展示投影或渲染测试，覆盖非空会话的 command/时间与 sessions/deletions 全空时的空态。

## 结论

- 本轮新发现：2 条（1 important、1 minor）
- 未进表的提示：`.repo_template/scripts/check_review_status.py` 在当前 Python 3.9.6 导入失败，原因是运行时不支持 `list[...] | None`；这是模板工具链问题，未作为 t005 finding。按要求未运行长模板测试。
- 总体判断：`t005_gen_f001` 违反 AC-001 并阻断通过；`t005_gen_f002` 为非阻断覆盖缺口。
- 系统性 follow-up：无

### AC 复验方式

- AC-001：`re_verified`；独立检查源码字段 fixture、`HistorySessionRow` 展示路径和空值处理，确认空 `ended_at` 场景丢失有效 `started_at`。
- AC-002：`re_verified`；独立检查 `sessions`/`deletions` 双空分支与成功空响应测试，确认状态区分存在，但 UI 空态未被渲染级测试触达。
- AC-003：`re_verified`；独立检查 loader argv 与 `testHistoryLoaderUsesDefaultLimitAndDecodesSessionSummary` 的精确断言。
- AC-004：`re_verified`；独立检查 1–200 钳制、`--limit 1` argv 与 `testHistoryLoaderUsesRequestedLimitWithoutSendingZero`。
- AC-005：`re_verified`；独立检查非零退出/JSON decode 错误到 `errorMessage` 的路径及 `testHistoryViewModelShowsFailureForInvalidJSONAndNonZeroExit`。

coverage = 5 / 5

verdict: FAIL

## Round 2 (2026-09-21 18:38 UTC+8)

reviewed_scope: ceccc7d9edac96fa

## Findings

本轮无新 finding。

## 结论

- 前轮 finding 复核：
  - `t005_gen_f001` 已消除。`HistorySession.dateText` 对空/空白 `ended_at` 使用非空 `started_at` 回退，解码校验同时拒绝空白 `command`；证据：`src/zmole/Features/History/HistorySnapshot.swift:67-97`。非空 `ended_at` fixture 也覆盖回退路径：`tests/unit/ZmoleTests.swift:187-200`。
  - `t005_gen_f002` 已消除。`HistorySnapshot.displayState` 已由 `HistorySnapshotContent` 消费，非空会话与双空数组分别投影为 content/empty；证据：`src/zmole/Features/History/HistorySnapshot.swift:14-21`、`src/zmole/Features/History/HistoryView.swift:48-84`、`tests/unit/ZmoleTests.swift:106-123`。
- 本轮新发现：0 条
- 未进表的提示：无；按用户要求未运行长模板测试。
- 总体判断：前轮 blocker 已消除，当前 diff 无未解决 critical / important；可通过。
- 系统性 follow-up：无

### AC 复验方式

- AC-001：`re_verified`；`HistorySessionRow` 展示 `command`、回退后的 `dateText` 及 `items`/`size`，非空会话 fixture 与投影断言覆盖对应字段。
- AC-002：`re_verified`；`HistorySnapshotContent` 对 `displayState == .empty` 渲染空态，双空 fixture 断言 `.empty`。
- AC-003：`re_verified`；`HistorySnapshotLoader` 默认将 argv 构造为 `history`、`--json`、`--limit`、`20`，测试逐项断言。
- AC-004：`re_verified`；loader 将 limit 钳制到至少 1，limit=1 测试断言 argv 不含 0。
- AC-005：`re_verified`；非零 exit code 与 JSON 解码异常均进入 ViewModel `errorMessage`，对应失败测试覆盖两条路径。

coverage = 5 / 5

verdict: PASS

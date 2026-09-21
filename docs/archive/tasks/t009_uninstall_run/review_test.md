# Task review t009（reviewer_focus: 测试）

- task：`t009_uninstall_run`
- spec：`docs/tasks/t009_uninstall_run/spec.md`
- diff_anchor：`c5264241db883bfce53fbb461ae0c276cde9f337`
- target：`git -C '/Users/karson/kar/code/zmole_t009' diff c5264241db883bfce53fbb461ae0c276cde9f337`
- round：1
- reviewed_at：2026-09-21 21:10 UTC+8

reviewed_scope: 35ecdde696512334

## Findings

### t009_test_f001 - AC-009 未覆盖所选目标从当前 list 消失

- 严重度：minor
- 锚点：AC-009；预览成功后当前 list 可能不再包含所选 path 时，必须禁止执行。
- 位置：`tests/unit/UninstallTests.swift:149` `testUninstallChangedTargetCannotExecute`；`tests/unit/UninstallTests.swift:311` `uninstallChangedPathFixture`
- 问题：现有测试只把目标改成另一条 path，验证了“落到不同 path”分支；没有用 `[]` 或不含原目标的当前 list 验证“目标消失”分支。`UninstallViewModel.confirmExecution()` 的当前 list 校验虽有 `first(where:)`，但若该分支回归为只按 `uninstall_name` 判断，现有测试仍会通过，无法证明目标消失时不会发起 `uninstall Example`。
- 建议：补一条当前 list 为空或不含原目标的 fixture，确认调用序列只到第二次 `uninstall --list`，无不带 `--dry-run` 的 uninstall，且页面进入 changed-target 失败状态。

### t009_test_f002 - 新增交付文件未进入 reviewer 可见 diff

- 严重度：important
- 锚点：审查完整性门禁；本轮要求审查相对 diff 的最终交付内容。
- 位置：`src/zmole/Features/Uninstall/UninstallViewModel.swift`、`src/zmole/Features/Uninstall/UninstallView.swift`、`src/zmole/Features/Uninstall/UninstallSnapshot.swift`、`tests/unit/UninstallTests.swift`；`git status --short` 显示四项 `??`
- 问题：上述实现与测试文件仍是未跟踪文件，因此 `git diff c5264241db883bfce53fbb461ae0c276cde9f337` 和 `git diff --name-status` 看不到它们。虽然本轮直接读取并运行了这些文件，但无法证明 `reviewed_scope` 对应的是 reviewer 可见的最终 diff；按 prompt 的门禁规则，本轮只能判定为 INCOMPLETE，不能把当前报告当作完整最终 diff 的 PASS。
- 建议：由实施侧在重新派审前对四个明确的新交付文件执行 `git add -N`，保留工作树内容后重新生成/校验 scope，再进行下一轮完整测试评审。

## 结论

- 前轮 finding 复核：Round 1，无前轮 finding。
- 改测方向复核：未发现就地修改既有测试预期；本轮新增测试均围绕卸载 ViewModel 与进程边界 spy。`UninstallProcessSpy` 位于 `MoleProcessControlling` 外部进程边界，未 mock 被测 ViewModel。
- 异步等待复核：`testUninstallBusyExecutionCannotStartTwiceAndCanCancel` 通过 `waitForInvocationCount(4)` 等待真实执行调用，等待器在 1,000 次 1ms 轮询后抛出 `UninstallSpyWaitError.timeout`；没有把超时当作成功。取消后等待原执行 task 完成，并断言 cancel 次数、执行状态和取消错误。
- 危险模式扫描：未发现恒真断言、删除/注释断言、`.skip`/`.only`、静默类型错误、关键副作用 mock 或无条件跳过；`try?` 仅用于轮询 sleep，计数超时仍抛错。
- AC 复验方式：
    - AC-001：`re_verified`；`testUninstallListDecodesDisplayedFieldsAndViewWiring` 通过真实 `UninstallViewModel.loadList()` 解码 JSON，并断言四个字段；同时检查 `UninstallView` 对四字段的展示接线。
    - AC-002：`re_verified`；`testUninstallPreviewUsesSelectedNameAndConfirmationInput` 精确断言 `uninstall --dry-run Example` 与 `Data("y\\n".utf8)`。
    - AC-003：`re_verified`；预览测试在确认前精确断言调用序列只含 `--list` 与 `--dry-run`，没有生产 uninstall。
    - AC-004：`re_verified`；`testUninstallConfirmationExecutesWithoutPermanentAndShowsSummary` 扫描全部 spy 调用，断言不存在 `--permanent`。
    - AC-005：`re_verified`；`testUninstallNoSelectionDoesNotPreviewOrExecute` 在无 selection 下只允许初始 `--list`，并断言 no-selection 错误与不可确认状态。
    - AC-006：`re_verified`；成功测试精确断言无 `--dry-run` 的执行 argv、`y\\n` stdin 与成功摘要；失败测试断言 stdout/stderr 摘要和非零错误。
    - AC-007：`re_verified`；`testUninstallDuplicateNameCannotPreview` 使用相同 `uninstall_name`、不同 path 的两条记录，断言不发起 dry-run、返回 ambiguous 错误且无 preview。
    - AC-008：`re_verified`；`testUninstallChangingSelectionExpiresPreviewUntilNewPreview` 断言 selection 变化后 preview 清空、不可确认，重新预览后才针对新 App 发起 dry-run。
    - AC-009：`re_verified`；已独立复验“path 改变”分支并确认无生产 uninstall；“目标消失”分支未覆盖，见 `t009_test_f001`。
    - AC-010：`re_verified`；`testUninstallAbortedPreviewCannotConfirm` 使用非零 exit、`Aborted` stderr，断言调用结束后无 preview、不可确认且展示失败信息。
    - AC-011：`re_verified`；`testUninstallBusyExecutionCannotStartTwiceAndCanCancel` 等待执行调用进入阻塞态，第二次确认不产生第二个执行调用，取消会调用 spy cancel 并结束 busy 状态。
- coverage = 11 / 11
- 未进表的提示：AC-001 的 UI 接线使用源文件字符串断言而非渲染快照；当前测试仍同时经过真实 decoder 与 View source 接线，属于可维护性提示，不单独阻断。本轮独立运行 `xcodebuild ... test`：48 tests，0 failures，其中 `UninstallTests` 10 tests，0 failures。
- 总体判断：行为测试覆盖主要 AC，目标消失变体需补测；由于四个新增交付文件未纳入 reviewer 可见 diff，本轮审查完整性为 INCOMPLETE，按门禁判定 FAIL。
- 系统性 follow-up：无。

verdict: FAIL

## Round 2 (2026-09-21 21:16 UTC+8)

reviewed_scope: f4e6a4140554b220

## Findings

本轮新发现：0。

## 结论

- 前轮 finding 复核：
    - `t009_test_f001` 已消除。`tests/unit/UninstallTests.swift:173-194` 的 `testUninstallMissingTargetCannotExecute` 用当前 list 为 `[]` 的夹具复核目标消失分支，精确断言调用止于第二次 `uninstall --list`，没有生产 uninstall，并断言 `uninstall.error.changed_target` 与 preview 失效。
    - `t009_test_f002` 已消除。`git -C '/Users/karson/kar/code/zmole_t009' status --short` 显示四个新增交付文件为 intent-to-add，`git -C '/Users/karson/kar/code/zmole_t009' diff c5264241db883bfce53fbb461ae0c276cde9f337` 已包含完整源码与测试；当前 scope 与 prompt 一致。
- 改测方向复核：无。新增目标消失测试补充未覆盖分支，没有就地修改既有测试预期迁就实现。
- 异步等待复核：`tests/unit/UninstallTests.swift:248-276` 等待执行调用进入阻塞态，`waitForInvocationCount` 在 `tests/unit/UninstallTests.swift:412-417` 超时会抛出错误；取消后等待原执行 task 完成，并断言仅一次执行、一次 cancel、busy 结束和取消错误。未发现静默超时或漏 await。
- 危险模式扫描：未发现恒真断言、删除/反转/注释断言、`.skip`/`.only`、静默类型错误、关键副作用 mock 或条件跳过。`try?` 仅包裹轮询 sleep，计数超时仍抛错。源文件字符串断言用于补充 View 字段接线，核心行为仍由真实 ViewModel、JSON 解码和进程边界 spy 验证。
- AC 复验方式：
    - AC-001：`re_verified`；`testUninstallListDecodesDisplayedFieldsAndViewWiring` 通过 `loadList()` 解码夹具并断言 `name`、`uninstall_name`、`path`、`bundle_id`，同时核对 `UninstallView` 四字段接线。
    - AC-002：`re_verified`；`testUninstallPreviewUsesSelectedNameAndConfirmationInput` 精确断言 `uninstall --dry-run Example` 与 `Data("y\\n".utf8)`。
    - AC-003：`re_verified`；预览测试精确断言确认前调用序列只含 `uninstall --list` 和 dry-run，不含生产 uninstall。
    - AC-004：`re_verified`；`testUninstallConfirmationExecutesWithoutPermanentAndShowsSummary` 扫描全部 spy 调用，断言不存在 `--permanent`。
    - AC-005：`re_verified`；`testUninstallNoSelectionDoesNotPreviewOrExecute` 断言无选择时只发生初始 list，且返回 no-selection、不可确认。
    - AC-006：`re_verified`；成功测试精确断言无 dry-run 的执行 argv、`y\\n` stdin 和成功摘要；`testUninstallExecutionFailureShowsSummary` 断言 stdout/stderr 摘要与非零错误。
    - AC-007：`re_verified`；`testUninstallDuplicateNameCannotPreview` 用同名不同 path 夹具断言不发起预览，返回 ambiguous 错误且无 preview。
    - AC-008：`re_verified`；`testUninstallChangingSelectionExpiresPreviewUntilNewPreview` 断言改选后 preview 清空、不可确认，重新预览后才针对新 App 发起 dry-run。
    - AC-009：`re_verified`；`testUninstallChangedTargetCannotExecute` 覆盖 path 改变，`testUninstallMissingTargetCannotExecute` 覆盖目标消失；两者均断言不会执行 uninstall。
    - AC-010：`re_verified`；`testUninstallAbortedPreviewCannotConfirm` 使用非零 exit 与 `Aborted` 结果，断言预览失效、不可确认且展示失败信息。
    - AC-011：`re_verified`；`testUninstallBusyExecutionCannotStartTwiceAndCanCancel` 独立复核执行中不可重复启动，取消会终止该 Process 并结束 busy。
- coverage = 11 / 11
- 未进表的提示：AC-001 的 View 接线采用源文件字符串断言，未使用渲染快照；现有测试同时经过真实 JSON 解码和 ViewModel 路径，属于可维护性提示，不构成 blocking finding。
- 独立验证：`xcodebuild test -scheme Zmole -destination 'platform=macOS'` 通过，49 tests，0 failures；其中 `UninstallTests` 11 tests，0 failures。
- 总体判断：前轮覆盖缺口和 diff 完整性门禁均已修复；当前完整交付内容无未解决 critical / important finding。
- 系统性 follow-up：无。

verdict: PASS

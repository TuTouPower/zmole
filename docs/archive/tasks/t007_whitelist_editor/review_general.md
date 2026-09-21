# Task review t007（reviewer_focus: 通用）

- task：`t007_whitelist_editor`
- spec：`docs/tasks/t007_whitelist_editor/spec.md`
- diff_anchor：`b36a005650b6ad5d99226d85f896e3991f0573c6`
- target：`git -C '/Users/karson/kar/code/zmole_t007' diff b36a005650b6ad5d99226d85f896e3991f0573c6`
- round：1
- reviewed_at：2026-09-21 19:41 UTC+8

reviewed_scope: fdfb0d21b4890f7d

## Findings

### t007_gen_f001 - 读取失败后仍可覆盖原白名单文件

- 严重度：important
- 锚点：行为缺陷 + 数据丢失；现有文件读取失败时仍可继续添加并保存
- 位置：`src/zmole/Features/Whitelist/WhitelistViewModel.swift:34-39,42-60,88-93`
- 问题：已有 whitelist 文件遇到无效 UTF-8、权限错误或其他读取错误时，`load()` 将 `document` 置为 nil 并显示错误；随后 `addPattern()` 仍允许输入，`updateDocument()` 会用默认头替代失败读取的原文，`save()` 再把默认头和新模式写回同一 URL。用户只需在错误页输入模式并点击 Add/Save，就可能覆盖原配置内容。
- 建议：读取失败时保持编辑和保存禁用；`addPattern`/删除操作要求已有成功加载的 `document`。默认头只用于“文件不存在”的正常初始状态，不能作为读取失败后的回退文档。

### t007_gen_f002 - 重复模式无法按单行删除

- 严重度：important
- 锚点：AC-003；删除一条模式行会删除全部同名行
- 位置：`src/zmole/Features/Whitelist/WhitelistView.swift:57-63`、`src/zmole/Features/Whitelist/WhitelistViewModel.swift:62-64`
- 问题：列表使用模式文本作为 `ForEach` 唯一 ID，删除回调只传文本；`removePattern` 使用 `removeAll { $0 == pattern }`。当夹具或已有文件包含两行相同模式时，两个 UI 行共享 ID，点击任一删除按钮都会移除全部同名行并在保存时一并丢失，无法满足“删除一条”。
- 建议：为每个模式行保留稳定的行/索引 ID，删除按单个索引或行 ID 操作；增加重复模式夹具，验证列表与保存结果只移除目标行。

### t007_gen_f003 - AC-004 测试没有建立 spawn spy

- 严重度：important
- 锚点：AC-004；“本功能不 spawn mole 进程（单测 spy）”
- 位置：`tests/unit/ZmoleTests.swift:251-263`
- 问题：`testWhitelistEditorUsesOnlyInjectedFilePath` 只注入临时文件 URL、检查文件存在，并没有 spy、调用计数或其他进程启动断言。若后续实现误在白名单流程中创建 `MoleBridge` 并 spawn mole，这个测试仍会通过；现有代码静态上没有该调用，但没有满足 spec 指定的自动测试证据。
- 建议：增加可注入的 bridge/process seam 或 command-runner spy，在 load、add、delete、save 流程断言调用次数为零，同时保留临时文件夹具。

## 结论

- 本轮新发现：3 条
- 未进表的提示：已覆盖规格合规、实现正确性、安全、契约与类型、性能与资源、架构可维护性、健壮性与可观测、测试与文档一致性；没有其他范围内 finding。diff 中 `tests/unit/ZmoleTests.swift:340-342` 对 Analyze 测试等待逻辑的改动与本 task 无关，作为范围外观察不进表。
- 总体判断：当前存在两条重要行为缺陷，且 AC-004 的指定 spy 覆盖缺失，不能通过。
- 系统性 follow-up：无，均可在当前 task 内修复。

### AC 复验方式

- AC-001：`re_verified` — 独立运行 `xcodebuild test -scheme Zmole -destination 'platform=macOS'`，26/26 通过；`testWhitelistStoreListsPatternsAndPreservesComments` 对临时夹具精确断言非注释模式，`WhitelistView.swift:48-70` 将加载模式列出。
- AC-002：`re_verified` — `testWhitelistViewModelAddsDeletesAndSavesPatterns` 使用临时 URL 添加模式并保存，独立读取文件确认新行存在。
- AC-003：`re_verified` — 同一 XCTest 流程删除模式并保存，独立读取文件确认该行消失；重复模式边界由 finding `t007_gen_f002` 记录。
- AC-004：`re_verified` — 白名单 feature 源码未引用 `MoleBridge`/直接 `Process`，独立测试通过；但 spec 要求的 spawn spy 缺失，见 finding `t007_gen_f003`。

coverage = 4 / 4

verdict: FAIL

## Round 2 (2026-09-21 19:50 UTC+8)

reviewed_scope: 4e587c80a5d40a06

## Findings

- 本轮新发现：0 条。

## 结论

- 前轮 finding 复核：
  - `t007_gen_f001` 已消除。`WhitelistViewModel.load()` 读取失败时清空 `document`，`addPattern`、`removePattern` 和 `save` 均拒绝无成功加载文档的操作；错误状态下 UI 不显示编辑栏和可用保存按钮。`testWhitelistViewModelCannotOverwriteAfterLoadFailure` 独立确认原始字节未被覆盖。
  - `t007_gen_f002` 已消除。模式行使用独立 UUID，UI 删除按行 ID 传递；`testWhitelistViewModelRemovesOneDuplicatePattern` 以两条相同模式为夹具，保存后确认只剩一条。
  - `t007_gen_f003` 已消除。白名单流程注入 `MoleCommandRunning` spy，覆盖 load、add、save 后断言调用次数为零；白名单实现本身未引用 `MoleBridge` 或 `Process`。
- 本轮新发现：0 条。
- 未进表的提示：`moleProcess` 注入点当前只用于证明白名单流程不调用命令 runner；这是测试 seam，不影响当前行为。其余规格、实现正确性、安全、契约与类型、性能与资源、架构可维护性、健壮性与可观测性、测试可信度、文档与配置一致性均已复核，无范围内问题。
- 总体判断：Round 1 的三个 blocking finding 均已由当前 diff、代码和独立 XCTest 复核消除。
- 系统性 follow-up：无。

### AC 复验方式

- AC-001：`re_verified` — 独立运行 `xcodebuild -project Zmole.xcodeproj -scheme Zmole -destination 'platform=macOS' test`，29/29 通过；`testWhitelistStoreListsPatternsAndPreservesComments` 从临时夹具读取并精确断言非注释模式。
- AC-002：`re_verified` — `testWhitelistViewModelAddsDeletesAndSavesPatterns` 向临时文件添加模式并保存，再从文件内容确认新行存在。
- AC-003：`re_verified` — 同一 XCTest 流程确认删除后目标行不存在；`testWhitelistViewModelRemovesOneDuplicatePattern` 额外确认重复行只删除一条。
- AC-004：`re_verified` — `testWhitelistEditorDoesNotRunMoleProcess` 注入 `WhitelistMoleProcessSpy`，完整执行 load、add、save 后确认调用次数为零；白名单源码检索无 `MoleBridge`/`Process`。

coverage = 4 / 4

verdict: PASS

# Task review t006（reviewer_focus: 通用）

- task：`t006_analyze_browser`
- spec：`docs/tasks/t006_analyze_browser/spec.md`
- diff_anchor：`145c21f2ee8132717638b9935fc1e9afcbd9dfc4`
- target：`git -C '/Users/karson/kar/code/zmole_t006' diff 145c21f2ee8132717638b9935fc1e9afcbd9dfc4`
- round：1
- reviewed_at：2026-09-21 19:10 UTC+8

reviewed_scope: 505299d3090fca6b

## Findings

### t006_gen_f001 - 加载期间返回会并发触发 Bridge busy 并覆盖导航状态

- 严重度：important
- 锚点：行为缺陷；用户在下钻加载期间点击 Back 时，界面应能返回上级并展示对应结果，但当前流程会显示 Bridge busy 错误或留下与当前路径不一致的快照。
- 位置：`src/zmole/Features/Analyze/AnalyzeView.swift:35-41`、`src/zmole/Features/Analyze/AnalyzeViewModel.swift:72-100`
- 问题：点击目录后，`loadCurrentPath()` 在第 88 行先把 `canGoBack` 设为真，再在第 97 行等待 mole。此时视图只显示 ProgressView，但工具栏 Back 仍可点击。若用户立即点击 Back，`goBack()` 会在前一个 `bridge.run(["analyze", "--json", path])` 未完成时再次调用同一个 `MoleBridge`；Bridge 返回 `busy`，Back 请求把 `errorMessage` 设为错误并结束。先发出的下钻请求完成后仍会在第 97 行把子目录快照写回，且没有校验请求是否仍对应当前 `pathStack`，最终可能出现“busy”错误覆盖界面，或快照与当前路径栈不一致。
- 建议：加载期间禁用 Back（至少给第 38 行按钮加 `.disabled(viewModel.isLoading)`），并为导航请求增加取消/序列号校验，确保过期请求不能提交 `snapshot`、`errorMessage` 和 `isLoading` 状态。

### t006_gen_f002 - 下钻和 UI 展示测试未断言可观察条目内容

- 严重度：minor
- 锚点：AC-001、AC-002；spec 将这些行为声明为自动可测。
- 位置：`tests/unit/ZmoleTests.swift:205-227`、`src/zmole/Features/Analyze/AnalyzeView.swift:62-83`
- 问题：导航测试只断言 overview/子路径的 `snapshot.path` 与 argv，没有断言下钻后快照含子夹具的 `Utilities` 条目；也没有触达 `AnalyzeSnapshotContent` 对 name/size 的实际展示路径。实现若误把下钻结果替换为 overview、或改坏条目渲染，当前测试仍可通过。
- 建议：增加可测试的展示投影或渲染级测试，断言 overview 的 name/size、下钻的 child entries，以及只存在目录导航、刷新和返回动作而没有删除/移到废纸篓动作。

## 结论

- 本轮新发现：2 条（1 important、1 minor）。
- 未进表的提示：首次并行执行 test/build 触发共用 DerivedData 的 build database lock，随后串行重跑通过；Release build 通过。未运行长模板测试；AC-005 属部署态人工验证，本轮按只读 review 范围未启动 App。
- 总体判断：下钻加载期间 Back 可触发并发请求，造成可观察的错误和状态覆盖，important finding 阻断通过。
- 系统性 follow-up：无。

### AC 复验方式

- AC-001：`re_verified`；`AnalyzeSnapshotContent` 明确渲染 `entry.name` 与 `ByteCountFormatter` 生成的 size，overview fixture 和单测分别断言 name/size；串行 `xcodebuild test` 21/21 通过。
- AC-002：`re_verified`；`AnalyzeSnapshotLoader.load(path:)` 固定构造 [`analyze`, `--json`, path]，`AnalyzeViewModel.openDirectory` 将 loader 返回值写入当前 snapshot，导航测试精确断言 argv 顺序与子路径；条目内容断言不足已列为 minor。
- AC-003：`re_verified`；`goBack()` 移除 pathStack 末项并重新调用 loader，测试精确断言返回 overview 的 argv 与 path。
- AC-004：`re_verified`；审查 AnalyzeView 全部动作，仅有目录 Button、Back 和 Refresh，没有删除、trash 或 destructive action；测试也未注入任何删除副作用。
- AC-005：`trust_prior`；本轮只读代码/测试/文档，未启动部署态 App；仅核对 `AnalyzeViewModel.init()` 使用默认 Bundle 的 `MoleBridge`，以及现有 spike 对 analyze JSON 形状的记录，不能替代 overview/下钻/返回的本机人工验证。

coverage = 4 / 5

verdict: FAIL

## Round 2 (2026-09-21 19:17 UTC+8)

reviewed_scope: aa2b03bccb295206

## Findings

本轮未发现新 finding。

## 结论

- 前轮 finding 复核（Round 1）：
  - `t006_gen_f001` 已消除。`AnalyzeView` 在 `src/zmole/Features/Analyze/AnalyzeView.swift:37-48` 对 Back 与 Refresh 禁用加载期间操作；`AnalyzeViewModel` 在 `src/zmole/Features/Analyze/AnalyzeViewModel.swift:67-83` 对 overview、下钻、返回统一防重入。`tests/unit/ZmoleTests.swift:251-287` 独立验证目录加载期间 Back 不会产生第二次命令，加载完成后仍展示下钻结果。
  - `t006_gen_f002` 已消除。`AnalyzeSnapshotContent` 在 `src/zmole/Features/Analyze/AnalyzeView.swift:58-84` 消费展示投影条目，`AnalyzeEntryRow` 在 `src/zmole/Features/Analyze/AnalyzeView.swift:91-102` 渲染 name 与 size；`tests/unit/ZmoleTests.swift:193-209`、`230-233` 已断言 overview 与下钻夹具条目。
- 本轮新发现：0 条。
- 未进表的提示：无。已检查规格合规、实现正确性、安全、类型与契约、性能与资源、架构可维护性、健壮性与可观测性、测试可信度及文档配置一致性。
- 总体判断：Round 1 的 important 并发导航问题已由 UI 与 ViewModel 双重防重入消除，当前 diff 无未解决的 critical/important finding。
- 系统性 follow-up：无。

### AC 复验方式

- AC-001：`re_verified`；`AnalyzeSnapshotContent` 遍历 `displayState.entries` 并由 `AnalyzeEntryRow` 显示 `entry.name` 与 `ByteCountFormatter` size，测试断言 overview 条目的 name/size；独立 `xcodebuild test` 通过 23/23。
- AC-002：`re_verified`；`AnalyzeSnapshotLoader.load(path:)` 在 `src/zmole/Features/Analyze/AnalyzeViewModel.swift:19-23` 固定生成 `analyze`, `--json`, path，导航测试断言下钻 argv 与 `Utilities` 条目。
- AC-003：`re_verified`；`goBack()` 在 `src/zmole/Features/Analyze/AnalyzeViewModel.swift:79-83` 移除当前路径并重新加载，导航测试断言返回 overview 条目与无 Back 状态。
- AC-004：`re_verified`；Analyze 页面仅注册目录下钻、Back、Refresh 三类动作，`src/zmole/Features/Analyze/AnalyzeView.swift:35-84` 未提供删除或移到废纸篓操作。
- AC-005：`trust_prior`；本轮未启动部署态 App，依赖实施侧已有本机 CUA 证据，无法由本轮代码/单测独立替代 overview、下钻、返回的人工验证。

coverage = 4 / 5
建议合并前人工抽查 trust_prior 项。

verdict: PASS

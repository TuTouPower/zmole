---
tid: "t008"
slug: "clean_run"
title: "clean 预览确认后执行"
status: "done"
branch: "t008_clean_run"
worktree: ""
review_level: "full"
review_limit: "5"
verify_limit: "5"
diff_anchor: "e1bfc29e87ddc097449c5b2218997626026faca4"
depends_on: "t003"
conflicts_with: ""
note: ""
---

# Task 过程总账

front matter 只经 `task.py` 修改；reviewer 只写对应 `review_*.md`。

## 实施笔记

执行期记录关键步骤、决策、验证、阻塞和用户批准的新轮次上限。

创建期不预测实施步骤。只记有追溯价值的内容；无事项时写“无”。

- 新增 clean preview generation/store：每次预览先移除旧 `clean-list.txt`，只读取本次 dry-run 写出的文件；文件缺失、空文件、失败或内容变化均使确认失效。
- 新增 `CleanViewModel`/`CleanView` 生命周期：预览 `clean --dry-run`、确认后 `clean`、确认取消、执行取消、重复执行防重入、Bridge cancel 与失败摘要；ContentView 持有共享 VM，切换侧栏不自动重跑。
- 新增 clean 三语文案与初始化失败本地化；AC-005 测试同时锁定 catalog 语义和 `CleanView` 文案接线。
- XCTest 38/38；Debug、Release 构建通过；signed Release universal/codesign 通过；bundled mole 1.55.0；模板 pytest 480 passed；格式、JSON、diff 检查通过。

## Review 处置

每个结构化 finding 一行。`已修` 表示本 task 已修复；`遗留` 必须指向 `pNNN` 或 follow-up tid；`撤回` 必须写清理由。critical/important 未解决时不得 PASS。

### Round 1–5

|finding_id|severity|status|rationale|fix_ref|
|---|---|---|---|---|
|t008_code_f001|important|已修|失败路径保留 stdout/stderr 并展示合并摘要，补充非零执行测试|src/zmole/Features/Clean/CleanViewModel.swift:133-145；tests/unit/ZmoleTests.swift|
|t008_code_f002|minor|已修|clean 错误与 Bridge 初始化失败统一改用三语 String Catalog|src/zmole/Features/Clean/CleanViewModel.swift:16-57；src/zmole/Resources/Localizable.xcstrings|
|t008_test_f001|important|已修|AC-005 测试断言三语指定语义，并断言 `CleanView` 实际接入该 key|tests/unit/ZmoleTests.swift:430-471|
|t008_test_f002|important|已修|补充旧列表、未写列表与 dry-run 非零路径，确认不可执行且不回读旧文件|tests/unit/ZmoleTests.swift:389-418|
|t008_test_f003|important|已修|失败测试精确断言 stdout/stderr 摘要与非零错误|tests/unit/ZmoleTests.swift:503-528|
|t008_test_f004|important|已修|执行占用前置断言，spy 等待超时抛错并精确核对单次执行|tests/unit/ZmoleTests.swift:452-477；tests/unit/ZmoleTests.swift:846-851|

Round 2–5 逐轮复核前轮 finding；Round 5 两轴 `verdict: PASS`，review scope `b3700c2d73fcb37c`，无遗留 critical/important/minor。

无 finding 时写“Round N 零 finding”。

## 收尾报告

### 验收与验证

- spec：[`spec.md`](spec.md)
- 结果：全部满足
- 测试：XCTest 38/38；Debug、Release 构建；signed Release universal/codesign；bundled mole 1.55.0；模板 pytest 480 passed；`md_format.py --check`、JSON 与 `git diff --check` 通过。
- 黑盒：`testing.md` 的 `blackbox_verify` 未定义；本 task 未对真实 clean 执行破坏性操作，全部行为由临时 list 文件与 Bridge spy 验证。
- review：full Round 5，代码轴与测试轴均 PASS。
- AC 证据：见 `handoff.json`

### 结果摘要

- 完成 clean 预览、确认后执行和取消/失败/忙碌生命周期；无遗留 finding。

---
tid: "t023"
slug: "installer_page"
title: "安装包页预览后移除"
status: "done"
branch: "t023_installer_page"
worktree: ""
review_level: "full"
review_limit: "5"
verify_limit: "5"
diff_anchor: "8c35388de81115ebafabe95b9a5520bab481e3e1"
depends_on: "t015,t022"
conflicts_with: ""
note: "安装包页走预览确认，不进 TUI。"
---

# Task 过程总账

front matter 只经 `task.py` 修改；reviewer 只写对应 `review_*.md`。

## 实施笔记

执行期记录关键步骤、决策、验证、阻塞和用户批准的新轮次上限。

创建期不预测实施步骤。只记有追溯价值的内容；无事项时写“无”。

来源：docs/design/refactor_grilling.md。用户于 2026-10-16 批准后创建。

- 新增 `InstallerInterface.swift`（t022 接口的 Swift 包装：`installer --list-json` 解码 + `installer --remove <path> --size ... --identity ...`）与 `InstallersViewModel`（扫描列出、多选/全选/清空、按本次列出快照确认、逐项移除并保留失败原因）。
- 重写 `InstallersView`：统计条、搜索、列表（类型/名称/来源/大小）、勾选与底部移除条、失败卡；确认框写明选中数量与“移入废纸篓”。
- `OperationCoordinator` 增 `.installer` 写操作；`AppDependencies`/`AppShellView` 装配；demo 夹具提供安装包列表。
- 测试 `tests/unit/InstallersPageTests.swift`：只调非交互列出、确认前 0 删除、确认 argv 只含选中且已列出路径、新扫描使旧确认失效、取消后须重新确认、失败路径保留原因、确认数量、文案。
- 黑盒：GUI 受限（同前），以假接口自动断言替代。

## Review 处置

review_level=full：`review_code.md` / `review_test.md`。

|finding_id|severity|status|rationale|fix_ref|
|---|---|---|---|---|
|t023_code_f001|important|已修|确认框未写选中数量，给确认视图加 detail 并显示 count·size|DestructiveConfirmation.swift / InstallersViewModel.swift|
|t023_code_f002|minor|已修|扫描中仍可确认，canConfirm 加 !isListing/!isRemoving|InstallersViewModel.swift|
|t023_code_f003|minor|已修|租约冲突显示原始键，改 String(localized:)|InstallersViewModel.swift|
|t023_code_f004|minor|撤回|遗留死文案键，属资源清理 nit|Localizable.xcstrings|
|t023_test_f001|minor|已修|补 AC-004 取消后须重新确认断言|InstallersPageTests.swift|
|t023_test_f002|minor|已修|未确认时 confirmRemoval 早退断言|InstallersPageTests.swift|
|t023_test_f003|minor|撤回|AC-006 由键断言 + 生产引用检视确认|InstallersView.swift|
|t023_test_f004|minor|撤回|count 断言偏弱但已足够定位多选计数|InstallersPageTests.swift|

## 收尾报告

### 验收与验证

- spec：[`spec.md`](spec.md)
- 结果：全部满足
- 测试：`xcodebuild test -scheme Zmole -destination 'platform=macOS'`：170 tests / 0 failures；`pytest .repo_template/tests -q -m contract`：147 passed
- 黑盒：GUI 受限（同前）；列出/选择/确认/移除/失败由假接口自动覆盖
- review：`review_code.md`（rounds 1-2）、`review_test.md`（rounds 1-2）最终均 PASS
- AC 证据：见 `handoff.json`

### 结果摘要

- 安装包页消费 t022 非交互接口：扫描列出本次候选，多选/全选/清空，确认框写明数量并移入废纸篓，仅移除选中且仍在本次列出中的路径；新扫描使旧确认失效；被接口拒绝的路径保留原因。遗留：无（minor nit 已撤回）。

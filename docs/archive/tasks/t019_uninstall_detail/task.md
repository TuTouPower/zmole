---
tid: "t019"
slug: "uninstall_detail"
title: "卸载列表详情与多选"
status: "done"
branch: "t019_uninstall_detail"
worktree: ""
review_level: "full"
review_limit: "5"
verify_limit: "5"
diff_anchor: "88be325cacc5c76cdc0a7c76bfea2436df35953b"
depends_on: "t015"
conflicts_with: ""
note: "列表加详情，保留批量卸载。"
---

# Task 过程总账

front matter 只经 `task.py` 修改；reviewer 只写对应 `review_*.md`。

## 实施笔记

执行期记录关键步骤、决策、验证、阻塞和用户批准的新轮次上限。

创建期不预测实施步骤。只记有追溯价值的内容；无事项时写“无”。

来源：docs/design/refactor_grilling.md。用户于 2026-10-16 批准后创建。

- 新增 `UninstallMetadata.swift`：`UninstallMetadataProviding` / `FileRevealing` 协议 + 本机实现（Info.plist 版本、Spotlight 最近使用、NSWorkspace 揭示），可注入替身。
- `UninstallViewModel` 增加 `focusedAppID`/`metadataByID`/`relatedPathsByID`、`focus`、`loadDetail`（元数据）、`loadRelatedFiles`（该项 dry-run，显式按钮触发并持 `.uninstall` 租约，避免与批处理争用单槽 bridge）、`revealInFinder`；`UninstallApp` 增 `sizeText`（不可解析为 nil→未知）。抽出 `UninstallListFilter.visible`（搜索只隐藏不清选择）。
- 重写 `UninstallView`：左列表 + 右详情，补上 `DestructiveConfirmationView` 确认（此前无视图渲染卸载确认，属 t015 移除 ContentView 时遗留的可达性缺口），列表行系统图标 + 勾选 + 焦点，详情展示版本/最近使用（缺失未知）、path、bundle id、只来自 dry-run 的关联文件、在 Finder 中显示、移到废纸篓。
- `docs/design/ui_contract.md` 更新卸载页结构。
- 黑盒：GUI 受限（同前）；已用自动化门禁替代。

## Review 处置

每 finding 一行。review_level=full：`review_code.md` / `review_test.md`。

|finding_id|severity|status|rationale|fix_ref|
|---|---|---|---|---|
|t019_code_f001|important|已修|卸载确认 UI 缺失，补 DestructiveConfirmationView|UninstallView.swift|
|t019_code_f002|important|已修|关联 dry-run 失败不再永久记「无文件」|UninstallViewModel.swift|
|t019_code_f003|minor|已修|元数据读取移出主线程|UninstallMetadata.swift|
|t019_code_f004|minor|已修|不可解析 size 显示未知|UninstallSnapshot.swift / UninstallView.swift|
|t019_code_f005|minor|撤回|dry-run 路径解析按行前缀，契约窄且由 AC-004 用例覆盖|UninstallViewModel.swift|
|t019_code_f006|minor|已修|补 AC-001 过滤保留选择用例|UninstallDetailTests.swift|
|t019_code_f007|minor|撤回|孤儿本地化键多为既有，属清理范畴|Localizable.xcstrings|
|t019_code_f008|important|已修|关联 dry-run 改为显式动作并持租约，避免与批处理争用|UninstallViewModel.swift / UninstallView.swift|
|t019_code_f009|minor|撤回|缺少加载反馈/刷新未纳入协调，属体验与长期架构项，非阻断|UninstallView.swift|
|t019_test_f001|minor|已修|AC-001 抽 UninstallListFilter 并断言|UninstallDetailTests.swift|
|t019_test_f002|minor|已修|size「0」→未知断言|UninstallDetailTests.swift|
|t019_test_f003|minor|撤回|AC-003 已断言数据源 nil，UI 映射由文案键覆盖|UninstallDetailTests.swift|
|t019_test_f004|minor|撤回|dry-run 归属由精确路径断言覆盖|UninstallDetailTests.swift|
|t019_test_f005|minor|已修|补批量执行 argv 端到端断言|UninstallDetailTests.swift|
|t019_test_f006|minor|撤回|取消用例已断言无执行调用|UninstallDetailTests.swift|
|t019_test_f007|minor|撤回|租约互斥分支未单测，属体验边界，非阻断|UninstallViewModel.swift|

## 收尾报告

### 验收与验证

- spec：[`spec.md`](spec.md)
- 结果：全部满足
- 测试：`xcodebuild test -scheme Zmole -destination 'platform=macOS'`：145 tests / 0 failures；`pytest .repo_template/tests -q -m contract`：147 passed
- 黑盒：GUI 受限（同前）；列表/详情/元数据/dry-run/确认由可视化测试覆盖
- review：`review_code.md`（rounds 1-3）、`review_test.md`（rounds 1-3）最终均 PASS
- AC 证据：见 `handoff.json`

### 结果摘要

- 卸载页改为左列表 + 右详情并保留真多选与批量废纸篓；补上此前缺失的确认 UI；版本/最近使用读本机元数据缺失显示未知；关联文件只来自该项 dry-run；size 不可解析显示未知；多选合计标为应用本体估计；在 Finder 中显示用真实 path。遗留：minor 体验项（加载反馈、刷新协调）已撤回。

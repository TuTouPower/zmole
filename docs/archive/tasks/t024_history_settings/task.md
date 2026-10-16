---
tid: "t024"
slug: "history_settings"
title: "历史页与设置页"
status: "done"
branch: "t024_history_settings"
worktree: ""
review_level: "single"
review_limit: "5"
verify_limit: "5"
diff_anchor: "cb934138cb075b79802ed765e1cff753e8c1a3aa"
depends_on: "t015"
conflicts_with: ""
note: "历史导出、登录项、两份白名单；不做菜单栏常驻。"
---

# Task 过程总账

front matter 只经 `task.py` 修改；reviewer 只写对应 `review_*.md`。

## 实施笔记

执行期记录关键步骤、决策、验证、阻塞和用户批准的新轮次上限。

创建期不预测实施步骤。只记有追溯价值的内容；无事项时写“无”。

来源：docs/design/refactor_grilling.md。用户于 2026-10-16 批准后创建。

- 新增 `AppAppearance`（跟随系统/浅色/深色，`@AppStorage`）、`LoginItem`（`LoginItemControlling` 协议 + `SMAppService` 实现 + `LoginItemViewModel`，失败显示原因且不假装开启）、`BundledMoleInfo`（读捆绑 SOURCE_VERSION tag 与可执行路径）。
- `WhitelistViewModel` 增 `WhitelistKind`：optimize 白名单只接受任务 id，注释拒绝；`WhitelistStore.optimize` 指向 `whitelist_optimize`。
- `HistoryViewModel` 存原始 JSON 并提供 `export(to:)`；`HistoryView` 加导出按钮（NSSavePanel）与空状态。
- 重写 `SettingsView`：语言/外观/登录项/项目扫描目录（复用 `purge_paths` 编辑器）/optimize 白名单/clean 白名单/CLI 行/关于/权限；不含被移除的两个开关。
- `ZmoleApp` 增 `AppDelegate`（关闭最后窗口退出）与 `AppLifecycle` 常量；`AppShellView` 应用外观覆盖。
- 测试 `tests/unit/SettingsHistoryTests.swift` 覆盖 8 条 AC。
- 黑盒：GUI 受限（同前），以临时目录/替身自动断言。

## Review 处置

review_level=single（`review_general.md`）。

|finding_id|severity|status|rationale|fix_ref|
|---|---|---|---|---|
|t024_gen_f001|minor|已修|history 跑两次，改为单次 raw 解析同源|HistoryViewModel.swift|
|t024_gen_f002|minor|已修|requiresApproval 静默关闭，补 failureReason|LoginItem.swift|
|t024_gen_f003|minor|已修|白名单错误键未接入视图，优先渲染 key|WhitelistView.swift|

## 收尾报告

### 验收与验证

- spec：[`spec.md`](spec.md)
- 结果：全部满足
- 测试：`xcodebuild test -scheme Zmole -destination 'platform=macOS'`：178 tests / 0 failures；`pytest .repo_template/tests -q -m contract`：147 passed
- 黑盒：GUI 受限（同前）；历史导出、白名单类型、登录项替身、生命周期常量由自动化覆盖
- review：`review_general.md` rounds 1-2 最终 PASS
- AC 证据：见 `handoff.json`

### 结果摘要

- 历史页展示 `history --json` 会话并原样导出；设置页提供语言、外观、登录项、项目扫描目录、两份白名单、CLI 行与关于；不做菜单栏常驻，关闭最后窗口即退出。遗留：无。

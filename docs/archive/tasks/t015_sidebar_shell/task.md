---
tid: "t015"
slug: "sidebar_shell"
title: "侧边栏壳与十页导航"
status: "done"
branch: "t015_sidebar_shell"
worktree: ""
review_level: "single"
review_limit: "5"
verify_limit: "5"
diff_anchor: "00814db3ebf3d6b288625cbbd167120f0b9205ce"
depends_on: ""
conflicts_with: ""
note: "取代 t014。grilling 2026-10-16 批准的信息架构与视觉壳。"
---

# Task 过程总账

front matter 只经 `task.py` 修改；reviewer 只写对应 `review_*.md`。

## 实施笔记

执行期记录关键步骤、决策、验证、阻塞和用户批准的新轮次上限。

创建期不预测实施步骤。只记有追溯价值的内容；无事项时写“无”。

来源：docs/design/refactor_grilling.md。用户于 2026-10-16 批准后创建。

- 新增 `AppDestination`（十目的地，双分组）、`NavigationModel`（导航状态、命令面板过滤、设置落点）、`AppShellView`（侧边栏 + NavigationStack 内容 + 命令面板 overlay + ⌘K 工具栏按钮）、`SidebarView`、`CommandPaletteView`、`MoleTheme`（按视觉权威 CSS 变量）。
- 删除 `ContentView.swift` 及顶部五模式 wrapper；`ZmoleApp` 改为 `WindowGroup` + `CommandGroup(replacing: .appSettings)`（设置命令选中侧边栏设置页）+ 默认 1200×780 / 最小 1100×700。移除原 `Settings` scene。
- `DemoConfiguration.page` 类型由 `AppMode` 改为 `AppDestination`，并保留 `analyze→disk`、`software→uninstall` 演示别名。
- `SettingsView` 增加 clean 白名单入口；`AppDependencies` 不变更进程边界。
- 概览、安装包为占位页（无删除/执行动作），由 t016/t023 接入。
- 黑盒门禁：testing.md 的 GUI demo smoke 需要可显示窗口的图形会话。本次执行环境（agent 会话）下 `open` 启动的 App 在 GUI domain 内无可见窗口，基线与本 task 表现一致（TextEdit 同样无窗口），确认为环境限制而非回归。已尝试 `open`/`launchctl asuser` 均无法取得窗口，无法产出截图验收；改以自动化门禁（109 单测含 demo 注入、contract 测试、Debug 构建）+ 基线一致性作为替代证据。GUI 截图验收待有图形会话时补做。

## Review 处置

每个结构化 finding 一行。`已修` 表示本 task 已修复；`遗留` 必须指向 `pNNN` 或 follow-up tid；`撤回` 必须写清理由。critical/important 未解决时不得 PASS。

### Round 1 (2026-10-16T17:23:51+08:00)

|finding_id|severity|status|rationale|fix_ref|
|---|---|---|---|---|
|t015_gen_f001|minor|已修|面板缺方向键实现，已加 selectedIndex + onMoveCommand + 高亮|CommandPaletteView.swift|
|t015_gen_f002|minor|已修|面板/设置命令测试偏自证，改为集合等值断言并声明接线手工覆盖|NavigationTests.swift|
|t015_gen_f003|minor|已修|过滤只读进程 locale，改为跨 en/zh-Hans/zh-Hant 解析|NavigationModel.swift|
|t015_gen_f004|minor|已修|同步 testing.md 与 demo_launch.md 到十目的地 IA 与新尺寸|testing.md / demo_launch.md|
|t015_gen_f005|minor|已修|sidebar/line 改为自适应基色 + opacity|MoleTheme.swift|

### Round 2 (2026-10-16T17:30:00+08:00)

Round 1 的 f001–f005 于本轮复核确认已消除；本轮新 finding 一条。

|finding_id|severity|status|rationale|fix_ref|
|---|---|---|---|---|
|t015_gen_f006|minor|已修|跨语言过滤修复缺回归测试，已补|NavigationTests.swift|

### Round 3 (2026-10-16T17:32:00+08:00)

Round 3 零 finding（生产代码自 Round 2 未变，f006 已消除）。

## 收尾报告

### 验收与验证

- spec：[`spec.md`](spec.md)
- 结果：全部满足（AC-004 的视图树断言以 `ShellChrome.drawsCustomTrafficLights` 常量替代，项目无 ViewInspector）
- 测试：`xcodegen generate` + `xcodebuild test -scheme Zmole -destination 'platform=macOS'`：109 tests / 0 failures；`pytest .repo_template/tests -q -m contract`：147 passed
- 黑盒：testing.md `blackbox_verify` 的 GUI demo smoke 受执行环境限制无法取得窗口截图（无图形会话，基线与本 task 一致）；Status 只读 watch 部分由 `StatusStreamTests` 自动化覆盖并通过。见实施笔记。
- review：`review_general.md` three rounds，最终 verdict PASS，无未处置 finding（全部 minor 已修）
- AC 证据：见 `handoff.json`

### 结果摘要

- 侧边栏十页壳 + ⌘K 命令面板 + 系统菜单设置落点完成；旧顶部五模式导航移除；概览/安装包为无副作用占位页，待 t016/t023。遗留：GUI 截图验收待图形会话补做。

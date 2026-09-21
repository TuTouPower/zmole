---
tid: "t003"
slug: "app_shell_i18n"
title: "侧栏、三语与设置关于页"
status: "done"
branch: "t003_app_shell_i18n"
worktree: ""
review_level: "single"
review_limit: "5"
verify_limit: "5"
diff_anchor: "52da180a86ca19c0a41332a742b9d306d02a5879"
depends_on: "t002"
conflicts_with: ""
note: ""
---

# Task 过程总账

front matter 只经 `task.py` 修改；reviewer 只写对应 `review_*.md`。

## 实施笔记

执行期记录关键步骤、决策、验证、阻塞和用户批准的新轮次上限。

创建期不预测实施步骤。只记有追溯价值的内容；无事项时写“无”。

- 2026-09-21：完成九项侧栏、`en`/`zh-Hans`/`zh-Hant` String Catalog、系统跟随与设置覆盖、About/权限引导、破坏性确认空壳；About 通过 t002 `MoleBridge.version()` 显示捆绑版本。
- 2026-09-21：发现动态 `LocalizedStringKey` 在运行时显示键名；改为枚举分支中的静态本地化键，CUA 复核英文、简体、繁体即时切换与不支持语言回落英文。

## Review 处置

每个结构化 finding 一行。`已修` 表示本 task 已修复；`遗留` 必须指向 `pNNN` 或 follow-up tid；`撤回` 必须写清理由。critical/important 未解决时不得 PASS。

### Round 1 (2026-09-21 17:41 UTC+8)

|finding_id|severity|status|rationale|fix_ref|
|---|---|---|---|---|
|t003_gen_f001|minor|已修|移除未使用的 `SidebarItem.isDestructive`，避免与路由 case 列表分叉|`src/zmole/App/ContentView.swift`|

### Round 2 (2026-09-21 17:51 UTC+8)

Round 2 零 finding。

## 收尾报告

### 验收与验证

- spec：[`spec.md`](spec.md)
- 结果：全部满足
- 测试：`xcodegen generate`；Debug `xcodebuild test` 10/10；Debug `xcodebuild build`；Release `xcodebuild build`；`mise exec -- pytest .repo_template/tests -q` 480 passed；`md_format.py --check` 与 `git diff --check` 通过。
- 黑盒：CUA 启动 Debug App；验证九项侧栏、英文/简体/繁体即时切换、不支持系统语言回落英文、About 信息与 Releases 链接、破坏性确认取消。
- review：single/general Round 2 PASS，零 finding，scope 见 `review_general.md`。
- AC 证据：见 `handoff.json`

### 结果摘要

- 完成三语 App shell 与设置入口；无遗留 finding。

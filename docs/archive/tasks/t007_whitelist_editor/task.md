---
tid: "t007"
slug: "whitelist_editor"
title: "白名单配置文件编辑页"
status: "done"
branch: "t007_whitelist_editor"
worktree: ""
review_level: "single"
review_limit: "5"
verify_limit: "5"
diff_anchor: "b36a005650b6ad5d99226d85f896e3991f0573c6"
depends_on: "t003"
conflicts_with: ""
note: ""
---

# Task 过程总账

front matter 只经 `task.py` 修改；reviewer 只写对应 `review_*.md`。

## 实施笔记

执行期记录关键步骤、决策、验证、阻塞和用户批准的新轮次上限。

创建期不预测实施步骤。只记有追溯价值的内容；无事项时写“无”。

- 新增可注入 URL 的 `WhitelistStore` 与 `WhitelistDocument`，仅读写 clean 白名单文件；解析模式时忽略空行/注释，保存时保留注释和空行。
- 新增原生 `WhitelistView`/`WhitelistViewModel`，支持模式列表、添加、删除、保存；optimize 白名单明确标注暂不支持，未调用 `MoleBridge`。
- XCTest 26/26；Debug、Release 构建通过；signed Release 为 x86_64/arm64，bundled mole 1.55.0，strict codesign 通过；模板 pytest 480 passed；CUA 只读核验 clean 标注和注释区；格式与 JSON 检查通过。

## Review 处置

每个结构化 finding 一行。`已修` 表示本 task 已修复；`遗留` 必须指向 `pNNN` 或 follow-up tid；`撤回` 必须写清理由。critical/important 未解决时不得 PASS。

### Round N (YYYY-MM-DD HH:MM UTC+8)

|finding_id|severity|status|rationale|fix_ref|
|---|---|---|---|---|
|t007_gen_f001|important|已修|读取失败后禁止编辑和保存，避免用默认头覆盖原文件|`src/zmole/Features/Whitelist/WhitelistViewModel.swift`; `tests/unit/ZmoleTests.swift`|
|t007_gen_f002|important|已修|模式行使用独立 UUID，重复模式按单行删除|`src/zmole/Features/Whitelist/WhitelistDocument.swift`; `tests/unit/ZmoleTests.swift`|
|t007_gen_f003|important|已修|注入 MoleCommandRunning spy，load/add/save 调用计数为零|`src/zmole/Features/Whitelist/WhitelistViewModel.swift`; `tests/unit/ZmoleTests.swift`|

无 finding 时写“Round N 零 finding”。

### Round 2 (2026-09-21 19:50 UTC+8)

Round 2 零 finding。

## 收尾报告

### 验收与验证

- spec：[`spec.md`](spec.md)
- 结果：全部满足
- 测试：XCTest 29/29；Debug、Release 构建；signed Release universal/codesign；模板 pytest 480 passed；`md_format.py --check`、JSON 与 `git diff --check` 通过。
- 黑盒：`testing.md` 的 `blackbox_verify` 未定义；CUA 启动 Debug App，确认页面显示 clean whitelist、clean 文件路径、optimize 暂不支持、注释只读；未执行保存，未修改用户配置。
- review：`review_general.md`，Round 2 PASS，Round 1 三条 finding 已修，零新 finding，scope 见报告。
- AC 证据：见 `handoff.json`

### 结果摘要

- 完成 clean whitelist 文件编辑，支持临时路径测试、注释保留、添加/删除/保存；optimize 白名单暂不支持；无遗留 finding。

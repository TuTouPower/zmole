---
tid: "t012"
slug: "icon_and_release_zip"
title: "独立图标与 Gatekeeper 说明"
status: "done"
branch: "t012_icon_and_release_zip"
worktree: ""
review_level: "single"
review_limit: "5"
verify_limit: "5"
diff_anchor: "c11ed2b18ef3db579c95970ea38eaa73cd55401c"
depends_on: "t001"
conflicts_with: ""
note: ""
---

# Task 过程总账

front matter 只经 `task.py` 修改；reviewer 只写对应 `review_*.md`。

## 实施笔记

执行期记录关键步骤、决策、验证、阻塞和用户批准的新轮次上限。

创建期不预测实施步骤。只记有追溯价值的内容；无事项时写“无”。

- 生成抽象 Z/工具形非地鼠图标源图 `assets/app_icon_source.png`，转换为 `src/zmole/Resources/AppIcon.icns`；显式 Info.plist 注入图标与完整 application bundle 元数据。
- README 已包含右键打开、系统设置「仍要打开」与 `xattr -cr` 三条未公证处理路径；Release bundle 核验 AppIcon、Info.plist、PkgInfo、Universal 与签名。

## Review 处置

每个结构化 finding 一行。`已修` 表示本 task 已修复；`遗留` 必须指向 `pNNN` 或 follow-up tid；`撤回` 必须写清理由。critical/important 未解决时不得 PASS。

### Round 1–3

|finding_id|severity|status|rationale|fix_ref|
|---|---|---|---|---|
|t012_gen_f001|important|已修|三个交付文件加入 intent-to-add 并进入最终 commit/review diff|assets/app_icon_source.png；src/zmole/Info.plist；src/zmole/Resources/AppIcon.icns|
|t012_gen_f002|important|已修|补齐 bundle identifier、executable、version、package type 等基础 metadata，PkgInfo 为 APPL????|src/zmole/Info.plist；project.yml|

Round 3 single review `verdict: PASS`，AC 2/2，reviewed_scope `f184f55dd399a8b8`，无遗留 finding。

无 finding 时写“Round N 零 finding”。

## 收尾报告

### 验收与验证

- spec：[`spec.md`](spec.md)
- 结果：全部满足 / 未满足
- 测试：XCTest 63/63；Debug、Release 构建；Release universal x86_64/arm64、AppIcon.icns、Info.plist、PkgInfo、codesign strict；模板 pytest 480 passed；`md_format.py --check`、JSON 与 `git diff --check` 通过。
- 黑盒：AC-001 按 `[deploy]` 约束以构建产物 `Contents/Resources/AppIcon.icns`、Info.plist、PkgInfo 和签名核验；未做 Finder/Dock 人工渲染检查。AC-002 读取 README。
- review：single Round 3 PASS，reviewed_scope `f184f55dd399a8b8`。
- AC 证据：见 `handoff.json`

### 结果摘要

- 完成独立 Z/工具形图标与 Gatekeeper 说明；不涉及公证、dmg 或 Release zip。

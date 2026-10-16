---
tid: "t021"
slug: "optimize_purge_pages"
title: "优化页与项目清理页"
status: "done"
branch: "t021_optimize_purge_pages"
worktree: ""
review_level: "full"
review_limit: "5"
verify_limit: "5"
diff_anchor: "e0a077092a195a016ba55ee18facf378244d6272"
depends_on: "t015"
conflicts_with: ""
note: "优化只读任务；项目清理不按勾选删除。"
---

# Task 过程总账

front matter 只经 `task.py` 修改；reviewer 只写对应 `review_*.md`。

## 实施笔记

执行期记录关键步骤、决策、验证、阻塞和用户批准的新轮次上限。

创建期不预测实施步骤。只记有追溯价值的内容；无事项时写“无”。

来源：docs/design/refactor_grilling.md。用户于 2026-10-16 批准后创建。

- 新增 `OptimizePlan.swift`：从真实 `optimize --dry-run`（`➤ 任务` 段 + 缩进明细）解析只读任务行、跳过原因与“会删文件”标记；`OptimizeView` 重写为任务行 + 原始输出 + 永久删除提示 + 白名单入口（跳设置）。
- 新增 `PurgePaths.swift`（`PurgePathsStore` 读写 `~/.config/mole/purge_paths` + 校验）与 `PurgePathsViewModel`（保存取 `.purge` 写租约并 `invalidatePreviews`）；`PurgePathsEditorView` 编辑器；`PurgeView` 重写为预览 + 扫描目录/白名单入口 + 永久删除提示。
- `AppDependencies` 增 `purgePathsViewModel`；`AppShellView` 传入设置跳转。
- `docs/blueprint/architecture.md`、`docs/design/ui_contract.md` 更新两页只读计划与永久删除。
- 测试 `tests/unit/OptimizePurgePageTests.swift`：优化/purge argv（无子集）、真实 dry-run 样例解析、当前跳过措辞、purge_paths 往返与非法保存、保存使预览失效、永久删除文案。
- 黑盒：GUI 受限（同前），已用自动化替代。

## Review 处置

review_level=full：`review_code.md` / `review_test.md`。

|finding_id|severity|status|rationale|fix_ref|
|---|---|---|---|---|
|t021_code_f001|important|已修|解析器与真实优化输出脱节，重写为 ➤ 段+明细|OptimizePlan.swift|
|t021_code_f002|important|已修|编辑器不加载，改 onAppear load|PurgePathsEditorView.swift|
|t021_code_f003|important|已修|保存扫描目录取写租约并失效预览|PurgePaths.swift|
|t021_code_f004|minor|撤回|保存过滤注释行，属小行为差异，不影响 AC|PurgePaths.swift|
|t021_code_f005|minor|已修|load 重置 didSave|PurgePaths.swift|
|t021_code_f006|important|已修|跳过措辞漏判，补 is healthy / close these apps before|OptimizePlan.swift|
|t021_code_f007|minor|撤回|测试引用 spike 样例路径，归档后需同步，属维护项|OptimizePurgePageTests.swift|
|t021_test_f001|important|已修|夹具改用真实 mole 样例|OptimizePurgePageTests.swift|
|t021_test_f002|minor|已修|补永久删除行文案断言|OptimizePurgePageTests.swift|
|t021_test_f003|minor|已修|补无预览→无行断言|OptimizePurgePageTests.swift|
|t021_test_f004|minor|撤回|冗余但无害的 no-subset 断言，保留记录意图|OptimizePurgePageTests.swift|

## 收尾报告

### 验收与验证

- spec：[`spec.md`](spec.md)
- 结果：全部满足
- 测试：`xcodebuild test -scheme Zmole -destination 'platform=macOS'`：162 tests / 0 failures；`pytest .repo_template/tests -q -m contract`：147 passed
- 黑盒：GUI 受限（同前）；arg 与预览文本映射、purge_paths 往返由自动化覆盖
- review：`review_code.md`（rounds 1-3）、`review_test.md`（rounds 1-3）最终均 PASS
- AC 证据：见 `handoff.json`

### 结果摘要

- 优化页列出真实任务（只读、跳过原因落在行、删除任务标永久删除），预览后确认执行，白名单入口到设置。项目清理页预览后 `purge --yes` 执行，扫描目录编辑器写 `purge_paths` 并取写租约失效旧预览；两页写明永久删除。遗留：minor 维护项已撤回。

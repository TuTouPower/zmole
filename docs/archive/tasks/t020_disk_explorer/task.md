---
tid: "t020"
slug: "disk_explorer"
title: "磁盘浏览与面积图"
status: "done"
branch: "t020_disk_explorer"
worktree: ""
review_level: "single"
review_limit: "5"
verify_limit: "5"
diff_anchor: "a6b20775333d4ce11d98401017e0638e32dd96ea"
depends_on: "t015"
conflicts_with: ""
note: "只读磁盘浏览，面积按当前层字节。"
---

# Task 过程总账

front matter 只经 `task.py` 修改；reviewer 只写对应 `review_*.md`。

## 实施笔记

执行期记录关键步骤、决策、验证、阻塞和用户批准的新轮次上限。

创建期不预测实施步骤。只记有追溯价值的内容；无事项时写“无”。

来源：docs/design/refactor_grilling.md。用户于 2026-10-16 批准后创建。

- `AnalyzeViewModel` 增加 `open(path:)`（面包屑）、`refreshCurrent`（重扫当前根）、展开子项（`toggleExpanded`/`children(of:)`/`expandedPaths`/`childrenByPath`，仅列表用，面积图仍只用当前层），并注入 `FileRevealing` 做在 Finder 中显示。
- 抽出纯函数 `AnalyzeSort`/`AnalyzeListOrder`/`AnalyzeArea.share` 便于断言。
- 重写 `AnalyzeView`：可点面包屑、返回、当前层搜索、按大小/名称排序、列表与面积图选中同步、目录展开与进入、叶子在 Finder 中显示；无删除/清理控件。
- `tests/unit/DiskExplorerTests.swift` 覆盖下钻 argv、面包屑、展开、面积占比、排序、Finder path、无删除控件。
- 黑盒：GUI 受限（同前），已用自动化替代。

## Review 处置

review_level=single（`review_general.md`）。

|finding_id|severity|status|rationale|fix_ref|
|---|---|---|---|---|
|t020_gen_f001|minor|已修|删除未使用的 AppKit 导入|AnalyzeView.swift|
|t020_gen_f002|minor|已修|refreshCurrent 清理展开缓存|AnalyzeViewModel.swift|
|t020_gen_f003|minor|撤回|单层展开满足“展开子项”，深层展开非需求|AnalyzeView.swift|
|t020_gen_f004|minor|撤回|展开失败缓存空结果与并发属边界，无 AC 影响|AnalyzeViewModel.swift|
|t020_gen_f005|minor|已修|补面积图与列表 path 一致断言|DiskExplorerTests.swift|
|t020_gen_f006|minor|撤回|AC-005 源码扫描为辅助证据，代码确无删除控件|AnalyzeView.swift|

## 收尾报告

### 验收与验证

- spec：[`spec.md`](spec.md)
- 结果：全部满足
- 测试：`xcodebuild test -scheme Zmole -destination 'platform=macOS'`：153 tests / 0 failures；`pytest .repo_template/tests -q -m contract`：147 passed
- 黑盒：GUI 受限（同前）；下钻/排序/面积/展开/Finder 由自动化覆盖
- review：`review_general.md` rounds 1-2 最终 PASS
- AC 证据：见 `handoff.json`

### 结果摘要

- 磁盘页改为面包屑 + 当前层列表 + 面积图 + 底部详情：下钻按 path 调 analyze、面积用当前层字节、列表/面积选中同步、可展开子项、叶子可在 Finder 中显示，无任何删除控件。遗留：minor 边界项已撤回。

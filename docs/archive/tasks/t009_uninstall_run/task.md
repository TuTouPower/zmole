---
tid: "t009"
slug: "uninstall_run"
title: "uninstall 列表预览确认后执行"
status: "done"
branch: "t009_uninstall_run"
worktree: ""
review_level: "full"
review_limit: "5"
verify_limit: "5"
diff_anchor: "c5264241db883bfce53fbb461ae0c276cde9f337"
depends_on: "t008"
conflicts_with: ""
note: ""
---

# Task 过程总账

front matter 只经 `task.py` 修改；reviewer 只写对应 `review_*.md`。

## 实施笔记

执行期记录关键步骤、决策、验证、阻塞和用户批准的新轮次上限。

创建期不预测实施步骤。只记有追溯价值的内容；无事项时写“无”。

- 新增 `UninstallApp`/list JSON 解码与行身份：`path` + `bundle_id` + `uninstall_name`。
- 新增 uninstall 列表、单选、唯一性校验、预览确认、执行前重列、目标变化失效、stdout/stderr 摘要与取消生命周期；所有命名 uninstall stdin 固定 `y\n`，不传 `--permanent`。
- 接入 `ContentView` uninstall 页面与三语文案；XCTest 49/49，`UninstallTests` 11/11；捆绑 mole 只读 `uninstall --list` 返回 63 条并包含 name/uninstall_name/path/bundle_id。

## Review 处置

每个结构化 finding 一行。`已修` 表示本 task 已修复；`遗留` 必须指向 `pNNN` 或 follow-up tid；`撤回` 必须写清理由。critical/important 未解决时不得 PASS。

### Round 1–2

|finding_id|severity|status|rationale|fix_ref|
|---|---|---|---|---|
|t009_test_f001|important|已修|补充当前 list 为空的目标消失测试，断言不发起生产 uninstall|tests/unit/UninstallTests.swift:173-194|
|t009_test_f002|important|已修|新增文件加入 intent-to-add，重新生成完整 reviewer scope 并通过双轴复审|git add -N；reviewed_scope f4e6a4140554b220|

Round 2 代码轴与测试轴均 `verdict: PASS`，无遗留 critical/important/minor。

无 finding 时写“Round N 零 finding”。

## 收尾报告

### 验收与验证

- spec：[`spec.md`](spec.md)
- 结果：全部满足 / 未满足
- 测试：XCTest 49/49；Debug、Release 构建；signed Release universal/codesign；模板 pytest 480 passed；`md_format.py --check`、JSON 与 `git diff --check` 通过。
- 黑盒：`testing.md` 的 `blackbox_verify` 为“无”；真卸载不执行；捆绑 mole 只读 `uninstall --list` 核验 JSON 63 条及四个必需字段。
- review：full Round 2，代码轴与测试轴均 PASS，reviewed_scope `f4e6a4140554b220`。
- AC 证据：见 `handoff.json`

### 结果摘要

- 完成 uninstall 列表展示、唯一目标预览、确认执行和目标变化保护；未执行真实卸载。

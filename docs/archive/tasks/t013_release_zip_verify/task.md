---
tid: "t013"
slug: "release_zip_verify"
title: "Release zip 与解压后只读验收"
status: "done"
branch: "t013_release_zip_verify"
worktree: ""
review_level: "single"
review_limit: "5"
verify_limit: "5"
diff_anchor: "8f12cf619ce86e7dd458013a3f27f05220bc6daf"
depends_on: "t002,t003,t004,t005,t006,t007,t008,t009,t010,t011,t012"
conflicts_with: ""
note: ""
---

# Task 过程总账

front matter 只经 `task.py` 修改；reviewer 只写对应 `review_*.md`。

## 实施笔记

执行期记录关键步骤、决策、验证、阻塞和用户批准的新轮次上限。

创建期不预测实施步骤。只记有追溯价值的内容；无事项时写“无”。

- 新增可重复 `scripts/build_release_zip.sh`：XcodeGen + Release 构建、ad-hoc codesign 校验、输出 `artifacts/releases/Zmole-1.0.zip`。
- 解压 zip 检查主程序与 mole 树入口、三项 Universal 架构、ad-hoc 签名、Releases URL 与占位符；CUA 从 Finder 选中并启动解压 App，验证 status 刷新、history、analyze overview。
- `docs/blueprint/testing.md` 登记 Release zip 门禁；未执行破坏性命令。

## Review 处置

每个结构化 finding 一行。`已修` 表示本 task 已修复；`遗留` 必须指向 `pNNN` 或 follow-up tid；`撤回` 必须写清理由。critical/important 未解决时不得 PASS。

### Round 1

|finding_id|severity|status|rationale|fix_ref|
|---|---|---|---|---|
|t013_gen_f001|minor|已修|相对输出目录先按调用方当前目录解析为绝对路径，支持仓外调用|`scripts/build_release_zip.sh`|
|t013_gen_f002|minor|已修|校验 `codesign -dv` 输出含 ad-hoc 签名标志，防止签名配置漂移|`scripts/build_release_zip.sh`|

### Round 2

Round 2 零 finding。

## 收尾报告

### 验收与验证

- spec：[`spec.md`](spec.md)
- 结果：全部满足
- 测试：`scripts/build_release_zip.sh`；zip 解压/内容；主程序、analyze-go、status-go 均 `x86_64 arm64`；ad-hoc `codesign -dv`；Releases URL/占位符扫描；XCTest 63/63；模板 pytest 480 passed；格式、JSON、diff 检查通过。
- 黑盒：Finder 选中并启动解压后的 `Zmole.app`；CUA 验证 Status 刷新健康分 100、History 列表、Analyze overview 条目；真破坏性命令不执行。
- review：single Round 2 PASS。
- AC 证据：见 `handoff.json`

### 结果摘要

- 完成 Release zip 生成与解压后只读验收；无遗留。

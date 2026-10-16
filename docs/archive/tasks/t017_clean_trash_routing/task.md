---
tid: "t017"
slug: "clean_trash_routing"
title: "清理删除改走废纸篓"
status: "done"
branch: "t017_clean_trash_routing"
worktree: ""
review_level: "full"
review_limit: "5"
verify_limit: "5"
diff_anchor: "0be6d3ef39d0e480ebff7e9a6e71d63cf2f51fb3"
depends_on: ""
conflicts_with: ""
note: "捆绑 clean 改为废纸篓且不再清空废纸篓。"
---

# Task 过程总账

front matter 只经 `task.py` 修改；reviewer 只写对应 `review_*.md`。

## 实施笔记

执行期记录关键步骤、决策、验证、阻塞和用户批准的新轮次上限。

创建期不预测实施步骤。只记有追溯价值的内容；无事项时写“无”。

来源：docs/design/refactor_grilling.md。用户于 2026-10-16 批准后创建。

- 在 `lib/core/file_ops.sh` 新增 `_mole_clean_trash_destination` / `_mole_clean_trash_path`（非提权、HOME 或 `MOLE_TRASH_DIR` 落点、同名去重），并在 `safe_remove` 的删除 sink 加 `MOLE_CURRENT_COMMAND=clean` 分支：clean 走移入废纸篓，失败保留原文件并返回非零，不回退 `rm -rf`。
- `safe_sudo_remove` 的 clean 提权分支不再直接 root `mv` 进用户可控 `~/.Trash`，改为委托仓库既有 `_mole_move_path_to_user_trash`（root 暂存中继 + 以 invoking user 身份落篓），并传播 124/`>=128` 取消码。
- `lib/clean/user.sh` 的 `clean_trash` 直接 `return 0`（同一次不再清空废纸篓；dry-run 预览也不登记）。
- 补丁全部带 “zmole local patch (t017)” 标记，便于上游升级重放。
- 测试：新增 `tests/integration/clean_trash_test.sh`，source 真实生产库，用临时 HOME / 废纸篓目录，覆盖 AC-001..005（含同名去重、非 clean 仍永久删除）。已把该测试加入 `docs/blueprint/testing.md` 的 `test_cmd`。
- `docs/blueprint/domain.md` 更新 clean/optimize 词条；`decisions.md` 追加 007。
- 黑盒：GUI 相关不在本 task；集成测试为可执行黑盒。

## Review 处置

每个结构化 finding 一行。`已修` 表示本 task 已修复；`遗留` 必须指向 `pNNN` 或 follow-up tid；`撤回` 必须写清理由。critical/important 未解决时不得 PASS。

review_level=full：代码轴 `review_code.md`、测试轴 `review_test.md`。

|finding_id|severity|status|rationale|fix_ref|
|---|---|---|---|---|
|t017_code_f001|important|已修|提权入篓绕开既有安全 helper，改为委托 `_mole_move_path_to_user_trash`|file_ops.sh|
|t017_code_f002|minor|已修|存在性判定补 `-L`，悬挂链接可入篓|file_ops.sh|
|t017_code_f003|minor|已修|提权入篓传播 124/`>=128` 取消码|file_ops.sh|
|t017_code_f004|minor|撤回|`clean_trash` 原体保留供上游升级重放，属有意保留|user.sh|
|t017_code_f005|minor|已修|注释错位，拆到对应函数|file_ops.sh|
|t017_code_f006|minor|已修|`domain.md` 状态词条越界改动，已回退|domain.md|
|t017_code_f007|minor|已修|陈旧注释归位到 `safe_remove` 之上|file_ops.sh|
|t017_test_f001|important|已修|AC-003 假绿，改为运行真实 `clean_trash` 并断言既有废纸篓项存活|clean_trash_test.sh|
|t017_test_f002|important|已修|提权 sink 零覆盖，补提权用例|clean_trash_test.sh|
|t017_test_f003|minor|已修|移除 AC-004 死 stub|clean_trash_test.sh|
|t017_test_f004|minor|已修|补非 clean 仍永久删除的负向用例|clean_trash_test.sh|
|t017_test_f005|minor|已修|提权用例改委托后自然消除旧 stub 问题|clean_trash_test.sh|
|t017_test_f006|important|已修|提权用例改断言委托标记，变为红绿可信|clean_trash_test.sh|

零 finding 轮次：代码轴 Round 2 与 Round 4、测试轴 Round 2（除 f005）与 Round 4 无新增阻断项；详见两份报告。

## 收尾报告

### 验收与验证

- spec：[`spec.md`](spec.md)
- 结果：全部满足
- 测试：`bash tests/integration/clean_trash_test.sh`：8/8；`pytest .repo_template/tests -q -m contract`：147 passed
- 黑盒：集成测试即可执行黑盒（真实生产库 + 临时 HOME 废纸篓）；GUI smoke 不涉及本 task
- review：`review_code.md` / `review_test.md` 均最终 PASS；未解决 important 为 0
- AC 证据：见 `handoff.json`

### 结果摘要

- 捆绑 clean 的删除改走废纸篓，失败保留原文件不回退永久删除；同一次不再清空废纸篓；提权路径委托既有安全 helper。遗留：无（f004 为有意保留）。

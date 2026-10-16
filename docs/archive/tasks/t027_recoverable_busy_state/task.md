---
tid: "t027"
slug: "recoverable_busy_state"
title: "mole busy 降级为可恢复提示"
status: "done"
branch: "t027_recoverable_busy_state"
worktree: ""
review_level: "single"
review_limit: "5"
verify_limit: "5"
diff_anchor: "97734278e417bd4b1f84f647e052b2f3ee35ef1c"
depends_on: "t025"
conflicts_with: ""
note: "区分瞬时忙碌与真实失败。来源 p008。"
---

# Task 过程总账

front matter 只经 `task.py` 修改；reviewer 只写对应 `review_*.md`。

## 实施笔记

执行期记录关键步骤、决策、验证、阻塞和用户批准的新轮次上限。

创建期不预测实施步骤。只记有追溯价值的内容；无事项时写“无”。

来源：`p008`（2026-10-16 核实）。用户实测安装包页 busy 显示为红色失败。

- 新增 `CommandBusy.isBusy` 与 `RecoverableBusyNotice`（中性提示视图）；`MoleBridgeError.isBusy`。
- 各 VM 增 `showBusyNotice`（Analyze/History/Overview/Installers/Uninstall/Clean/Maintenance）：busy 时不设失败、保留既有数据；协调器租约忙改为置提示并回滚 session（Clean/Maintenance/Uninstall 改为先 acquire 再 beginPreview）。真实失败不变。
- 各页渲染中性 busy 提示。t025 的写入互斥用例改为表示无关断言（不 spawn）。
- `docs/design/ui_contract.md` 更新忙碌态与失败态区分。
- 测试 `tests/unit/RecoverableBusyTests.swift` 覆盖三条 AC。

## Review 处置

review_level=single（`review_general.md`）。

|finding_id|severity|status|rationale|fix_ref|
|---|---|---|---|---|
|t027_gen_f001|important|已修|Uninstall 先 beginPreview 后 acquire，busy 卡 previewing；改为先 acquire|UninstallViewModel.swift|
|t027_gen_f002|minor|已修|Installers 成功后未清 busy 提示|InstallersViewModel.swift|
|t027_gen_f003|minor|已修|MoleBridgeError 两 case 并到一行，已分行|MoleBridgeError.swift|
|t027_gen_f004|minor|已修|删除 CommandBusy 死代码|CommandBusy.swift|
|t027_gen_f005|minor|已修|Overview busy 不清 errorMessage|OverviewViewModel.swift|
|t027_gen_f006|minor|已修|t025 用例改为表示无关断言|CommandConcurrencyTests.swift|
|t027_gen_f007|minor|已修|Overview 真实失败未清 busy 提示|OverviewViewModel.swift|

## 收尾报告

### 验收与验证

- spec：[`spec.md`](spec.md)
- 结果：全部满足
- 测试：`xcodebuild test -scheme Zmole -destination 'platform=macOS'`：198 tests / 0 failures；`pytest .repo_template/tests -q -m contract`：147 passed
- 黑盒：GUI 受限（同前）；busy/失败区分由假进程与协调器租约覆盖
- review：`review_general.md` rounds 1-3 最终 PASS
- AC 证据：见 `handoff.json`

### 结果摘要

- 命令通道忙碌（含写入租约占用）不再显示为失败，改为中性可恢复提示并可重试；真实失败保持原有持久结果区与摘要。遗留：无。

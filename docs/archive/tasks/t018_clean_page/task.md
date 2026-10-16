---
tid: "t018"
slug: "clean_page"
title: "清理页整次预览后执行"
status: "done"
branch: "t018_clean_page"
worktree: ""
review_level: "full"
review_limit: "5"
verify_limit: "5"
diff_anchor: "ef1efac64fa4d2338b4ff5e421b26f4512d91fb0"
depends_on: "t015,t017"
conflicts_with: ""
note: "清理页不按勾选子集执行，显示扫描阶段名。"
---

# Task 过程总账

front matter 只经 `task.py` 修改；reviewer 只写对应 `review_*.md`。

## 实施笔记

执行期记录关键步骤、决策、验证、阻塞和用户批准的新轮次上限。

创建期不预测实施步骤。只记有追溯价值的内容；无事项时写“无”。

来源：docs/design/refactor_grilling.md。用户于 2026-10-16 批准后创建。

- 新增 `CleanPreviewModel.swift`（解析 dry-run 的 `=== 分类 ===` 与 `path # 体积` 行、体积解析、reclaim 合计）与 `CleanScanStage.swift`（阶段目录 + ANSI 剥离；阶段名来自捆绑 `bin/clean.sh` 的 `start_section`）。
- `CleanViewModel` 增加可选 `MoleStreaming`：有流时用 `clean --dry-run` 流式输出显示当前阶段（timeout 300s），否则回落一次性 `run()`（测试/demo）。新增 `currentStage` 与 `lastReclaimBytes`：预览成功设置、失败/取消/确认取消/执行时清空。
- 重写 `CleanView` 为整次预览布局：统计条、分类列表（按体积 + 每行「保护」按钮，无勾选子集执行）、右侧保护说明与白名单条数、底部确认执行；扫描中显示阶段名不显示百分比。保护路径经 `WhitelistViewModel.addPattern + save` 写入白名单并经 coordinator 使预览失效。
- `SidebarView` 清理项在有 `lastReclaimBytes` 时显示角标；`AppShellView` 传入 whitelist 与打开设置的回调。
- `AppDependencies`：clean dry-run 流使用第三条独立 `MoleBridge`（`cleanStreaming`），与 status watch 流、一次性命令流隔离；demo 回落一次性路径。
- 文案：`clean.execution_note` / `clean.confirm_summary` / `clean.subtitle` 三语写明移入废纸篓。
- `docs/blueprint/domain.md` 与 `docs/design/ui_contract.md` 更新清理页不可子集执行。
- 黑盒：GUI 受环境限制（同前）；已用自动化门禁替代。

## Review 处置

每个结构化 finding 一行。`已修` 表示本 task 已修复；`遗留` 必须指向 `pNNN` 或 follow-up tid；`撤回` 必须写清理由。critical/important 未解决时不得 PASS。

review_level=full：代码轴 `review_code.md`、测试轴 `review_test.md`。

|finding_id|severity|status|rationale|fix_ref|
|---|---|---|---|---|
|t018_code_f001|important|已修|clean 预览流与 status watch 共用 bridge，拆为第三条独立 bridge|AppDependencies.swift|
|t018_code_f002|important|已修|流式分支缺测试，补 streaming 注入用例|CleanPageTests.swift|
|t018_code_f003|minor|撤回|无用本地化键在 diff_anchor 前即存在，非本 task 引入|Localizable.xcstrings|
|t018_code_f004|minor|已修|阶段名单派生自单一映射并给流式加 timeout|CleanScanStage.swift / CleanViewModel.swift|
|t018_code_f005|minor|撤回|AC-002/AC-006 已有既有专用测试覆盖（ZmoleTests 确认取消与失败摘要），本 task 未重复|ZmoleTests.swift|
|t018_test_f001|important|已修|生产 streaming 预览零覆盖，补注入用例|CleanPageTests.swift|
|t018_test_f002|minor|已修|currentStage 未断言，streaming 用例补断言|CleanPageTests.swift|
|t018_test_f003|minor|已修|角标数值自指，改硬编码期望|CleanPageTests.swift|
|t018_test_f004|minor|已修|补无子集控件源码扫描测试|CleanPageTests.swift|
|t018_test_f005|minor|已修|补三语阶段键存在性校验|CleanPageTests.swift|

## 收尾报告

### 验收与验证

- spec：[`spec.md`](spec.md)
- 结果：全部满足
- 测试：`xcodebuild test -scheme Zmole -destination 'platform=macOS'`：133 tests / 0 failures；`pytest .repo_template/tests -q -m contract`：147 passed；`bash tests/integration/clean_trash_test.sh`：8/8
- 黑盒：GUI 受执行环境限制（同前）；阶段/角标/文案/预览世代由自动化覆盖
- review：`review_code.md` / `review_test.md` 最终均 PASS
- AC 证据：见 `handoff.json`

### 结果摘要

- 清理页改为整次预览：分类+体积、每行保护、右侧白名单条数、执行前确认、失败摘要持久；扫描显示阶段名不显示百分比；侧边栏清理角标为最近成功预览可回收量；文案三语写明移入废纸篓。遗留：无。

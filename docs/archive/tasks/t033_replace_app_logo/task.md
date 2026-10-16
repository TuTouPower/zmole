---
tid: "t033"
slug: "replace_app_logo"
title: "更换应用 Logo 与图标"
status: "done"
branch: "t033_replace_app_logo"
worktree: ""
review_level: "single"
review_limit: "5"
verify_limit: "5"
diff_anchor: "03580b8fd999c141509e07e30ecbee17deb051a5"
depends_on: ""
conflicts_with: ""
note: "用户 2026-10-17 批准（来源 p011 核实）：彩色渐变为主、黑白备用。"
---

# Task 过程总账

front matter 只经 `task.py` 修改；reviewer 只写对应 `review_*.md`。

## 实施笔记

执行期记录关键步骤、决策、验证、阻塞和用户批准的新轮次上限。

创建期不预测实施步骤。只记有追溯价值的内容；无事项时写“无”。

- 图标源：彩色渐变版落地为 `assets/app_icon_source.svg`（唯一构建源），黑白版为 `assets/app_icon_source_mono.svg`（备用，不入构建）；根目录两个 gemini SVG 移除；旧 `assets/app_icon_source.png` 删除（全仓无构建引用）。
- 生成流水线：新增 `scripts/build_app_icon.sh`（qlmanage 渲染 1024 → sips 生成 10 个 iconset 尺寸 → iconutil 输出 `src/zmole/Resources/AppIcon.icns`）。同一源重复渲染字节一致（sha 稳定），测试以此做「产物与源一致」断言。
- 重生成的 icns：旧 `3e5608ef…` → 新 `122ae945…`；构建产物 app 内 icns 与新源 sha 一致，`Info.plist`/`project.yml` 引用不变。
- 测试：新增 `AppIconTests`（源位置与根目录清理、产物可由源复现字节比对、icns 十个尺寸齐全、无旧 PNG 引用、侧栏走 `NSApp.applicationIconImage`）。
- 约定：`docs/blueprint/conventions.md` 增加「图标源与生成」约定。
- 黑盒：Debug 构建 demo 启动截图，侧栏 zmole 品牌图标显示新渐变图标。

## Review 处置

每个结构化 finding 一行。`已修` 表示本 task 已修复；`遗留` 必须指向 `pNNN` 或 follow-up tid；`撤回` 必须写清理由。critical/important 未解决时不得 PASS。

### Round N (YYYY-MM-DDThh:mm:ss+08:00)

|finding_id|severity|status|rationale|fix_ref|
|---|---|---|---|---|
|t000_code_f001|critical/important/minor|已修/遗留/撤回|一句话|文件:行 / pNNN / tid|

### Round 1 (2026-10-17T03:15:00+08:00)

|finding_id|severity|status|rationale|fix_ref|
|---|---|---|---|---|
|t033_gen_f001|minor|已修|测试 helper 用 Pipe 捕获子进程 stderr，失败断言附尾部输出|tests/unit/AppIconTests.swift|

## 收尾报告

### 验收与验证

- spec：[`spec.md`](spec.md)
- 结果：全部满足（AC-001/002/004 自动测试；AC-003 `[deploy]` 以构建产物 icns 断言 + 侧栏截图人工确认，见 `handoff.json`）
- 测试：`xcodebuild test -scheme Zmole -destination 'platform=macOS'` 241 通过（新增 AppIconTests 5 例）；`pytest .repo_template/tests -q -m contract` 147 通过；三组 shell 集成通过
- 黑盒：Debug 构建产物 `Contents/Resources/AppIcon.icns` 与新源重渲染 sha 一致；demo 启动截图侧栏品牌图标为新的蓝青渐变 Z
- review：single Round 2 PASS（`review_general.md`）；`reviewed_scope 52d8c267f2b2c157`；无未解决 finding
- AC 证据：见 `handoff.json`

### 结果摘要

- 彩色渐变 SVG 为唯一图标源（`assets/app_icon_source.svg`），黑白版备用入库；`scripts/build_app_icon.sh` 由源可复现生成 `AppIcon.icns`（旧 `3e5608ef…` → 新 `122ae945…`）；根目录草稿 SVG 与旧 PNG 源移除。
- 遗留：无

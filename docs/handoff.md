# 项目交接记录（最新）

本文件只保留当前有效一节。过时段落由 `repo-hygiene` 迁入 `docs/archive/handoff.md`。

## 2026-09-21T12:26:08+08:00 init → owner

- 当前焦点：仓库已从 repo_template 初始化；技术栈定为 SwiftUI + MoleBridge 调 `mo`；待创建 Xcode 工程与首个 Bridge/只读功能。
- branch：main
- head_commit：d40fd76c2b97b8c5582d810f18cb72eca12b8711
- 已完成：模板复制、软链校验、hooks、README/AGENTS/blueprint、Swift gitignore、目录占位
- 未完成：`Zmole.xcodeproj`、MoleBridge 实现、功能页、业务测试接入 `test_cmd`
- 陷阱：上游另有商业 Mole for Mac，勿与本仓混淆；破坏性 CLI 须 dry-run/确认；本机可能未装 `mo`
- 下一步：`task-create` 拆「Xcode 工程骨架 + MoleBridge 探测 `mo --version`」等 task

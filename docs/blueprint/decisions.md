# 决策记录（ADR）

只记录已经确认、影响后续工作的非显然决策。追加新条目，不重写历史；决策被替代时，新条目通过“替代”字段引用旧编号。

每条结构：`## NNN 标题（YYYY-MM-DD）`，下接 `- 背景` / `- 选项` / `- 结论` / `- 替代` 四项；替代填旧编号，无则写「无」。

## 001 桌面端采用 SwiftUI 原生，经 Bridge 调用 mole CLI（2026-09-21）

- 背景：本仓目标是把 mole CLI 做成 macOS 桌面应用；需选定 UI 技术与能力实现方式。
- 选项：
    1. SwiftUI 原生 App + `Process` 调用本机 `mo`
    2. Tauri + Web UI + sidecar/shell 调 `mo`
    3. 仅仓库骨架，技术栈延后
- 结论：选 1。体积与权限模型更贴 macOS；清理语义继续由上游 CLI 负责，本仓做 GUI 与编排。首版非沙盒；不捆绑商业版 Mole for Mac。Xcode 工程在首个实现 task 中创建，初始化阶段不手写 pbxproj。
- 替代：无

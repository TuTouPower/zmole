# 视觉验收证据（2026-10-17）

- 构建版本：`adoption_20261017` worktree（main `288e3e5` + `docs/reviews/review_20261017_054534` 全部采纳项），Debug 构建。

- 运行环境：macOS 26.5.2（25F84）、Apple Silicon、中文系统。

- 启动方式（demo 假件驱动生产 View，不触碰真实 mole/用户文件）：

    ```bash
    open Zmole.app --args --demo --demo-page <page> --demo-state populated \
      --demo-language <zh-Hans|zh-Hant|en> --demo-appearance <light|dark> \
      --demo-data-root <临时目录>
    ```

- 命名：`<语言>_<外观>_<尺寸>_<页面>.png`（Retina 2x 像素）。

- 覆盖范围：

    - 十页（overview / clean / uninstall / disk / optimize / status / purge / installers / history / settings）× zh-Hans × 浅色 × 1200×780；
    - 抽查：en × 深色（overview、disk）、zh-Hant × 浅色（status）、zh-Hans × 浅色 × 1100×700（overview，最小窗口）。

- 未覆盖（后续交付增量补齐）：浅/深 × 三语 × 两尺寸全矩阵、交互态（悬停/禁用/确认 sheet）、VoiceOver。

- 已知边界：

    - `--demo-language` 覆盖经 SwiftUI environment 生效（界面文案与侧栏分组标题随其切换）；窗口标题栏由 AppKit 按系统 locale 渲染，不随 demo 覆盖切换。
    - 侧栏首项的系统键盘焦点环在截图时可见（焦点而非选中态）；选中态为对应行的强调背景。
    - 侧栏底部机器名与系统版本来自本机系统信息（非应用文案），截图未去标识，仅本仓内追溯用。

- 对照物：`docs/design/mole_desktop_demo_cn_final.html`（布局参考）与 `docs/design/ui_contract.md`（页面契约）；色彩以应用图标蓝系为准（decisions 009）。

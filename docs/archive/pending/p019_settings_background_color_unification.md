# p019 设置界面背景色与其他界面保持统一

- 来源：用户 2026-10-17 口述
- 内容：排查并修复设置页（`src/zmole/Features/Settings/SettingsView.swift`）的背景色不一致问题：
    1. 当前大部分页面（Clean、Optimize、Purge、Overview 等）外层均显式声明了 `.background(MoleTheme.background)`，而 `SettingsView` 采用默认 `Form` 样式未施加统一背景，在浅色/深色模式下与侧边栏及主窗口基底色彩不协调。
    2. 为 `SettingsView` 添加 `.background(MoleTheme.background)` 或通过 `.scrollContentBackground(.hidden)` 清除 Form 默认底色，确保与其他所有功能页面的背景色彩完全一致。
- 边界：仅调整设置页面的容器背景色，不破坏 Form 内各 Section 的行背景与交互排版。
- 处理：t045

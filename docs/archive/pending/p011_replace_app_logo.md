# p011 更换应用 Logo / 图标

- 来源：用户 2026-10-17 提供自设计 SVG 两个（仓库根目录新增未跟踪文件 `gemini-svg.svg` 彩色渐变版、`gemini-svg (1).svg` 黑白版），要求更换本软件 logo
- 内容：用新 SVG 设计替换当前应用图标/Logo，涉及：
    - 应用图标源 `assets/app_icon_source.png`（现为旧图）→ 改用新 SVG 重新生成
    - 打包图标 `src/zmole/Resources/AppIcon.icns`（project.yml:35 引用）→ 从新源重新导出
    - 运行期展示入口 `src/zmole/App/SidebarView.swift:47`（`NSApp.applicationIconImage`）随 AppIcon.icns 更新自动生效
    - 两个 SVG 为同一设计两版本：`gemini-svg.svg` 彩色渐变（#00F2FE→#0052D4 系蓝紫渐变），`gemini-svg (1).svg` 纯黑白（白底黑图形，四周留白 100px，viewBox 1200×1200）；主图标用途需确认用哪个版本，可能分别用于彩色图标与单色/模板场景
    - 根目录两个 SVG 为未跟踪文件，落地时需移入 `assets/`（如 `assets/app_icon_source.svg`）并纳入版本控制
- 处理：t033

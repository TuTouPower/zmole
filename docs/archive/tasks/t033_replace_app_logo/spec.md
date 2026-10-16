# Task spec

## 背景

用户 2026-10-17 提供自设计 SVG 两版（仓库根目录未跟踪文件 `gemini-svg.svg` 彩色渐变版、`gemini-svg (1).svg` 黑白版），要求替换当前应用 Logo/图标。现图标源为 `assets/app_icon_source.png`（旧图），打包引用 `src/zmole/Resources/AppIcon.icns`（`project.yml:35`），运行期侧栏经 `NSApp.applicationIconImage` 展示。用户已确认：彩色渐变为主，黑白备用。

## 契约区

### 范围

- 新图标源 SVG 落地到 `assets/` 并纳入版本控制（彩色主版；黑白备用版一并入库或按实现判断）。
- 由新源生成/导出 `src/zmole/Resources/AppIcon.icns`（覆盖旧图标）。
- 构建后 app 图标、Finder/Dock 展示与侧栏 `NSApp.applicationIconImage` 均显示新图标。
- 释放根目录两个未跟踪 SVG（移入 assets 后不再残留于仓库根）。

### 非范围

- 不改应用名、bundle id、签名与公证流程。
- 不重设计图形本身。
- 不新增第三方图标处理依赖。

### 验收标准

<!-- 规范（门禁必留，不得删除） -->

只写可观察、可独立验证的行为；每条使用稳定且不复用的 `AC-NNN`。需真实部署或人工环境验证时在编号前加 `[deploy]`。技术选型不作为行为 AC。

<!-- /规范 -->

- [ ] AC-001：`assets/` 中存在新图标源文件（彩色主版），仓库根不再有未跟踪 SVG 残留。
- [ ] AC-002：重新构建产物中的 `AppIcon.icns` 与旧图标不同，且源出彩色主版 SVG。
- [ ] AC-003：构建后的 app 在 Finder 中显示新图标，应用内侧栏图标同为该新图标（`[deploy]`）。
- [ ] AC-004：仓库不残留对旧 `app_icon_source.png` 的构建引用，或该文件被新源替换且引用一致。

### 可测试性声明

<!-- 规范（门禁必留，不得删除） -->

逐条说明不可自动测试的 AC 及替代验证；全部可测则写“全部 AC 可自动测试”。

<!-- /规范 -->

- AC-001：可自动测试（文件存在性、git 状态）。
- AC-002：可测（比较 icns 内容/哈希、校验图标尺寸集合）。
- AC-003：Finder/侧栏真实渲染在无显示环境不可测；以构建产物图标与侧栏引用的静态断言替代，人工开图确认。
- AC-004：可测（grep 引用）。

## 上下文区

- 来源：p011（2026-10-17 核实：旧源 PNG 存在、`project.yml:35` 引用 icns、根目录两 SVG 未跟踪）

### 有意不测

- 设计美学与视觉评审：非行为，人工确认即可。

### 测试策略

- 构建后校验 icns 包含预期尺寸且非旧文件；单测/脚本断言图标文件哈希变化与引用路径。

### 未知契约清单

<!-- 规范（门禁必留，不得删除） -->

未核实的外部契约标为 `UNVERIFIED-BLOCKING` 或 `UNVERIFIED-SPIKE`；核实后改写为结论和验证方式。无则写“无”。

<!-- /规范 -->

- 无

### 风险与回退

- 风险：SVG→icns 转换在本机工具链的可复现性；图标覆盖后旧图丢失。
- 回退：保留旧 `AppIcon.icns`/旧源于 git 历史，回退提交即恢复。

### 依赖与约束

- 平台：macOS（iconutil/sips 或等效工具）。

### Finalization 时更新的 blueprint

- `docs/blueprint/conventions.md`：图标源与生成路径约定。

# Task spec

## 背景

已定三语、设置可覆盖、关于页说明与 mole 的关系。权限失败时再引导，不在启动时上课。

## 契约区

### 范围

- 侧栏信息架构（第一版条目：Status、History、Analyze、Clean、Uninstall、Optimize、Purge、Whitelist、Settings）
- String Catalog：`en` / `zh-Hans` / `zh-Hant`
- 设置：跟随系统或强制一种语言（立即生效或需重启须在 UI 写明）
- 关于：zmole 名、GPL-3.0、基于 mole 非 Mole for Mac、捆绑 mole 版本、打开 GitHub Releases 的链接（URL 可配置占位）
- 可复用的「破坏性确认」空壳组件（标题、摘要、确认/取消；确认前不调用 Bridge）
- 权限失败提示组件：说明可打开系统设置，不在首次冷启动强制弹出

### 非范围

- 各功能真实数据；installer 等侧栏项；公证

### 验收标准

<!-- 规范（门禁必留，不得删除） -->

只写可观察、可独立验证的行为；每条使用稳定且不复用的 `AC-NNN`。需真实部署或人工环境验证时在编号前加 `[deploy]`。技术选型不作为行为 AC。

<!-- /规范 -->

- [ ] [deploy] AC-001：系统语言为英文 / 简体 / 繁体时，未覆盖则界面为对应语言；其它系统语言回落英文
- [ ] [deploy] AC-002：设置中强制另一种已支持语言后，界面改为该语言
- [ ] [deploy] AC-003：关于页含 zmole、GPL、mole 来源声明、非 Mole for Mac、捆绑版本（来自 t002 API）
- [ ] AC-004：侧栏无 installer / update / remove 项
- [ ] AC-005：确认组件在取消时不调用任何 Bridge 执行方法（单测）

### 可测试性声明

<!-- 规范（门禁必留，不得删除） -->

逐条说明不可自动测试的 AC 及替代验证；全部可测则写“全部 AC 可自动测试”。

<!-- /规范 -->

- AC-001、AC-002、AC-003：改系统语言或设置后手工
- AC-004：读导航配置或 snapshot
- AC-005：单测

## 上下文区

- 来源：ADR-005、ADR-004；`docs/plan.md`

### 有意不测

- 每句文案的翻译质量：不测

### 测试策略

- 导航与确认取消用单测；语言用手工矩阵

### 未知契约清单

<!-- 规范（门禁必留，不得删除） -->

未核实的外部契约标为 `UNVERIFIED-BLOCKING` 或 `UNVERIFIED-SPIKE`；核实后改写为结论和验证方式。无则写“无”。

<!-- /规范 -->

- 无

### 风险与回退

- 风险：SwiftUI 语言覆盖需改 `AppleLanguages` 或自定义 bundle
- 回退：覆盖后提示重启 App 也可接受，须写在设置页

### 依赖与约束

- 依赖 t002

### Finalization 时更新的 blueprint

- `docs/blueprint/conventions.md`：本地化覆盖方式

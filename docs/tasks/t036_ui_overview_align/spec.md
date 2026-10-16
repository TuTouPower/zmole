# Task spec

## 背景

UI 对齐修复。2026-10-17 用户批准：概览页按 demo 重排，并裁定删除快捷卡（demo `renderOverview` 无此区块，其 `quickCard` 函数为未调用死代码；`ui_contract.md` 的「快捷卡片」条目为冲突项，已批准一并更新）。

**参考 demo 在哪里：**

- 视觉权威：`docs/design/mole_desktop_demo_cn_final.html` 的 `renderOverview`（第 839 行）及其下半区辅助函数 `activityRow`（第 931 行）；相关 CSS：`.overview-hero`、`.health-card`/`.health-ring`（第 132 行附近）、`.overview-storage*`、`.disk-capacity-bar`、`.storage-legend`、`.overview-status-grid`、`.stat-strip`。
- 对照方法：浏览器直接打开 HTML，或 headless Chrome `--blink-settings=preferredColorScheme=1|2` 强制浅深色截图；app 侧用 `Zmole --demo --demo-page overview --demo-state populated --demo-language zh-Hans --demo-appearance dark|light --demo-data-root <dir>`（见 `docs/design/demo_launch.md`）。
- 语义基线：`docs/design/ui_contract.md`「概览」行。用户已裁定「快捷卡片」「趋势条」两个条目按 demo 对齐删除/替换，本 task 负责同步更新该文档。
- 设计 token 已对齐（`src/zmole/App/MoleTheme.swift`），无需改 token。

现状（`src/zmole/Features/Overview/OverviewView.swift`）：页头无动作按钮；健康卡为大数字 92+三指标（无圆环、无文案）；存储卡为环形图+图例列表；下半区为最近操作（纯文本行）+趋势柱条；另有 3 张快捷卡（demo 无）。

## 契约区

### 范围

- 页头右侧增加动作区：「刷新」（触发状态重采样）与清理入口按钮（跳转清理页；空间数值来自现有可回收数据源，无数据时显示纯入口文案）。
- 健康卡改为 demo 结构：圆环显示健康分 + 状态文案 + 三个指标 tile；tile 数值使用真实数据源（可用空间、CPU 或内存等现有采样），无法提供的指标显示占位，不伪造。
- 存储卡改为 demo 结构：大数字（当前已用）+ 五段分段条 + 图例（名称+数值），数据沿用现有存储估算。
- 下半区改为：最近活动（demo `activityRow` 结构：图标+标题+时间+数值+注记）与系统状态四宫格（CPU/内存/温度/网络，真实采样，缺失显示占位）。
- 删除快捷卡区块与趋势条区块。
- 同步更新 `docs/design/ui_contract.md`「概览」行：移除「快捷卡片」「趋势条」，改记「页头动作、健康环、存储分段条、最近活动、系统状态四宫格」。

### 非范围

- 不改存储估算口径（属 t034）。
- 不改状态页图表（属 t037）。
- 不改其它页面。

### 验收标准

<!-- 规范（门禁必留，不得删除） -->

只写可观察、可独立验证的行为；每条使用稳定且不复用的 `AC-NNN`。需真实部署或人工环境验证时在编号前加 `[deploy]`。技术选型不作为行为 AC。

<!-- /规范 -->

- [ ] AC-001：概览页头右侧显示「刷新」与清理入口按钮；点击刷新触发状态重采样，点击清理进入清理页。
- [ ] AC-002：健康卡显示健康分圆环与状态文案；健康分不可用时显示占位而非 0。
- [ ] AC-003：健康卡三个指标 tile 的数值来自真实采样；对应数据缺失时显示占位。
- [ ] AC-004：存储卡显示已用容量大数字、五段分段条与带数值图例；估算不完整时如实显示不完整状态。
- [ ] AC-005：下半区左侧为最近活动（图标+标题+时间+数值）；无记录显示空状态。
- [ ] AC-006：下半区右侧为系统状态四宫格（CPU/内存/温度/网络）；字段缺失显示占位，不伪造趋势与数值。
- [ ] AC-007：页面不再出现快捷卡区块与趋势条区块。
- [ ] AC-008：浅色/深色、简中/繁中/英文、1200×780 与 1100×700 下页面无裁切，主要动作可见。

### 可测试性声明

<!-- 规范（门禁必留，不得删除） -->

逐条说明不可自动测试的 AC 及替代验证；全部可测则写“全部 AC 可自动测试”。

<!-- /规范 -->

- AC-001～AC-008：视觉布局以截图对照验证，不可单测断言。替代验证：`--demo` 模式深浅色截图与 demo HTML 同视口渲染对照；数据缺失占位与不伪造行为可用 demo 的 `--demo-state stale/empty/partial` 状态截图覆盖，其中占位逻辑若涉及 ViewModel 计算可加组件级单测。

## 上下文区

- 来源：2026-10-17 用户批准「UI 级别 2 修复」（评估报告 b 项）；快捷卡删除与页头动作位置为同日用户裁定。

### 有意不测

- 圆环/分段条的像素级弧度与比例：设计近似，不设精确断言。

### 测试策略

- 复用 `--demo-state` 的 populated/empty/partial/stale 驱动页面截图；涉及数值格式的函数（如容量、百分比）保持或补充现有单测。

### 未知契约清单

<!-- 规范（门禁必留，不得删除） -->

未核实的外部契约标为 `UNVERIFIED-BLOCKING` 或 `UNVERIFIED-SPIKE`；核实后改写为结论和验证方式。无则写“无”。

<!-- /规范 -->

- 无。

### 风险与回退

- 风险：健康卡与四宫格的部分指标（如运行时间）在现有数据源中不存在，需以占位呈现，不能引入假数据；demo 数值不可当作需求。
- 回退：单 commit 还原。

### 依赖与约束

- 与 t034 同改概览页相关文件，需串行（conflicts_with 已标）。
- 保留 `ui_contract.md` 其它概览语义（真实采样、不伪造趋势）。

### Finalization 时更新的 blueprint

- `docs/design/ui_contract.md`：「概览」行（本 task 范围内直接更新）。

# Task spec

## 背景

UI 对齐修复。2026-10-17 用户批准：状态页对齐 demo 的指标条与系统负载图。当前 app 状态页没有折线图，指标结构也与 demo 不同。

**参考 demo 在哪里：**

- 视觉权威：`docs/design/mole_desktop_demo_cn_final.html` 的 `renderStatus`（第 1131 行）；相关 CSS：`.stat-strip`/`.stat-tile`（第 220 行附近）、`.line-chart`/`.chart-svg`/`.chart-card`、`.lower-grid`、`.process-row`。
- 对照方法：浏览器直接打开 HTML，或 headless Chrome `--blink-settings=preferredColorScheme=1|2` 强制浅深色截图；app 侧用 `Zmole --demo --demo-page status --demo-state populated --demo-language zh-Hans --demo-appearance dark|light --demo-data-root <dir>`。
- 语义基线：`docs/design/ui_contract.md`「状态」行（真实 watch 数据、首帧待采样、暂停与离页停止、旧数据显式标记、采样不足不伪造趋势）。
- 设计 token 已对齐（`src/zmole/App/MoleTheme.swift`），无需改 token。

现状（`src/zmole/Features/Status/StatusView.swift`）：顶部为状态点+时间+暂停/刷新条（页头由 t035 统一，本 task 不负责）；内容为 3 个指标卡（健康分/CPU/内存）+ 磁盘/IO/网络 3 panel + 温度 panel + 进程列表；无折线图。

## 契约区

### 范围

- 指标区改为 4 格 stat-strip：CPU、内存、磁盘写入、温度；数值来自现有 watch 采样，字段缺失显示占位（demo 中「CPU · 8 核心」的核心数若现有数据源没有则省略该注记）。
- 新增系统负载折线图卡：展示最近 60 秒 CPU 与内存两条序列（复用现有 `series` 数据）；采样不足时显示等待说明，不画假线。
- 保留：网络面板（下载/上传）、进程列表（只读快照，不结束进程）、暂停/恢复与离页停止行为、陈旧进程数据标记。
- 布局顺序对齐 demo：页头（t035 提供）→ 指标条 → 负载图与网络卡并排 → 进程表。

### 非范围

- 页头与页面动作按钮（属 t035）。
- 不新增进程结束动作（保持只读，符合 ui_contract「不结束进程」语义）。
- 不改 watch 采样与断流逻辑本身。

### 验收标准

<!-- 规范（门禁必留，不得删除） -->

只写可观察、可独立验证的行为；每条使用稳定且不复用的 `AC-NNN`。需真实部署或人工环境验证时在编号前加 `[deploy]`。技术选型不作为行为 AC。

<!-- /规范 -->

- [ ] AC-001：指标区为 4 格（CPU、内存、磁盘写入、温度）；各格数值来自真实采样，不可用字段显示占位符。
- [ ] AC-002：系统负载图显示 CPU 与内存两条序列，数据来自最近 60 秒采样。
- [ ] AC-003：采样点不足时负载图显示等待说明，不绘制伪造趋势。
- [ ] AC-004：网络面板显示下载/上传速率；首帧或 warming 阶段显示采样中说明。
- [ ] AC-005：进程列表保持只读（无结束进程入口），陈旧数据仍显式标记。
- [ ] AC-006：暂停/恢复与离页停止行为不变。
- [ ] AC-007：浅色/深色下图表与占位状态可辨；1200×780 与 1100×700 无裁切。

### 可测试性声明

<!-- 规范（门禁必留，不得删除） -->

逐条说明不可自动测试的 AC 及替代验证；全部可测则写“全部 AC 可自动测试”。

<!-- /规范 -->

- AC-001～AC-004、AC-007：视觉与截图对照验证；替代验证：`--demo` 各状态截图（populated/empty/busy/stale）+ 与 demo HTML 同视口渲染对照。
- AC-005、AC-006：可部分自动化——沿用/补充 `StatusStreamTests` 与 StatusViewModel 单测断言暂停、恢复、离页停止与陈旧标记路径。

## 上下文区

- 来源：2026-10-17 用户批准「UI 级别 2 修复」（评估报告 c 项）。

### 有意不测

- 图表曲线的具体形状：由采样驱动，不做像素断言；只验证两条序列存在与数据来源。

### 测试策略

- 复用 `StatusStreamTests` 夹具验证首帧渐进、暂停/恢复、断流；新增图表数据准备逻辑（如有）走组件级单测；截图对照 demo。

### 未知契约清单

<!-- 规范（门禁必留，不得删除） -->

未核实的外部契约标为 `UNVERIFIED-BLOCKING` 或 `UNVERIFIED-SPIKE`；核实后改写为结论和验证方式。无则写“无”。

<!-- /规范 -->

- 无。

### 风险与回退

- 风险：折线图与现有 `series` 数据结构的对接（采样间隔、点数上限）；60 秒窗口的裁剪逻辑需明确。
- 回退：单 commit 还原，不影响采样逻辑。

### 依赖与约束

- 与 t035 改同一文件，需串行（conflicts_with 已标）。
- 保持 ui_contract 的「采样不足不伪造趋势」「旧数据显式标记」语义。

### Finalization 时更新的 blueprint

- `docs/design/ui_contract.md`：「状态」行如与实现描述有出入则同步（页头由 t035 更新）。

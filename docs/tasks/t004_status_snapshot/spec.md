# Task spec

## 背景

status 有 `--json`，适合做成只读看板。不做 `--watch`。

## 契约区

### 范围

- `mole status --json` 经 Bridge；展示健康分与 CPU、内存、磁盘摘要
- 加载中、失败、JSON 损坏态
- 显式传 `--json`，不依赖「非 TTY 自动 JSON」
- 刷新按钮：成功后更新上述字段

### 非范围

- 交互式 TUI、`--watch`、进程杀除

### 验收标准

<!-- 规范（门禁必留，不得删除） -->

只写可观察、可独立验证的行为；每条使用稳定且不复用的 `AC-NNN`。需真实部署或人工环境验证时在编号前加 `[deploy]`。技术选型不作为行为 AC。

<!-- /规范 -->

- [ ] AC-001：对 `s001` 夹具 JSON，界面展示 `health_score`，以及 CPU 用量（或 `cpu.usage`）、内存 used/total（或 used_percent）、至少一块磁盘 used/total（或 used_percent）
- [ ] AC-002：非零退出或非法 JSON 时可见错误文案，不展示过期成功数据冒充当前结果，不崩溃
- [ ] AC-003：Bridge 参数含 `status` 与 `--json`
- [ ] [deploy] AC-004：对捆绑 mole 点刷新后，健康分与 CPU/内存/磁盘区域均有数值（本机）

### 可测试性声明

<!-- 规范（门禁必留，不得删除） -->

逐条说明不可自动测试的 AC 及替代验证；全部可测则写“全部 AC 可自动测试”。

<!-- /规范 -->

- AC-001、AC-002、AC-003：自动
- AC-004：本机手工

## 上下文区

- 来源：`docs/plan.md`；字段见 `samples/status_json.shape.json`

### 有意不测

- 健康分算法：不测（上游）

### 测试策略

- fixture 解码后断言 UI/ViewModel 字段；参数断言为辅

### 未知契约清单

<!-- 规范（门禁必留，不得删除） -->

未核实的外部契约标为 `UNVERIFIED-BLOCKING` 或 `UNVERIFIED-SPIKE`；核实后改写为结论和验证方式。无则写“无”。

<!-- /规范 -->

- 无。s001 已抓非空 status 对象。

### 风险与回退

- 风险：字段增删导致严格解码失败
- 回退：关键字段缺失则错误态，多余字段忽略

### 依赖与约束

- 依赖 t003；夹具 s001 status_json

### Finalization 时更新的 blueprint

- 无（稳定后可补 `schemas/mole_cli/`，非本 task 必须）

# Task spec

## 背景

磁盘浏览用 `analyze --json`。第一版不提供删除。`--json` 必须在路径参数之前。

## 契约区

### 范围

- overview：`analyze --json`
- 下钻：`analyze --json <path>`
- 加载/失败态；无删除按钮、无把选中项移到废纸篓的操作

### 非范围

- 交互 TUI、删除、外部卷专项（可后加路径入口但不删）

### 验收标准

<!-- 规范（门禁必留，不得删除） -->

只写可观察、可独立验证的行为；每条使用稳定且不复用的 `AC-NNN`。需真实部署或人工环境验证时在编号前加 `[deploy]`。技术选型不作为行为 AC。

<!-- /规范 -->

- [ ] AC-001：overview 夹具展示 entries 名称与 size
- [ ] AC-002：下钻时 argv 中 `--json` 出现在路径之前
- [ ] AC-003：界面无删除/移到废纸篓动作
- [ ] [deploy] AC-004：对本机捆绑 mole 能打开 overview 且不进入 TUI（无全屏清屏占用 App）

### 可测试性声明

<!-- 规范（门禁必留，不得删除） -->

逐条说明不可自动测试的 AC 及替代验证；全部可测则写“全部 AC 可自动测试”。

<!-- /规范 -->

- AC-001–AC-003：自动
- AC-004：手工

## 上下文区

- 来源：ADR-004；p002 已 park 删除

### 有意不测

- 扫描性能与大目录内存：本 task 不设指标

### 测试策略

- fixture + argv 断言；UI 无删除控件

### 未知契约清单

<!-- 规范（门禁必留，不得删除） -->

未核实的外部契约标为 `UNVERIFIED-BLOCKING` 或 `UNVERIFIED-SPIKE`；核实后改写为结论和验证方式。无则写“无”。

<!-- /规范 -->

- 无。s001：overview=`path/overview/entries/total_size`；路径扫描另有 `large_files`/`total_files`。`--json` 在路径前。

### 风险与回退

- 风险：大目录 JSON 很大导致 UI 卡顿
- 回退：列表虚拟化或限制展示条数并标明截断

### 依赖与约束

- 依赖 t003

### Finalization 时更新的 blueprint

- 无

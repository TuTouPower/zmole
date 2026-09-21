# Task spec

## 背景

`mo history --json` 可回答「mole 删过什么」。s001 只抓到空 `sessions`/`deletions`。单条记录字段以锁定源码 `lib/core/history.sh` 的 `history_render_json_*` 为准，样例见 `samples/history_json.schema_from_source.json`。默认 limit=20，上限 200。

## 契约区

### 范围

- `history --json --limit`：默认 20；可设 1–200；超出交给 mole 钳制或 UI 先挡住
- 列表展示会话摘要：`command`、`started_at` 或 `ended_at`、`items`/`size` 至少一类
- 无记录空态；Bridge 失败或非法 JSON 为失败态

### 非范围

- 改日志文件、撤销删除

### 验收标准

<!-- 规范（门禁必留，不得删除） -->

只写可观察、可独立验证的行为；每条使用稳定且不复用的 `AC-NNN`。需真实部署或人工环境验证时在编号前加 `[deploy]`。技术选型不作为行为 AC。

<!-- /规范 -->

- [ ] AC-001：按源码字段构造的非空 `sessions` 夹具，列表展示对应 `command` 与时间之一
- [ ] AC-002：`sessions` 与 `deletions` 皆空时显示空态而非崩溃
- [ ] AC-003：默认刷新的 Bridge 调用含 `history`、`--json`、`--limit 20`
- [ ] AC-004：limit=1 时 argv 为 `--limit 1`；UI 不发送 0
- [ ] AC-005：非零退出或非法 JSON 时失败态，不把空列表当成「没有历史」除非 mole 成功返回空数组

### 可测试性声明

<!-- 规范（门禁必留，不得删除） -->

逐条说明不可自动测试的 AC 及替代验证；全部可测则写“全部 AC 可自动测试”。

<!-- /规范 -->

- 全部 AC 可自动测试

## 上下文区

- 来源：s001 空态顶层形状；记录字段来自 `history_render_json_sessions` / `_deletions`（command/started_at/ended_at/items/size/operation_count/failed_tasks/actions.\* 与 timestamp/mode/status/size_kb/path）

### 有意不测

- 日志轮转与磁盘上 oplog 格式：不测

### 测试策略

- 空夹具 + 源码字段合成非空夹具；失败夹具

### 未知契约清单

<!-- 规范（门禁必留，不得删除） -->

未核实的外部契约标为 `UNVERIFIED-BLOCKING` 或 `UNVERIFIED-SPIKE`；核实后改写为结论和验证方式。无则写“无”。

<!-- /规范 -->

- 无。顶层键 s001 已见；元素字段以源码为准并写入 `history_json.schema_from_source.json`（非运行抓取）。

### 风险与回退

- 风险：源码字段改名
- 回退：解码失败走失败态

### 依赖与约束

- 依赖 t003

### Finalization 时更新的 blueprint

- 无

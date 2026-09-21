# Task spec

## 背景

clean 会永久删除。必须**本次**预览成功后再确认。非 TTY 下 mole 会自动跑用户级清理，故未确认不得 spawn 无 `--dry-run` 的 clean。

本 task 同时定下 t009–t011 共用的预览新鲜度与执行生命周期（实现放共享类型/组件）。

## 契约区

### 范围

- `clean --dry-run` 成功结束后读取**本次**写出的 `clean-list.txt`（路径可注入）；展示并标明「执行会重扫」
- 仅当存在未过期的成功预览时，确认才可点。过期：预览失败、用户取消预览、确认对话框取消、再次点预览、list 文件不是这次 run 写的
- 确认后 spawn `clean`（无 dry-run）；取消则不 spawn 执行
- 复用 t003 确认组件
- 执行中：忙碌，忽略重复点击；提供取消，取消须结束 Bridge 中的 Process；失败/部分完成展示 mole 输出摘要
- 切到其它侧栏项再回来：不得自动再 spawn；若仍忙碌则显示进行中

### 非范围

- `--external`、whitelist TUI、系统级 sudo 策略定制（沿用 mole osascript）

### 验收标准

<!-- 规范（门禁必留，不得删除） -->

只写可观察、可独立验证的行为；每条使用稳定且不复用的 `AC-NNN`。需真实部署或人工环境验证时在编号前加 `[deploy]`。技术选型不作为行为 AC。

<!-- /规范 -->

- [ ] AC-001：预览调用的 argv 含 `clean` 与 `--dry-run`
- [ ] AC-002：确认前，执行用 Bridge 方法调用次数为 0（无 dry-run 的 clean）
- [ ] AC-003：用户取消确认后，仍不出现无 `--dry-run` 的 clean，且预览标记为过期，需重新预览才能再确认
- [ ] AC-004：本次预览成功后确认，argv 为 `clean` 且不含 `--dry-run`
- [ ] AC-005：预览 UI 含「执行时会重新扫描、列表可能变化」的说明
- [ ] AC-006：dry-run 非零或未写出本次 list 文件时，界面为预览失败，确认不可用；不得展示目录里旧的 `clean-list.txt`
- [ ] AC-007：执行过程中再次点击执行不创建第二个 Process
- [ ] AC-008：执行中点取消后，Bridge `cancel` 被调用，忙碌结束
- [ ] AC-009：执行非零退出时展示失败摘要，不假装成功

### 可测试性声明

<!-- 规范（门禁必留，不得删除） -->

逐条说明不可自动测试的 AC 及替代验证；全部可测则写“全部 AC 可自动测试”。

<!-- /规范 -->

- AC-001–AC-004、AC-006–AC-009：假 Bridge spy 自动
- AC-005：UI 文案测试或 snapshot

## 上下文区

- 来源：ADR-004；审阅 P1 预览约束、P2 生命周期

### 有意不测

- 真机删除效果：不进自动测试

### 测试策略

- spy 参数、调用次数、预览世代 token；旧 list 文件夹具

### 未知契约清单

<!-- 规范（门禁必留，不得删除） -->

未核实的外部契约标为 `UNVERIFIED-BLOCKING` 或 `UNVERIFIED-SPIKE`；核实后改写为结论和验证方式。无则写“无”。

<!-- /规范 -->

- 无。s001：`clean --dry-run` 写出 `$HOME/.config/mole/clean-list.txt`

### 风险与回退

- 风险：误 spawn 真实 clean；读到上次预览文件
- 回退：预览世代 token；执行入口检查 token

### 依赖与约束

- 依赖 t003；review_level=full；生命周期依赖 t002 的 cancel/忙碌 API

### Finalization 时更新的 blueprint

- 无

# Task spec

## 背景

uninstall_stream_apps 用 fd 3 保留 stdout；start_uninstall_metadata_refresh 的 disown 后台分支继承该 fd。提取生产函数并替换大小探测后，主命令约 5 ms 退出、EOF 约 1241 ms；关闭 fd 后 EOF 约 5 ms。但仅关闭 fd 会使仍在扫描的 worker 脱离 Bridge 生命周期，绕过后续资源名额。目标是流式名单的全部工作受父命令管理，结束事件代表工作真正结束。

本文件描述本 task 完成后的目标，当前状态仍为 backlog。

## 契约区

### 范围

- --list-stream 采用受父命令管理的元数据解析流程：worker 可以并发，但必须被登记、等待和取消；不启动退出后继续扫描的 disown 任务。交互式卸载的后台缓存策略不在本 task 改动范围。
- 名单先发布身份行；本轮需要更新的元数据通过受管 worker 完成后合并到完整行，成功 done 标记在全部必需 worker 成功或明确完成其可容忍缺字段处理后发出。不能为同一行重复计算同一字段大小。
- 不需要写流的 worker 在开始长工作前关闭继承的名单流 fd 和其他无关管道写端，stdin 保留 /dev/null；真正发布名单的父进程保留 fd 3。
- 父进程收到取消、超时或异常时停止并等待自己的 worker，再退出；取消不发送成功 done。支持取消整组进程的 Bridge 仍同时等待退出码与 stdout/stderr 完成，不以提前忽略输出解决 EOF。
- 元数据不可读的行保留身份与显式未知，不把失败大小变成 0；致命 worker 错误传递失败终态。退出码、done 与允许的缺字段边界保持一致。

### 非范围

- Homebrew 索引、GUI 任务订阅和资源调度策略。
- lib/manage/update.sh、其他非 --list-stream 的后台任务及真实卸载。

### 验收标准

<!-- 规范（门禁必留，不得删除） -->

只写可观察、可独立验证的行为；每条使用稳定且不复用的 `AC-NNN`。需真实部署或人工环境验证时在编号前加 `[deploy]`。技术选型不作为行为 AC。

<!-- /规范 -->

- [ ] AC-003：子进程退出码已得到但输出管道仍开着时 Bridge 不返回；全部管道关闭后返回并保留退出码。
- [ ] AC-004：元数据 worker 的 stdin 仍为 /dev/null，不读取控制终端。
- [ ] AC-005：元数据 worker 被挡住时身份行已可见，成功 done 和父命令退出尚未发生；放行后才输出最终行与 done，父退出时没有存活扫描 worker。
- [ ] AC-006：--list-stream 取消或超时后，受管 worker 全部退出，没有继续读取目录的后台任务；不输出成功 done。
- [ ] AC-007：不发布名单的 worker 不持有名单管道；父进程退出至 EOF 在受控夹具中不依赖另一个长任务结束，且对照夹具保留 fd 时确实会等待。
- [ ] AC-008：同一名单行本轮所需大小只探测一次；元数据不可读仍保留身份、大小未知，致命错误不能返回成功 done。

### 可测试性声明

<!-- 规范（门禁必留，不得删除） -->

逐条说明不可自动测试的 AC 及替代验证；全部可测则写“全部 AC 可自动测试”。

<!-- /规范 -->

- 全部 AC 可自动测试。提取或 source 生产 --list-stream 分支，用管道屏障、worker PID/读取计数和临时 App 夹具验证，不扫描开发机应用。

## 上下文区

- 来源：无；2026-10-17 生产函数隔离复现见 `.scratch/task_review_20261017`；稳定入口为 bin/uninstall.sh 的 start_uninstall_metadata_refresh 与 uninstall_stream_apps。

### 有意不测

- 不调用真实 Homebrew 或真实卸载；不拿固定真机耗时证明 worker 生命周期正确。

### 测试策略

- 在生产函数的大小读取入口注入阻塞，断言身份先到、done 后到、父仍存活；放行后验证 worker 全退出。
- 原 EOF 正反对照保留，但从“命令看似变快”改为验证无多余管道持有者；使用同步屏障，仅以宽松超时防挂死。
- MoleBridge 的退出码/EOF 双条件、取消进程组与 worker 清理均走生产 Bridge 路径；不绕过 completion 条件。
- 覆盖成功、不可读、worker 崩溃、SIGTERM 和超时；现有卸载流字段及身份断言保留。

### 未知契约清单

<!-- 规范（门禁必留，不得删除） -->

未核实的外部契约标为 `UNVERIFIED-BLOCKING` 或 `UNVERIFIED-SPIKE`；核实后改写为结论和验证方式。无则写“无”。

<!-- /规范 -->

- 无。

### 风险与回退

- 风险：等待元数据会延长真正完成时间，但首批身份必须及时出现；不能靠留下失管工作伪造完成。
- 风险：关闭发布者 fd 会中断名单，只关闭非发布 worker 的写端。
- 回退：撤回受管流式分支与相关本地补丁；Bridge 完成条件及交互式终端保护保持不变。

### 依赖与约束

- 无硬依赖；t048 必须依赖本 task 的真实进程生命周期。t054 共改卸载脚本，属于文件冲突而非行为依赖。
- macOS、Bash 3.2；只改仓库捆绑脚本。

### Finalization 时更新的 blueprint

- `docs/blueprint/architecture.md`、`docs/specs/uninstall.md`：受管元数据 worker、渐进身份与真正完成时点。
- `docs/specs/mole_bridge.md`：进程及管道双条件、子任务取消与名额生命周期。

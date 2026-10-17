# 捆绑 mole 桥接（mole_bridge）

- 来源 task：t002、t025、t027、t053、t057、t048；（2026-10-17 审阅采纳加固随附）
- 生效范围：进程 spawn、参数拼装、输出解析、并发通道、忙碌语义、资源准入与共享文件所有权
- 最后更新：2026-10-18

## 行为契约

- 唯一 spawn 层是 `MoleBridge`；只执行 `.app` 内 `Contents/Resources/mole/mole`（绝对路径），不搜 PATH、不调用系统 `mo`、不把命令装进 PATH；生产环境不调用 `update`/`remove`。
- `run(argv)` 以参数数组传参（无 shell 拼接）；捕获 stdout/stderr 与退出码；满足进程终止且管道全部 EOF 双条件后返回并保留退出码，非零退出返回可展示错误（含输出摘要）。
- 每个 Bridge 实例同时只允许一个 active runner；in-flight 时第二次 `run` 返回 `busy`（不创建第二个进程）；`cancel` 结束整个进程组（TERM，0.25s 后 KILL，发送前复核进程组身份）。
- 非流式输出有每通道 16MB 上限；流式 stdout 逐行解析、按块加锁；EOF 时排出未成行的尾段。
- 子进程环境继承父环境但剥离全部 `MOLE_*` 变量；stdin 写端忽略 SIGPIPE（`F_SETNOSIGPIPE`），写失败不影响进程存活。
- 应用装配按命令分通道（`MoleCommandLanes`）：每个一次性消费者（history、uninstall、installer、clean 执行、optimize、purge）各持独立 Bridge，互不阻塞；概览估算持 3 条通道并发探测；卸载名单流、状态流各持独立实例，后台五类扫描各持独立实例。写入命令之间由 `OperationCoordinator` 单一租约互斥。
- 重扫描资源调度：五类后台只读命令与概览目录探测均接入全局唯一 `HeavyScanScheduler` 进行并发准入与名额计账；通道可用性作为准入前提，不占名额等待忙碌通道，亦不占通道等待名额。
- clean 文件所有权：后台 clean 扫描对 `~/.config/mole/clean-list.txt` 的所有权延伸至后台快照读取与解析完全结束；用户 clean 执行或接管开始前，除取消子进程外，必须等待在飞的读取解析任务退出并释放文件，旧解析放行后不得覆盖新世代。
- 忙碌错误语义：任何页面遇到 `busy` 显示可恢复提示（非失败），重试可成功。
- 应用退出时取消全部活跃 runner 与流，限时等待 2 秒，避免破坏性子进程在 GUI 退出后继续执行。
- 日志：MoleBridge 关键路径经 os.Logger 记录子命令、退出码、耗时、错误类别（不记完整 argv/输出）。

## 验证

- `tests/unit/MoleBridgeTests.swift`、`tests/unit/MoleStreamTests.swift`
- `tests/unit/CommandConcurrencyTests.swift`（独立通道、同桥 busy 拒绝、写互斥）
- `tests/unit/RecoverableBusyTests.swift`

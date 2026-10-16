# p007 概览五段磁盘估算改为缓存并后台刷新（不要按钮）

- 来源：用户实测反馈 2026-10-16（2026-10-16 修订：不做按钮触发）
- 内容：概览页开屏自动串行执行 4 次 `analyze`（/Applications、/System、~/Library/Developer、/Users）算五段估算；/Users 类扫描可达数十秒到数分钟，且占用共用命令通道，表现为“数据出不来、一直在算”。不做“点击计算”按钮；改为：开屏先用缓存立即出结果，后台在独立只读通道刷新，刷新期间不阻塞其他页面命令。缓存与刷新策略见下。
- 处理：t026
- 缓存设计：
    - 缓存对象：4 个目录的字节和（apps/system/developer/users）+ 采集时间；不缓存最终五段（“其他”每次用 status 已用空间重算）。
    - 存储：进程内 + 磁盘各一份。磁盘落 `~/Library/Application Support/zmole/storage_estimate.json`（`{schemaVersion, capturedAt, apps, system, developer, users}`），原子写；schema 不符或超过最大年龄（如 7 天）视为无效。
    - 读取/渲染：概览出现时先读磁盘缓存，有则立刻渲染（容量来自 status，五段标“估算”）；无缓存则先只显示容量与占位，后台计算完成后填充。
    - 刷新触发（无按钮）：缓存缺失或超过 TTL（如 6h）时后台刷新；并复用 `OperationCoordinator.invalidationGeneration`——clean/purge/uninstall/installer/白名单保存成功会递增，概览据此将估算标脏并在后台重算。
    - 并发与去重：估算在独立只读通道串行执行 4 次 analyze，单次在飞时不再触发；依赖 p006，保证不占共用命令通道。
    - 容错：某个目录 analyze 失败/超时则该段缓存为空、界面显示占位；成功部分仍写缓存。demo 模式不走缓存，用夹具。

# 审阅结果决策

## 目录

docs/reviews/review_20261017_054534

## 报告来源

- 已读：bundle_v1_security.md, bundle_v2_correctness.md, bundle_v3_contract.md, bundle_v4_performance.md, bundle_v5_architecture.md, bundle_v6_robustness.md, bundle_v7_test_spec.md, bundle_v8_docs.md, review_intensive.md（intensive 路全部 bundle 已逐份通读）
- 缺失：无（本目录为 intensive-review 单模式运行；未发现 my-review 多模型路报告）
- 合并说明：聚合 161 条去重 finding → 97 项决策（85 采纳 + 12 不采纳）。主要聚类：
    - 死代码/未用 API 归并为 A60（12 条）、A61（5 条）、A62（2 条）
    - 性能微优化批次 A20（7 条：bundle_v4_performance 中 L 级 7 条）
    - 估算链路错误静默归并为 A21（4 条：StorageEstimate:107/152、OverviewViewModel:392、StorageEstimateCache:56）
    - i18n 缺口归并为 A51（10 个错误类型 + source 过滤 key）
    - 文档类归并为批次 A64–A68、A72–A74
    - 重复映射：bundle_v1_security:L14(202) ↔ bundle_v1 同项（MOLE\_\*）→ A75（原 D1）；bundle_v2_correctness:L15(105) ↔ bundle_v6_robustness:L19(203) → A10；bundle_v2_correctness:L24(427) ↔ bundle_v4_performance:L16(427) → A7；bundle_v2_correctness:L23(353) ↔ bundle_v1_security:L23(358) → A37；bundle_v3_contract:L14(H20) ↔ 聚合（CHALLENGED）→ R1

## 统计

- 采纳：85 项（A75–A85 由 D1–D11 决策转入）
- 不采纳：12 项
- 待决定：0 项

## 待决定项（请先决策）

无——D1–D11 已全部决策并并入采纳项 A75–A85：D8 按用户选择 A（全量补写 spec），其余按推荐（D1 B、D2 A、D3 A、D4 A、D5 A、D6 A、D7 A、D9 A、D10 B、D11 A）。

## 采纳项

### A1. stdin 管道写入无 SIGPIPE 防护，可致整个 app 被杀

- 来源：bundle_v1_security, bundle_v6_robustness
- 位置：src/zmole/MoleBridge/MoleBridge.swift:312-317
- 优先级：CRITICAL
- 详细判断理由：唯一 stdin 写点与子进程退出/取消/超时存在竞态；macOS 对无读端管道 write 默认发 SIGPIPE 终止进程，全仓无 signal(SIGPIPE, SIG_IGN)/F_SETNOSIGPIPE（rg 证实），未忽略时写失败还会抛 Swift 不可捕获的 NSFileHandleOperationException。修复成本极低。
- 修复说明：进程启动早期设 `signal(SIGPIPE, SIG_IGN)`，或对 stdin 写端 fd 执行 `fcntl(fd, F_SETNOSIGPIPE, 1)`；写入改 `try? stdinPipe.fileHandleForWriting.write(contentsOf: stdin)` 并容忍 EPIPE（子进程已退出）。

### A2. parseHumanSize 不识别 mole 实际紧凑格式，可回收合计恒 0

- 来源：bundle_v2_correctness, bundle_v5_architecture, bundle_v6_robustness
- 位置：src/zmole/Features/Clean/CleanPreviewModel.swift:96-114
- 优先级：HIGH
- 详细判断理由：真实输出为 "2.40GB"/"512MB"（`printf "%d.%02dGB"`，无空格），解析器按空格切分必然 nil；连带可回收 tile/徽标/概览入口全显示 0；夹具用带空格格式掩盖；另 :113 直接 `Int64(...)` 在超长数字时可 trap。UninstallSizeParser 已有正确实现，属解析器单侧问题。
- 修复说明：改为解析 `<数值><可选空格><单位>`（无单位按 B、单位大小写不敏感）；加 `value.isFinite && value <= Double(Int64.max)` 越界返回 nil；将 UninstallSizeParser.bytes（UninstallSnapshot.swift:260-310）提为共享工具并复用；tests/unit/CleanPageTests.swift:50-51 夹具换真实行（`/x  # 2.40GB, 18 items`、`512MB`、`123KB`）。

### A3. relatedPaths 过滤与真实 dry-run 行不匹配，关联文件面板恒空

- 来源：bundle_v2_correctness
- 位置：src/zmole/Features/Uninstall/UninstallViewModel.swift:295-305
- 优先级：HIGH
- 详细判断理由：真实行以 "✓ " 前缀或 "System: "/"Review only: " 标签开头、路径后附 ` <size>`，过滤要求行首即 `/` 或 `~/`，全部被丢弃；夹具裸路径 + demo 输出裸路径掩盖，生产恒显示无关联文件。
- 修复说明：stripANSI 后取行内首个 `/` 或 `~/` 起子串，截掉尾随尺寸 token（`" ✓ /p 1.4GB"` → `/p`）；补真实格式夹具（tests/unit/UninstallDetailTests.swift:58）。

### A4. clean.error.failed 在 xcstrings 中缺失，界面显示原始 key

- 来源：bundle_v3_contract
- 位置：src/zmole/Features/Clean/CleanViewModel.swift:142（另 :258）
- 优先级：HIGH
- 详细判断理由：423 个 key 全量比对唯一缺口；失败横幅以 LocalizedStringKey 渲染该 key，三语界面都显示字面量；现有测试只断言 key 字符串不校验 catalog。
- 修复说明：Localizable.xcstrings 增加 clean.error.failed 三语条目；可在单测中断言 errorKey 集合均存在于 catalog（ZmoleTests.swift:650 加强）。

### A5. status 流错误在首次采样成功后永远不可见

- 来源：bundle_v6_robustness
- 位置：src/zmole/Features/Status/StatusView.swift:74
- 优先级：HIGH
- 详细判断理由：分支顺序 snapshot 非空即赢，errorMessage 永不渲染；断流后页面停在旧值、无文案无 retry，用户无法感知数据已死。
- 修复说明：错误提示与 snapshot 解耦（内容顶部 banner：UtilityNotice + retry），snapshot 非空时也渲染 errorMessage。

### A6. OverviewView 不渲染 errorMessage 且 try? 吞取消空转

- 来源：bundle_v3_contract, bundle_v5_architecture, bundle_v6_robustness
- 位置：src/zmole/Features/Overview/OverviewView.swift:14、:32-36
- 优先级：HIGH
- 详细判断理由：errorMessage 仅存在于 ViewModel（history 失败不可见）；`:32` 忙轮询 12 秒且 `try? await Task.sleep` 吞取消，离开页面后仍继续触发估算探测。两问题同页同链路，一并修。
- 修复说明：:14 渲染 errorMessage（UtilityNotice + retry 或并入活动卡）；:32 改订阅 statusViewModel.$snapshot 等待 usedBytes（事件驱动），并显式 `guard !Task.isCancelled` / do-catch 处理取消。

### A7. 流式 stdout 逐字节加锁，O(字节数) 次锁操作

- 来源：bundle_v2_correctness, bundle_v4_performance
- 位置：src/zmole/MoleBridge/MoleBridge.swift:427-446
- 优先级：HIGH
- 详细判断理由：64KB chunk → 约 65,536 次 NSLock 往返 + 逐字节 Data.append；list-stream/clean dry-run 数 MB 输出即数百万次锁。
- 修复说明：先按 0x0A 切块（data.split/memchr），每块一次性加锁处理；行缓冲语义不变；跑 MoleStreamTests 回归。

### A8. AnalyzeView 排序/筛选在 body 内执行且每次测量发布全量重排

- 来源：bundle_v4_performance
- 位置：src/zmole/Features/Analyze/AnalyzeView.swift:37-39
- 优先级：HIGH
- 详细判断理由：每次渲染执行 filter + localizedStandardCompare 排序；一层 N 个子目录 → N 次发布 × 每次重排，总成本 O(N² log N) 级 ICU 比较。
- 修复说明：把排序结果缓存进 AnalyzeViewModel（key = level generation + sort + search 或 apply 时增量维护有序数组），body 只读取；搜索去抖。

### A9. Analyze 被测子树全部层驻留并在 MainActor 批量插入

- 来源：bundle_v4_performance
- 位置：src/zmole/Features/Analyze/AnalyzeViewModel.swift:221
- 优先级：HIGH
- 详细判断理由：measureSubtree 返回整树 levels，apply 在主线程逐层写 records；大目录（~、/Users）内存数百 MB 且插入卡顿数百 ms 起。
- 修复说明：后台构造快照后一次性发布；records 设容量/深度上限或按需惰性填充（进入目录再 list）。

### A10. 用户预览与 prewarm 并发写同一 clean-list.txt，取消为异步 best-effort

- 来源：bundle_v2_correctness, bundle_v6_robustness
- 位置：src/zmole/Features/Clean/CleanViewModel.swift:105 / PrewarmService.swift:203
- 优先级：MEDIUM
- 详细判断理由：预跑被杀进程在扫描完成时会 tee 覆写同一最终文件；用户侧可能读到另一次扫描清单，verifyUnchanged 报「列表已变化」或审阅对象与执行对象不一致。
- 修复说明：预跑写完复查 cleanPreviewActiveProvider() 并丢弃结果；或 CleanPreviewStore.begin() 记录起始时间、read() 校验文件 mtime 不早于该时间；两者可并用。

### A11. clean 预览文件读取+解析在 MainActor 同步执行

- 来源：bundle_v4_performance
- 位置：src/zmole/Features/Clean/CleanViewModel.swift:117（PrewarmService.swift:212 同路径）
- 优先级：MEDIUM
- 详细判断理由：Data(contentsOf:) + 整文件 String + split + 解析，MB 级/数万行时主线程冻结。
- 修复说明：`await Task.detached { try store.read(generation) }` 或改 async read。

### A12. 名单流每行整表发布，触发逐行全量过滤+排序

- 来源：bundle_v4_performance
- 位置：src/zmole/Features/Uninstall/UninstallViewModel.swift:135
- 优先级：MEDIUM
- 详细判断理由：500 app ≈ 1000 次发布 × 每次 O(N log N) ICU 比较。
- 修复说明：按 50-100ms 或每 20 行合并发布；列表排序按 revision 缓存。

### A13. 概览估算多个目录探测全部串行，/System 子目录逐个 spawn

- 来源：bundle_v4_performance
- 位置：src/zmole/Features/Overview/StorageEstimate.swift:137-173
- 优先级：MEDIUM
- 详细判断理由：3 + N 次 analyze 子进程首尾相接，首次估算墙钟数十秒至分钟级。
- 修复说明：TaskGroup 2-4 路并发（estimate lane 需多条 bridge 或明确串行限制）；至少 /System 子项并行。

### A14. 清理预览全量行非惰性渲染

- 来源：bundle_v4_performance
- 位置：src/zmole/Features/Clean/CleanView.swift:131-133
- 优先级：MEDIUM
- 详细判断理由：ScrollView+VStack 展开上万行，每行图标+path+size+按钮全部实例化。
- 修复说明：换 LazyVStack（或 List）。

### A15. 矩形树图布局在 body 内每次渲染全量重算

- 来源：bundle_v4_performance
- 位置：src/zmole/Features/Analyze/AnalyzeView.swift:322
- 优先级：MEDIUM
- 详细判断理由：tiles() 做 filter+sort+递归 partition，测量发布/选中/resize 都全量重算。
- 修复说明：按 (entries 指纹, geometry size) 缓存 tiles；resize 仅在尺寸实质变化后重算。

### A16. canPreview 为 O(选中数×名单数)，被视图 disabled 高频求值

- 来源：bundle_v4_performance
- 位置：src/zmole/Features/Uninstall/UninstallViewModel.swift:75-77
- 优先级：MEDIUM
- 详细判断理由：每次渲染线性扫描，全选 500 项约 25 万次比较/渲染。
- 修复说明：`Set(listings.map(\.path))` O(1) 查询或选择变化时预计算。

### A17. 部分失败的估算永不缓存，每次进概览都重跑全量扫描

- 来源：bundle_v4_performance
- 位置：src/zmole/Features/Overview/OverviewViewModel.swift:332、:376
- 优先级：MEDIUM
- 详细判断理由：任一路径不可读即 estimateNeedsRefresh 恒真且不落盘；持久性失败导致每次进页重启数十秒扫描。
- 修复说明：失败路径设重试冷却（如 30 分钟 backoff），或缓存部分和只重试失败路径。

### A18. 图标逐个发布触发逐图标整页重渲染

- 来源：bundle_v4_performance
- 位置：src/zmole/Features/Uninstall/UninstallViewModel.swift:192-197
- 优先级：MEDIUM
- 详细判断理由：每图标一次 objectWillChange → 视图全量重算 visibleListings；500 app ≈ 500 次全页重排。
- 修复说明：批量收集后每 N 个（或 100ms）一次赋值，或非 @Published 容器 + 节流刷新。

### A19. 测量 worker 不可取消、严格串行、同子树可重复走

- 来源：bundle_v4_performance, bundle_v6_robustness
- 位置：src/zmole/Features/Analyze/AnalyzeViewModel.swift:188-198、DiskScanner.swift:197-256
- 优先级：MEDIUM
- 详细判断理由：walk 无 Task.checkCancellation 且跑在 detached，离页/刷新都无法停止；一层几十子目录串行测量时长成倍；测量中进入目录会重复走同一子树（磁盘 IO 翻倍）。
- 修复说明：walk 周期性 checkCancellation；measureSubtree 前检查 records 是否已有新鲜层（可复用则跳过）；2-4 路并发（保持 parent generation 校验）。

### A20. 性能细节批次（7 条低风险微优化）

- 来源：bundle_v4_performance
- 位置：见各条
- 优先级：LOW
- 详细判断理由：均为局部、无行为语义变化的结构优化，批处理减少流程开销。
- 修复说明：① MoleBridge.swift:564 `removeFirst` 改 `buffer.suffix(limit)` 低频压缩；② StatusSnapshot.swift:355 静态复用两个 ISO8601DateFormatter（fractional/无）；③ SettingsView.swift:135 SOURCE_VERSION 一次缓存；④ AnalyzeViewModel.swift:214 改增量累加 totalSize；⑤ OptimizeView.swift:8 接受 preview 时解析一次存 rows；⑥ HistoryView.swift:105 改 LazyVStack + 稳定行 id；⑦ AppDependencies.swift:711 活动通知去抖（200ms 或状态翻转）。

### A21. 估算链路错误全部静默 + 注释口径不符

- 来源：bundle_v3_contract, bundle_v6_robustness, bundle_v7_test_spec
- 位置：src/zmole/Features/Overview/StorageEstimate.swift:107、:152、OverviewViewModel.swift:392、StorageEstimateCache.swift:56
- 优先级：MEDIUM
- 详细判断理由：探测错误转 nil、空 catch、缓存 try? 三处全静默，busy/超时/权限/未启动不可区分，UI 只显示占位；:152 注释声称口径与实现（逐子项 analyze）不符。
- 修复说明：区分错误类别并透传/可重试标记（日志部分随 D2 决定一并接）；缓存写失败至少可诊断；:152 注释改为「只读系统卷目录子项之和（不探测 /System/Volumes）」。

### A22. 失败结果被同时以成功样式（checkmark）重复展示

- 来源：bundle_v6_robustness
- 位置：src/zmole/Features/Optimize/OptimizeView.swift:92（CleanView.swift:273、PurgeView.swift:94 同）
- 优先级：MEDIUM
- 详细判断理由：错误通知已渲染后，executionSummary 又以 success 样式通知渲染，误导成功。
- 修复说明：仅 succeeded 渲染带 checkmark 的结果通知；失败摘要并入错误通知 detail。

### A23. unregister 失败被 try? 静默吞掉，登录项开关状态与事实不符

- 来源：bundle_v6_robustness
- 位置：src/zmole/Features/Settings/LoginItem.swift:34
- 优先级：MEDIUM
- 详细判断理由：永不外抛；setEnabled(false) 后开关仍为开且 failureReason 为 nil。
- 修复说明：移除 try?，让错误走 setEnabled 的 catch 显示 failureReason。

### A24. PurgePaths load 失败时 errorKey 清成 nil，随后保存可覆盖原文件

- 来源：bundle_v6_robustness
- 位置：src/zmole/Features/Purge/PurgePaths.swift:84
- 优先级：MEDIUM
- 详细判断理由：非 PurgePathsError 令 errorKey 为 nil，编辑器显示空文本无错误，用户保存即以仅注释头内容重写 purge_paths。
- 修复说明：未知错误映射通用 errorKey 并禁用保存，或保留 NSError 描述。

### A25. 卸载成功后不刷新名单也不清选择

- 来源：bundle_v6_robustness
- 位置：src/zmole/Features/Uninstall/UninstallViewModel.swift:429
- 优先级：MEDIUM
- 详细判断理由：已卸载 app 仍可勾选再次 preview/execute；partial 时无法区分哪些行已消失。
- 修复说明：成功或 partial 后剔除已处理 path（参照 InstallersViewModel.removedPaths），必要时后台重扫。

### A26. UninstallView errorMessageKey 分支丢弃 executionSummary

- 来源：bundle_v6_robustness
- 位置：src/zmole/Features/Uninstall/UninstallView.swift:427
- 优先级：MEDIUM
- 详细判断理由：解析器已把 stdout/stderr 摘要放进 summary，该分支只渲染 title，失败细节丢失。
- 修复说明：该分支同时传 `detail: viewModel.executionSummary`。

### A27. 快速切页时 start/stop 竞争，watch 可能长期残留

- 来源：bundle_v6_robustness
- 位置：src/zmole/App/AppShellView.swift:116-123
- 优先级：MEDIUM
- 详细判断理由：stop 先跑、start 后置 wantsRunning=true，页面已离开且无 destination 变化则不再 stop。
- 修复说明：start 链路 subscribe 后校验当前目的地，非 overview/status 立即 stop；或期望状态 generation 丢弃过期启动。

### A28. 相关文件 dry-run 错误全部 try? 丢弃且无反馈

- 来源：bundle_v6_robustness
- 位置：src/zmole/Features/Uninstall/UninstallViewModel.swift:286
- 优先级：LOW
- 详细判断理由：busy/超时/非零退出静默返回，按钮保持可点无解释，与「无关联文件」状态混淆。
- 修复说明：失败置 transientErrorKey 提示重试，与已加载态区分。

### A29. 取消的名单扫描保留部分行且无「未完成」标识

- 来源：bundle_v6_robustness
- 位置：src/zmole/Features/Uninstall/UninstallViewModel.swift:138
- 优先级：LOW
- 详细判断理由：cancelled 分支不标记，用户误以为扫描完整。
- 修复说明：cancelled 时设置显式「扫描已取消/继续扫描」状态。

### A30. CLI「已连接」指示无条件显示

- 来源：bundle_v6_robustness
- 位置：src/zmole/Features/Settings/SettingsView.swift:91
- 优先级：LOW
- 详细判断理由：与可执行文件存在性/命令结果无关，缺 mole 时仍标绿。
- 修复说明：按 BundledMoleInfo.executableURL() 存在性/最近命令结果切换文案与颜色。

### A31. 导出失败的错误分支会顶替整张历史表

- 来源：bundle_v6_robustness
- 位置：src/zmole/Features/History/HistoryView.swift:41
- 优先级：LOW
- 详细判断理由：导出失败把页面切成错误提示且无恢复入口。
- 修复说明：导出错误改独立可关闭 notice，不进入「快照或错误」二选一结构。

### A32. 批量移除无取消通道

- 来源：bundle_v6_robustness
- 位置：src/zmole/Features/Installers/InstallersViewModel.swift:153
- 优先级：LOW
- 详细判断理由：顺序循环每个 120s 超时，期间 UI 无 Cancel；卡住只能等或退出应用。
- 修复说明：提供批次取消或限制批量并显示进度。

### A33. commandFailed 描述仅含 stderr，stdout 细节丢失

- 来源：bundle_v6_robustness
- 位置：src/zmole/MoleBridge/MoleBridgeError.swift:20
- 优先级：LOW
- 详细判断理由：非 ViewModel 特判路径（如 InstallerInterface:63）只用 stderr，stdout 中的失败原因被丢弃。
- 修复说明：无 stderr 时附带 stdout 截断摘要，或统一使用命令结果摘要。

### A34. 集成脚本 mktemp 失败不退出且工作目录泄漏

- 来源：bundle_v6_robustness, bundle_v7_test_spec
- 位置：tests/integration/uninstall_stream_test.sh:17、installer_interface_test.sh:17
- 优先级：LOW
- 详细判断理由：WORK 为空时 HOME 变 /home 并写入；installer 脚本重复运行持续泄漏临时目录（对照 uninstall 脚本有清理）。
- 修复说明：`WORK="$(mktemp -d)" || exit 1`；加 `trap 'rm -rf "${WORK:-}"' EXIT`。

### A35. 预跑「空闲」判定与 architecture 定义不一致，确认框在屏仍启动只读扫描

- 来源：bundle_v6_robustness
- 位置：src/zmole/Features/Operations/PrewarmService.swift:139
- 优先级：LOW
- 详细判断理由：注入的 provider 不含「正在查看的清理预览」，仅 clean 项被单独拦住，卸载名单/安装包扫描仍会启动。
- 修复说明：把 clean preview/confirmation 状态并入 externalActivityProvider（AppDependencies.swift:697-700）。

### A36. 流式 dry-run 早退分支理论上不释放租约

- 来源：bundle_v6_robustness
- 位置：src/zmole/Features/Clean/CleanViewModel.swift:107
- 优先级：LOW
- 详细判断理由：guard 直接 return 未走 releaseLease；当前状态机使 accepts=false 不可达，但属防御缺口。
- 修复说明：改 defer 释放或先 releaseLease 再 return。

### A37. SIGKILL 定时器不复查进程状态、kill 前仅 isRunning 判定，存在 pid 复用风险

- 来源：bundle_v1_security, bundle_v2_correctness
- 位置：src/zmole/MoleBridge/MoleBridge.swift:353-365
- 优先级：LOW
- 详细判断理由：0.25s 后无条件 kill(-pid, SIGKILL) 且不查 finished/getpgid；判定与 kill 之间 pid 可被复用，窗口极小但命中即误杀。
- 修复说明：kill 前复核 `getpgid(pid) == pid` 且未 finished；SIGKILL 回调先复查 `!finished && process.isRunning` 再执行。

### A38. 「保护」按钮失败/重复时静默，用户以为已加入白名单

- 来源：bundle_v2_correctness, bundle_v6_robustness
- 位置：src/zmole/Features/Clean/CleanView.swift:278-282
- 优先级：LOW
- 详细判断理由：白名单未加载时 addPattern 静默 return、租约被占/写盘失败的错误 CleanView 不渲染；重复路径还会先置「已存在」再被 save 清空并显示已保存。
- 修复说明：addPattern 返回是否插入成功，失败不调用 save 并在 Clean 页回显错误。

### A39. clean 预跑项因预览被推迟后，预览关闭且无新活动时永不重跑

- 来源：bundle_v2_correctness
- 位置：src/zmole/Features/Operations/PrewarmService.swift:164-167
- 优先级：LOW
- 详细判断理由：重排只在 noteActivityChanged 的 !wasIdle 分支；预览关闭后状态已 idle，队列空、poke 无动作。
- 修复说明：活跃预览 deferral 与失败重试分开记账；或 cleanPreviewActiveProvider true→false 时显式重新入队 .cleanDryRun 并 poke。

### A40. 份额百分比文本未钳上限，硬链接场景可显示 >100%

- 来源：bundle_v2_correctness
- 位置：src/zmole/Features/Analyze/AnalyzeView.swift:294
- 优先级：LOW
- 详细判断理由：合计去重但行值各自展示，同层两条 1GB 硬链接各显示 100.0%。
- 修复说明：文本同样 `min(1, share)`，或对 linkKey 行标注「硬链接，合计已去重」。

### A41. 进入不可列目录时清空整个浏览状态

- 来源：bundle_v2_correctness
- 位置：src/zmole/Features/Analyze/AnalyzeViewModel.swift:151-154
- 优先级：LOW
- 详细判断理由：catch 设错误后 level=nil，整页错误态，当前层上下文被抹掉。
- 修复说明：列目录失败时保留上一层 level 只显示错误条。

### A42. installer 忙碌错误被折叠成单项失败，未按可恢复忙碌处理

- 来源：bundle_v2_correctness
- 位置：src/zmole/Features/Installers/InstallerInterface.swift:81-91
- 优先级：LOW
- 详细判断理由：MoleBridgeError.busy 被转成「目标被拒」展示，与同仓 CommandBusy/RecoverableBusyNotice 语义不一致。
- 修复说明：confirmRemoval 循环先判 CommandBusy.isBusy：中止批次、显示 RecoverableBusyNotice、保留选中。

### A43. busy 分支缺会话终止转移，UI 停在「执行中」直到手动取消

- 来源：bundle_v2_correctness
- 位置：src/zmole/Features/Clean/CleanViewModel.swift:273（MaintenanceOperation.swift:145-149、UninstallViewModel.swift:366-369 同）
- 优先级：LOW
- 详细判断理由：busy 时 releaseLease 但 session 仍处 executing/previewing。
- 修复说明：busy 分支补 `session.fail(...)`（或新增 reset 转移）。

### A44. CLI 摘要拼接四处重复、ANSI 剥离两套实现

- 来源：bundle_v2_correctness, bundle_v5_architecture
- 位置：CleanViewModel.swift:321-326、UninstallViewModel.swift:519-524、UninstallSnapshot.swift:214-217、MaintenanceOutput.swift:4；CleanScanStage.swift:59-84 与 MaintenanceOutput.swift:12-30
- 优先级：MEDIUM
- 详细判断理由：同一逻辑多份维护；Uninstall 未复用 stripANSI 导致 clear_screen 转义序列进面板。
- 修复说明：统一调用 MaintenanceOutput.summary；CleanScanStage.stripANSI 合并到 MaintenanceOutput.stripANSI 一处。

### A45. --demo-language/--demo-appearance 不受 --demo 门禁

- 来源：bundle_v3_contract
- 位置：src/zmole/App/AppDependencies.swift:360-361
- 优先级：MEDIUM
- 详细判断理由：dataRoot 有门禁而 language/appearance 无条件生效，非 demo 会话也能覆盖界面语言/外观。
- 修复说明：同样加 `isEnabled ? … : nil`；拒绝 "system" 值防非法 Locale。

### A46. 生产二进制保留 --demo 且 --demo-data-root 接受任意路径

- 来源：bundle_v1_security
- 位置：src/zmole/App/AppDependencies.swift:545-557
- 优先级：LOW
- 详细判断理由：任意路径 createDirectory 并原子覆盖同名文件（clean-list.txt/whitelist/purge_paths）。
- 修复说明：demo 数据根强制落在 temporaryDirectory 下并校验前缀；或将 demo 模式置于 #if DEBUG / 独立 build flag。

### A47. installer JSON 零防御 + 删除参数未经本地形状校验

- 来源：bundle_v1_security, bundle_v3_contract
- 位置：src/zmole/Features/Installers/InstallerInterface.swift:25-28、:76-80
- 优先级：MEDIUM
- 详细判断理由：任一字段缺失整表不可用（对比同仓其他解析器均有防御）；path/size/identity 直接拼 argv 依赖 CLI 兜底。
- 修复说明：source/identity 用 decodeIfPresent 默认、单行失败跳过；remove 前校验 path.hasPrefix("/")、sizeBytes>0、identity 非空，畸形拒绝并提示重扫。

### A48. 桥实例数组按位置映射 lane，无编译期约束

- 来源：bundle_v3_contract, bundle_v5_architecture
- 位置：src/zmole/App/MoleCommandLanes.swift:51-60
- 优先级：MEDIUM
- 详细判断理由：bridges[0..7] 位置赋名，增删 lane 静默错配。
- 修复说明：makeCommandBridges 返回具名结构体，或在 MoleCommandLanes 内集中构造各 lane 桥。

### A49. AboutView 生产路径自建 MoleBridge，且版本失败只显示「—」

- 来源：bundle_v3_contract, bundle_v5_architecture, bundle_v6_robustness
- 位置：src/zmole/Features/Settings/AboutView.swift:32-35
- 优先级：MEDIUM
- 详细判断理由：绕过 AppDependencies 装配（违反 architecture.md:24）；try? 吞错无法区分无捆绑 mole 与命令失败。
- 修复说明：版本改读 BundledMoleInfo.tag()（无需桥）或由 AppDependencies 注入；失败时区分原因显示。

### A50. UninstallListStream 弱类型解析 + 畸形行静默跳过

- 来源：bundle_v3_contract, bundle_v6_robustness
- 位置：src/zmole/Features/Uninstall/UninstallListStream.swift:44-67
- 优先级：LOW
- 详细判断理由：JSONSerialization + [String: Any] 字段名散落，全坏流表现为「没有应用」。
- 修复说明：定义 Codable 行类型统一解码；统计跳过行数，全空/超阈值抛解析错误。

### A51. i18n 缺口族：错误文案硬编码简体中文 + source 过滤无 key

- 来源：bundle_v3_contract, bundle_v5_architecture
- 位置：MoleBridgeError.swift:17、StatusWatchService.swift:41、DiskScanner.swift:88、HistoryViewModel.swift:75、StatusViewModel.swift:102、WhitelistViewModel.swift:72、StatusSnapshot.swift:372、CleanPreview.swift:22、PurgePaths.swift:15、InstallerInterface.swift:98；UninstallView.swift:120
- 优先级：MEDIUM
- 详细判断理由：错误字符串经 localizedDescription 直进 UI detail，en/zh-Hant 界面显示简体中文；source 过滤值 "App"/"Homebrew" 无 xcstrings 条目。
- 修复说明：错误类型改携带 errorKey（同 operation.error.\* 模式），UI 用 LocalizedStringKey 渲染；增加 uninstall.source.app/homebrew 等 key 并显式映射。

### A52. 契约以恒真常量向测试自证

- 来源：bundle_v5_architecture
- 位置：src/zmole/App/NavigationModel.swift:16、:21-23、AppDestination.swift:92
- 优先级：MEDIUM
- 详细判断理由：常量在 src 零运行时读取，仅测试断言，无法捕获真实行为回归。
- 修复说明：删除常量；测试改为对真实 palette/视图数据断言或结构性约束（NavigationTests.swift:52/54/88 相应改造）。

### A53. 四个页面手写页头，未使用共享 MolePageHead

- 来源：bundle_v5_architecture
- 位置：CleanView.swift:49-83、InstallersView.swift:57-80、OptimizeView.swift:50-62、PurgeView.swift:50-62
- 优先级：MEDIUM
- 详细判断理由：字号/颜色重复维护，MolePageHead 已被六页使用。
- 修复说明：四页改用 MolePageHead（subtitle 支持可选）。

### A54. statTile 多处手写，MoleStatTile 几乎闲置

- 来源：bundle_v5_architecture
- 位置：CleanView.swift:94-108、InstallersView.swift:91-102
- 优先级：MEDIUM
- 详细判断理由：字体/内边距/圆角/描边几乎一致，两份私有实现。
- 修复说明：统一使用 MoleStatTile（UtilityUI.swift:74），删除私有实现。

### A55. busyState 两页逐字重复

- 来源：bundle_v5_architecture
- 位置：OptimizeView.swift:170-176、PurgeView.swift:103-109
- 优先级：LOW
- 详细判断理由：ProgressView + 文案 + minHeight 200 完全相同。
- 修复说明：抽共享 busy 视图进 UtilityUI。

### A56. statusFixture 两条通道各复制一份

- 来源：bundle_v5_architecture
- 位置：src/zmole/App/AppDependencies.swift:198、:269
- 优先级：MEDIUM
- 详细判断理由：逐字相同的 fixture 两处维护。
- 修复说明：抽到共享 fixture 函数/类型。

### A57. 装配文件混装约 500 行 Demo 假件

- 来源：bundle_v5_architecture
- 位置：src/zmole/App/AppDependencies.swift:40-500
- 优先级：MEDIUM
- 详细判断理由：文件 727 行，假件随生产装配被动变更。
- 修复说明：Demo 假件与 fixtures 拆到 App/DemoSupport.swift，AppDependencies 只留装配（结合 A55/A56 一并迁移）。

### A58. accent 色板双份定义，依赖手工同步

- 来源：bundle_v5_architecture
- 位置：src/zmole/Features/UtilityUI.swift:6-11
- 优先级：LOW
- 详细判断理由：UtilityStyle.accent 与 MoleTheme.accent/accentStrong 数值手工对应，已在两处同时改色。
- 修复说明：UtilityStyle.accent 直接引用 MoleTheme.accent（色值方向见 A81：蓝色）。

### A59. 内存文本格式化两套实现

- 来源：bundle_v5_architecture
- 位置：StatusChart.swift:77-99、OverviewViewModel.swift:17-25
- 优先级：LOW
- 详细判断理由：used/total→x/y 回退逻辑与私有 bytes 帮助函数重复。
- 修复说明：抽共享 formatter。

### A60. 死代码清理批次（12 条）

- 来源：bundle_v5_architecture
- 位置：见各条
- 优先级：LOW
- 详细判断理由：rg src+tests 交叉验证零引用，删除无行为风险。
- 修复说明：删除 OptimizeSnapshot.swift:3/5 与 PurgeSnapshot.swift:3/5 死类型；UninstallViewModel.swift:229 selectAll；MoleTheme.swift:27/33 未用常量；NavigationModel.swift:82 displayName；OperationSession.swift:31-33 isCancelled/isPartial/isFailure；StatusSnapshot.swift:346 isVirtualOnly/processCollectedAt；StatusWatchService.swift:135 StatusWatchProviding.retry()（含协议方法）。

### A61. 测试专用 API 清理批次（5 条）

- 来源：bundle_v5_architecture
- 位置：见各条
- 优先级：LOW
- 详细判断理由：生产代码中仅测试引用的路径，应删或接入真实入口。
- 修复说明：删除 DestructiveConfirmation.swift:3 DestructiveConfirmationFlow（测试改覆盖真实确认路径）；UninstallViewModel.swift:253 focus(app:)（测试改 path 版）；StatusViewModel.swift:76 refresh（删或接真实入口）；OverviewViewModel.swift:399 refresh/loadEstimate/isLoading（删或合并）；WhitelistViewModel.swift:31 moleProcess（测试改断言 store/coordinator）；同步修改受影响测试。

### A62. 小整理：三 catch 合并、selectedIDs 双名收敛

- 来源：bundle_v5_architecture
- 位置：PrewarmService.swift:175-179、UninstallViewModel.swift:67
- 优先级：LOW
- 详细判断理由：catch 分支体相同；双名并存靠注释维系。
- 修复说明：三 catch 合并为一；保留单一公开名（selectedPaths），视图/测试统一。

### A63. ui_contract 页面契约表「清理」行重复

- 来源：bundle_v3_contract, bundle_v5_architecture, bundle_v8_docs
- 位置：docs/design/ui_contract.md:27、:29
- 优先级：MEDIUM
- 详细判断理由：两行同为清理，第二行多含预跑条款。
- 修复说明：合并为一行，保留含预跑条款的内容。

### A64. blueprint 文档同步批次

- 来源：bundle_v3_contract, bundle_v5_architecture, bundle_v8_docs
- 位置：见各条
- 优先级：MEDIUM
- 详细判断理由：实现已全面落地，blueprint 多处仍是落地前/与实况不符的现在时陈述。
- 修复说明：① domain.md:17 status 词条改为实时 watch 契约（只读、可暂停、离页停止）；② architecture.md:12-14 模块表按实际目录重写（补 Overview/Installers/Settings/Confirmation/Operations，删 Models 空目录声明）；③ conventions.md:15 目录清单按现状（Models 未启用），:30 侧栏图标约定同步为 AppIcon.icns 路径；④ testing.md:9/:21/:32 删除「落地前」残留、改当前门禁描述，:54 关于 StatusStreamTests 的覆盖声明按 A73 补测后修正（或先改写声明）。

### A65. 流程文档批次

- 来源：bundle_v3_contract, bundle_v5_architecture, bundle_v7_test_spec, bundle_v8_docs
- 位置：见各条
- 优先级：MEDIUM
- 详细判断理由：handoff 落后 30+ 提交、plan.md 现在时呈现已实现内容、ADR 替代字段缺失、AGENTS.md 占位符声明过时。
- 修复说明：① handoff.md 更新最新一节（branch: main、当前 head_commit、剩余工作），旧节迁 docs/archive/handoff.md（可经 repo-hygiene）；② plan.md 标注历史快照或迁 archive，README 链接改指 blueprint；③ decisions.md:70 ADR 008「替代」字段填 004；④ AGENTS.md:16 改为「architecture/domain 已填充为项目专属权威」。

### A66. 设计/历史文档批次

- 来源：bundle_v1_security, bundle_v8_docs
- 位置：见各条
- 优先级：MEDIUM
- 详细判断理由：refactor_grilling 多条事实已被实现推翻且含维护者本机路径、demo_design 两文档仍写五模式、d001 行号漂移且克隆已不存在。
- 修复说明：① refactor_grilling.md 文件头加「2026-10-16 决策记录，已被实现取代」标注；修正 :561 失效路径；:560 承诺的 optimize 白名单 ADR 注明不再需要或补录；:5 的 `/Users/karson/...` 本机路径去标识化；② demo_design_notes.md/demo_design_system.md 头部加「已被 ui_contract 侧边栏基线取代」标注；③ d001:12 行号更新为当前捆绑树或改为按符号定位的说明。

### A67. 归档批次

- 来源：bundle_v8_docs
- 位置：见各条
- 优先级：MEDIUM
- 详细判断理由：s001 已关闭未迁档、p001 前提被实现推翻、p004 理由为通用句。
- 修复说明：① s001 经 repo-hygiene 迁 docs/archive/spikes/ 并同步 d001 引用路径；② p001 经 .repo_template/scripts/pending.py 归档或改写为未来增强并复核来源引用；③ p004 按真实阻塞改写理由（经 pending.py 流程）。

### A68. README 批次

- 来源：bundle_v1_security, bundle_v8_docs
- 位置：见各条
- 优先级：LOW
- 详细判断理由：开发命令整段注释标「落地后」而工程已落地；无最低系统要求；xattr 命令缺限定语；暴露维护者本机目录约定。
- 修复说明：① :40-42 改为可执行当前构建步骤（含 xcodegen generate）；② 运行时节补「macOS 13+」；③ :25 xattr 命令加限定语（仅对本项目 App）并首选右键打开；④ :45 本机路径改去标识化描述或上游 URL。

### A69. spike 样本脱敏

- 来源：bundle_v1_security
- 位置：docs/spikes/s001_mole_cli_fixtures/samples/（analyze_json_path.sample.json:2、clean_dry_run.txt:10、history_json.sample.json:3、clean-list.excerpt.txt:13/17、status_json.sample.json:87）
- 优先级：LOW
- 详细判断理由：公开仓样本含 `/Users/karson/...`、私有 temp 路径、真实局域网 IP、代理端口、电池/硬件指纹，可关联去匿名。
- 修复说明：`/Users/karson` 全替换为 `/Users/example`，`/var/folders/...` 替换为 `<TMP>`，IP 换 192.0.2.10（TEST-NET），代理换 127.0.0.1:8080，硬件字段换通用值；替换后保留作为格式契约。

### A70. PurgePaths/Whitelist 写入信任假设未在 blueprint 明示

- 来源：bundle_v1_security
- 位置：src/zmole/Features/Purge/PurgePaths.swift:49-59
- 优先级：LOW
- 详细判断理由：用户输入原样写入 mole 配置，`$()`/反引号/`*` 按 mole 文件语义透传，当前假定 CLI 视为纯数据。
- 修复说明：在 docs/blueprint/architecture.md（或 decisions.md）明示信任假设：配置文件为纯数据、由 CLI 负责引号与展开安全；或对 purge 行增加拒绝 `$`/反引号/控制字符校验。

### A71. demo 概览估算仍读真实 /System 目录列表

- 来源：bundle_v2_correctness
- 位置：src/zmole/App/AppDependencies.swift:684-688
- 优先级：LOW
- 详细判断理由：与 architecture.md:93「demo 注入内存目录源」边界不一致，子项集合随本机变化。
- 修复说明：demo 装配注入固定子项列表（如 ["Library", "Applications", "Volumes"]）。

### A72. 测试加固批次（flaky 与断言方式）

- 来源：bundle_v7_test_spec
- 位置：见各条
- 优先级：MEDIUM
- 详细判断理由：固定 sleep 等待 unstructured Task 慢机 flaky；源码字符串断言等价重构即假红；try? XCTUnwrap 吞错；时间型断言依赖采样间隔。
- 修复说明：① UninstallDetailTests.swift:105 改有界轮询（参照 DiskExplorerTests.swift:363-368）；② DiskExplorerTests.swift:371/UiAlignmentTests.swift:189-241/SettingsHistoryTests.swift:127/CleanPageTests.swift:160/OverviewLayoutTests.swift:128 能抽数据断言的改断言数据，纯视觉保留最小集合并注明只防回归；③ NavigationTests.swift:72 改 try XCTUnwrap（测试改 throws）；④ ZmoleTests.swift:85 改带上限轮询等待 snapshot 非 nil。

### A73. 缺口补测批次

- 来源：bundle_v7_test_spec
- 位置：见各条
- 优先级：MEDIUM
- 详细判断理由：clean 执行闸门内容改写分支、命名卸载 y\\n 真实协议、schema 1→2 迁移、16MB 聚合上限均无测试；testing.md:54 覆盖声明与事实不符。
- 修复说明：① CleanPreviewStoreTests.swift 新增「clean-list.txt 内容改写后 confirmExecution 不 spawn 且报 changed_list」用例；② 新增集成用例：夹具 app 空 stdin 与 y\\n 调真实 uninstall.sh，断言空 stdin 中止；③ OverviewCacheTests 补 schemaVersion:1 条目不被采用用例；④ MoleBridgeTests 补 16MB 超限与 version() 空输出用例；⑤ testing.md:54 声明按补测实况修正。

### A74. AppIconTests 字节级断言 + 工具链依赖未登记

- 来源：bundle_v7_test_spec
- 位置：tests/unit/AppIconTests.swift:46、:30
- 优先级：MEDIUM
- 详细判断理由：字节级 icns 重现随工具链更新易误红；单测 target 依赖 swift/sips/iconutil 未在 doctor_cmd 登记；svg_to_png.swift 曾 untracked（4ed8314 已修复）。
- 修复说明：改为解码级不变量断言（各尺寸存在、512 角透明、行列数），字节一致性降级为发布校验；在 testing.md doctor_cmd 或测试注释登记 bash/swift/sips/iconutil 依赖。

### A75. 捆绑 mole 子进程剥离 MOLE\_\* 环境变量（原 D1，决策 B）

- 来源：bundle_v1_security
- 位置：src/zmole/MoleBridge/MoleBridge.swift:202-213
- 优先级：MEDIUM
- 详细判断理由：GUI 从不设 process.environment，随会话继承全部环境变量；同用户进程可经 `launchctl setenv MOLE_DELETE_MODE=permanent` 等持久化注入，改变之后所有清理/删除行为（生产脚本按 MOLE\_\* 改变行为已有多处证据）。选项权衡：显式最小环境可能破坏 mole 依赖的其他变量，仅剥离 MOLE\_\* 依赖命名空间纪律。
- 用户决策：B —— 仅剥离全部 `MOLE_*` 前缀变量，其余继承
- 修复说明：构造进程环境时过滤全部 `MOLE_` 前缀变量后传入 process.environment，其余环境保持继承；补测试：注入 MOLE\_\* 变量后断言子进程环境不含相应变量。

### A76. 引入 os.Logger 日志设施（原 D2，决策 A）

- 来源：bundle_v6_robustness
- 位置：src/zmole/MoleBridge/MoleBridge.swift:296 及全仓
- 优先级：MEDIUM
- 详细判断理由：rg 证实 src/zmole 无任何 print/os.Logger/NSLog；launchFailed、超时、退出码、stderr 仅进当次 UI 文案，事后不可诊断；与「日志优先、用 logging」约定不符。隐私边界需明确记录范围。
- 用户决策：A —— 引入 os.Logger：MoleBridge 关键路径记录命令名、退出码、耗时、错误类别（不记完整 argv/输出），走系统统一日志
- 修复说明：MoleBridge 关键路径引入 os.Logger（敏感值 `privacy: .private`）；与 A21 的估算/缓存失败记录点合并处理。

### A77. 退出应用清理活跃子进程（原 D3，决策 A）

- 来源：bundle_v6_robustness
- 位置：src/zmole/App/ZmoleApp.swift:11
- 优先级：MEDIUM
- 详细判断理由：退出后 bash+rm 子进程继续运行，破坏性操作可能在 GUI 消失后仍执行。
- 用户决策：A —— applicationWillTerminate 中取消全部活跃 runner，限时等待（如 2s）后放行
- 修复说明：AppDelegate 实现 applicationWillTerminate，向所有活跃 runner 发取消并等待终态，2s 超时后放行退出。

### A78. status watch 坏行容错（原 D4，决策 A）

- 来源：bundle_v6_robustness
- 位置：src/zmole/Features/Status/StatusWatchService.swift:172
- 优先级：MEDIUM
- 详细判断理由：单行抖动/半行即让状态页全面下线、只能手动 retry，容错过弱（terminal 为原有意设计）。
- 用户决策：A —— 坏行计数跳过，连续 N 行（如 3）或比例超阈值才终止
- 修复说明：decode 失败计数并跳过；连续 3 行失败或累计比例超阈值时 streamEnded(.invalidJSON)；与 A5 的 banner 呈现协同。

### A79. 确认视图展示本次预览摘要（原 D5，决策 A）

- 来源：bundle_v3_contract
- 位置：src/zmole/Features/Clean/CleanView.swift:16-21（同 UninstallView:51-56、OptimizeView:16、PurgeView:12）
- 优先级：LOW
- 详细判断理由：契约要求「确认 sheet 使用具体动作名和同代预览」，当前确认视图只传固定文案 key、不含本次预览内容。
- 用户决策：A —— 实现侧：确认视图展示本次预览摘要（对象数/路径样例/影响范围）
- 修复说明：DestructiveConfirmationView 增加预览摘要参数，四页传入本次预览对象数/路径样例；UiAlignmentTests 扩展断言。

### A80. optimize/purge 动作移入页头（原 D6，决策 A）

- 来源：bundle_v3_contract
- 位置：src/zmole/Features/Optimize/OptimizeView.swift:28-44、PurgeView.swift:25-41
- 优先级：LOW
- 详细判断理由：两页把预览/取消放 ToolbarItem，与其余八页及 ui_contract.md:15「页面动作位于页头右侧」不符。
- 用户决策：A —— 实现侧：预览/取消移入页头动作区（与其余页面一致）
- 修复说明：预览/取消从 ToolbarItem 移到页头动作区（MolePageHead 右侧）；UiAlignmentTests 补充两页断言。

### A81. accent 确认改蓝并补决策记录（原 D7，决策 A）

- 来源：bundle_v8_docs
- 位置：docs/design/ui_contract.md:7、src/zmole/App/MoleTheme.swift
- 优先级：HIGH
- 详细判断理由：ui_contract 宣布视觉权威为 demo HTML（绿色 `#2f8f68`），未提交改动已改蓝 `0x0072FF` 且无决策记录。
- 用户决策：A —— 确认改蓝：更新 ui_contract 参考资料声明 + decisions.md 补 ADR
- 修复说明：ui_contract:7 参考资料声明改为「HTML 为布局参考，色彩以应用图标蓝系为准」；decisions.md 新增 ADR（accent 由绿改蓝、跟应用图标）；确认工作区色值定稿（与 A58 协同）。

### A82. 全量补写需求级 spec（原 D8，决策 A）

- 来源：bundle_v7_test_spec, bundle_v8_docs
- 位置：docs/specs_index.md、docs/specs/
- 优先级：MEDIUM
- 详细判断理由：声明「task 收尾时累积 spec」但 39 个 task 全部归档后 spec 从未累积，需求追溯只能依赖归档 task 目录。
- 用户决策：A —— 补写已完成需求的 spec 并填索引（全量追溯）
- 修复说明：按已归档 task（t001–t039）梳理已交付行为，为每项生效需求补 docs/specs/<slug>.md 并填 docs/specs_index.md；工作量大，建议独立 task 分批执行（先索引草案后逐项成文）。

### A83. 截图入库并更新验收状态行（原 D9，决策 A）

- 来源：bundle_v7_test_spec, bundle_v8_docs
- 位置：tests/e2e/、docs/design/ui_contract.md:3、docs/blueprint/testing.md:36-45
- 优先级：LOW
- 详细判断理由：契约要求视觉证据但仓库无任何截图；状态行「进行中，尚未通过视觉验收」与 task 关闭实况需复核。
- 用户决策：A —— 截图入库（如 docs/guides 或 docs/reviews）+ 按实况更新 ui_contract:3 状态行
- 修复说明：运行实际 App 截取十页界面入库（注明版本/日期）；ui_contract:3 状态行按实况更新；testing.md 注明视觉证据存放位置。

### A84. optimize 行状态保守展示（原 D10，决策 B）

- 来源：bundle_v3_contract
- 位置：src/zmole/Features/Optimize/OptimizePlan.swift:20-27
- 优先级：MEDIUM
- 详细判断理由：英文关键词启发式在 mole 措辞/本地化变化时会误标永久删除或 skipped。
- 用户决策：B —— 保守展示：无法识别时附原文并标注「未知」，不猜状态
- 修复说明：无法识别时不再推断状态，附原文并标注「未知」；保留已识别的永久删除标记；上游结构化输出另登记 pending 作为长期方向。

### A85. 租约+预览世代样板收敛为共享实现（原 D11，决策 A）

- 来源：bundle_v5_architecture
- 位置：src/zmole/Features/Operations/OperationSession.swift:36（CleanViewModel:301-319、UninstallViewModel:480-506、MaintenanceOperation:242-258）
- 优先级：MEDIUM
- 详细判断理由：三份逐字重复，A43 同类缺陷三处同缺——收敛后一处修复全生效；触及三个核心 VM，风险中等。
- 用户决策：A —— 收敛为共享 PreviewLeaseCoordinator/基类
- 修复说明：抽共享 PreviewLeaseCoordinator/基类收拢 isCurrentPreview/releaseLease/operationID/过期订阅；三个 VM 迁移；以 CommandConcurrencyTests/RecoverableBusyTests 回归。

## 不采纳项

### R1. 卸载失败文案 "nothing was removed" 命中成功词表被判「部分完成」

- 来源：bundle_v3_contract（交叉验证 CHALLENGED）
- 位置：src/zmole/Features/Uninstall/UninstallSnapshot.swift:220
- 优先级：HIGH
- 详细判断理由：交叉证伪已推翻：该文案尾无空格不命中 "removed " 词表；direct-name 分支退码 0 实际落 .unknown 而非 .partial。原断言（零操作被标部分完成）不成立。

### R2. AppLinks 字面量 URL 强制解包

- 来源：bundle_v2_correctness
- 位置：src/zmole/App/AppLinks.swift:4
- 优先级：LOW
- 详细判断理由：常量格式固定不会失败；报告自身建议保留，仅作模式记录。

### R3. Analyze 目录遍历单线程递归

- 来源：bundle_v4_performance
- 位置：src/zmole/Features/Analyze/DiskScanner.swift:228
- 优先级：LOW
- 详细判断理由：报告自认当前可接受；A19 已覆盖取消点与并发议题，单独改遍历并发收益不明且风险高于收益。

### R4. 配置类文件在主线程同步读

- 来源：bundle_v4_performance
- 位置：src/zmole/Features/Whitelist/WhitelistViewModel.swift:55 等
- 优先级：LOW
- 详细判断理由：文件均为 KB 级，报告自认影响小；A11 已处理 MB 级 clean-list 的大头。

### R5. CleanPreviewSnapshot 同时保留原始全文与解析两份表示

- 来源：bundle_v4_performance
- 位置：src/zmole/Features/Clean/CleanPreview.swift:41
- 优先级：LOW
- 详细判断理由：确认执行需要 contents 摘要，去重会触及快照语义，收益低于风险；量级可控。

### R6. PrewarmService 直接耦合四个 Feature 类型

- 来源：bundle_v5_architecture
- 位置：src/zmole/Features/Operations/PrewarmService.swift:42-46
- 优先级：INFO
- 详细判断理由：报告自认可接受；预跑协调者放 Operations 是合理职责归属，协议化收敛无当前收益。

### R7. MoleProcessRunner 单类锁状态机约 15 个布尔

- 来源：bundle_v5_architecture
- 位置：src/zmole/MoleBridge/MoleBridge.swift:160
- 优先级：INFO
- 详细判断理由：报告建议不改行为前提下抽读取器，但该文件是全项目最敏感区域（A1/A7/A37 都在此），额外重构放大回归面；无实际问题证据支撑。

### R8. 每次写操作成功后整个预跑队列全部重跑

- 来源：bundle_v4_performance
- 位置：src/zmole/Features/Operations/PrewarmService.swift:156
- 优先级：INFO
- 详细判断理由：架构文档明示的资源换响应速度权衡，按项失效优化无明确收益。

### R9. status --watch 流无超时，卡死 helper 会挂着

- 来源：bundle_v4_performance
- 位置：src/zmole/Features/Status/StatusWatchService.swift:149
- 优先级：INFO
- 详细判断理由：报告标为「可选」；进程离页 stop 时回收，静默检测属增强而非缺陷。

### R10. --demo-page 未知值静默回落到 overview

- 来源：bundle_v3_contract
- 位置：src/zmole/App/AppDestination.swift:72
- 优先级：INFO
- 详细判断理由：demo 专用调试参数，拼错无实际危害；报告自认可保留现状。

### R11. DiskSplitLayout 留在视图文件与同类几何类型落点不一致

- 来源：bundle_v5_architecture
- 位置：src/zmole/Features/Analyze/AnalyzeView.swift:4-20
- 优先级：INFO
- 详细判断理由：纯风格偏好无对错，无约定强制；移动文件收益为零。

### R12. build_app_icon.sh 引用未入库的 svg_to_png.swift

- 来源：bundle_v3_contract
- 位置：scripts/build_app_icon.sh:36
- 优先级：LOW
- 详细判断理由：4ed8314 已修复（文件已入库）；保留供追溯。

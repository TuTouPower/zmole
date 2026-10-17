# 架构

## 目标

macOS 原生窗口 App（zmole）：把开源 CLI [mole](https://github.com/tw93/mole) 的可脚本化能力做成 GUI。清理语义仍由捆绑的 mole 执行；本仓不重写清理引擎，不解析 TUI 帧。

## 模块划分

|模块|职责|边界|
|---|---|---|
|`App`|窗口、侧边栏十页导航、本地化、设置、依赖装配|不直接 `Process`|
|`Features/*`|Overview / Status / History / Analyze / Clean / Uninstall / Optimize / Purge / Installers / Whitelist / Settings / Confirmation / Operations|用户意图 → Bridge API + UI 状态|
|`MoleBridge`|定位 bundle 内 mole、拼参数、跑 `Process`、读 stdout/stderr、解析退出码与 JSON|唯一允许 spawn mole 的层|
|`Models`|预留共享值类型落点（当前为空目录）；命令结果、清理条目、白名单行等值类型按 Feature 就近存放|与 UI 解耦|

侧边栏主导航为十个目的地：概览、清理、卸载、磁盘、优化、状态、项目清理、安装包、历史、设置。设置从系统菜单升为正式页面，系统菜单的设置命令选中该页。⌘K 命令面板只做页面跳转，不承载删除或执行动作。自定义窗口壳只替换导航；各页面继续呈现既有功能，破坏性语义留在各自的页面 task。优化与项目清理是两个独立页面：任务/产物行只读，计划来自本次 dry-run，执行范围由 mole 决定；两者的删除保持永久删除，白名单与扫描目录分别在设置与项目清理页编辑。

安装包不使用上游全屏菜单：捆绑 installer 增加非交互接口 `--list-json`（列出绝对路径、字节大小、来源、身份）与 `--remove <path> --size <n> --identity <id>`（只接受调用方会话名单里的路径；直接核对目标自身——仍在扫描根内、该深度、候选扩展名，且大小与身份未变——`MOLE_DELETE_MODE=trash` 移入废纸篓，失败保留原文件）。删除不重新遍历扫描根（t029）；扫描规则仍由捆绑脚本负责，界面（t023）只消费该接口。

设置页字段：界面语言（跟随系统/简中/繁中/英文）与外观（跟随系统/浅色/深色）经 `@AppStorage` 持久化并即时生效；设置页底色统一使用 `MoleTheme.background`；长列表与输出页面（安装包、优化、项目清理、历史）统一按可用视口布局，页头与操作区常驻可见视口，列表或输出作为独立滚动所有者；侧边栏品牌区仅保留 App 名称，导航按钮禁用系统蓝色焦点框并采用主题轮廓焦点样式；登录项用 `SMAppService` 注册/取消，失败时开关保持关闭并显示原因；项目扫描目录复用项目清理的 `purge_paths` 编辑器；两份白名单——clean（路径）与 optimize（任务 id）——分别编辑 `~/.config/mole/whitelist` 与 `~/.config/mole/whitelist_optimize`，保存成功后使清理结果失效；CLI 行显示捆绑 `SOURCE_VERSION` 的 tag 与 bundle 内路径，不探测系统 `mo`；关于见设置与侧边栏底部。不做菜单栏常驻，关闭最后一个窗口即退出进程。

## App 装配与共享协调

`AppDependencies` 是 App 生命周期所有者，统一创建共享 `MoleBridge`、`OperationCoordinator`、四类写入 ViewModel、白名单编辑器与只读查询/状态 ViewModel。页面只接收已装配依赖，不在 View 内创建生产 Bridge。

`OperationCoordinator` 为 clean、uninstall、optimize、purge、protectionRules 提供跨页面/窗口的单写入 lease；保存保护规则成功后递增 invalidation generation，使受影响 clean 结果失效。ViewModel 释放 lease 后才允许下一项写入。三个写入 ViewModel（clean、uninstall、optimize/purge）共享 `PreviewLeaseCoordinator`：由它持有 lease、跟踪当前结果所属的 generation、并经失效信号回调让页面过期结果；各页面不再各自维护租约与世代样板。

## 数据流

```
用户操作 → Feature → MoleBridge.run(argv)
                      → Process(<bundle>/Contents/Resources/mole/mole …)
                      → stdout / stderr / exitCode
                      → Model → UI
```

- 破坏性命令：后台扫描结果就绪 → 界面确认（对象与结果一致）→ 再 spawn 执行。扫描失败、取消、目标变化后禁止执行。确认前不创建**执行**用 `Process`（后台扫描 spawn 允许）。
- `clean --dry-run` 的 `~/.config/mole/clean-list.txt` 是扫描写出的清单；后台扫描结果连同 `capturedAt` 落入应用支持目录缓存。UI 展示缓存结果并说明执行时 mole 会重扫。用户执行开始前会取消后台 clean 扫描并等待其进程完全退出，避免两侧并发写同一文件。
- 白名单：读写 `~/.config/mole/whitelist`（及 optimize 对应文件），不跑 whitelist TUI。
- App 设置（语言覆盖等）存本应用容器；mole 配置仍在 `~/.config/mole/`。
- mole 配置文件（`purge_paths`、`whitelist`、`whitelist_optimize`）在本仓视为纯数据：GUI 逐行校验形状后原样写入，由 mole 负责解释与展开安全；GUI 不做 shell 转义（也不按 shell 求值）。

### 卸载确认协议

命名卸载（`uninstall <name> [--dry-run]`）会先打印 `Proceed with uninstallation? [y/N]` 并 `read -r`。空 stdin 导致中止。允许 MoleBridge **只**向 stdin 写入 `y\n`（mole 自己的行确认）；随后 batch 的 `read -n1` 遇 EOF 视为 Enter。禁止 PTY、方向键、解析 TUI 帧。

身份：list 的主键是 `path` + `bundle_id`。仅当 `uninstall_name` 在当前 list 中唯一对应那一行时才把它传给 CLI。同名不同 path、path 消失或重新匹配落到别的 path：拒绝执行。

### 进程生命周期

MoleBridge 对每个功能页最多一个 in-flight mole 进程。第二次提交须失败或排队（第一版：拒绝并保持忙碌）。`cancel` 结束该进程组。超时同上。终态：成功 / 失败（非零或无法解析）/ 取消；把 stdout/stderr 摘要交给 UI。切走页面不自动再开一个进程。写端管道忽略 SIGPIPE（fd 级 `F_SETNOSIGPIPE`），SIGTERM→SIGKILL 前复核进程组身份（`getpgid(pid) == pid`）；应用退出时由 AppDelegate 取消全部活跃 runner，限时等待 2 秒。子进程环境在启动时剥离全部 `MOLE_*` 变量，其余继承。

`MoleBridge` 每个实例只允许一个 active runner。App 装配按命令类型分通道（`MoleCommandLanes`）：每个一次性消费者（history、uninstall、installer、clean 执行、optimize、purge、概览估算）各持独立 `MoleBridge`，互不阻塞；概览估算持 3 条通道以并发探测多个目录（单通道内串行）；卸载名单流与后台扫描各持独立实例（后台五类扫描每种一条通道，可并行）；`status --watch` 与 `clean --dry-run` 流各持独立实例。写入命令之间仍由 `OperationCoordinator` 单一租约互斥，与通道数量无关。磁盘页不占通道：它在应用内只读扫描（见下节）。

### 卸载名单与确认

卸载名单与安装包名单由 `BackgroundScanService` 作为唯一所有者管理。卸载走 `uninstall --list-stream`：流式输出先产生身份行、随后补齐属性行，扫描服务以最长 100 ms 聚合渐进发布进度，流停止时 100 ms 内交付尾批。元数据 worker 受父命令统一登记、并发管理与取消（非发布 worker 关闭继承的名单管道写端，stdin 为 `/dev/null`；父命令退出或取消时全部 worker 退出，不产生后台 disown 任务）。名单扫描父级建立只读 Homebrew cask 索引，单次获取 installed 快照与 Caskroom 映射，真实路径或文件身份（`-ef`）所有权明确时直接认领且不调 `brew info`，仅多候选项做定向核验，全快路径时 Caskroom 遍历为 0。页面仅作为订阅者消费进度，移除独立扫描通道；名单未成功完成前禁止确认执行。同一次会话的确认复用已完成的稳定名单：确认前只做轻量身份核对（路径存在、bundle id 未变），不重跑全量大小扫描；身份变化时拒绝执行、不 spawn 卸载命令，并重新请求扫描名单。「检查关联文件」仍只在用户点击时对该应用跑一次 `uninstall --dry-run`。页面离页仅解除订阅，不影响底层共享任务。

### 后台扫描

`BackgroundScanService` 在应用运行期间并行执行五个只读扫描：卸载名单、安装包名单、`clean --dry-run`、`optimize --dry-run`、`purge --dry-run`；每项一条独立命令通道，互不阻塞，不获取写入租约。唯一互斥是 clean：用户 clean 执行会取消并等待后台 clean 进程完全退出且 clean-list.txt 读取解析任务完全退出释放所有权；写入租约持有期间 clean 不启动，租约释放后补跑。服务拥有显式 hydration 状态，由串行存储所有者 `BackgroundScanStorage`（actor，完全离开 MainActor 进行文件 I/O 与 JSON 编解码）在后台异步加载缓存；加载与新扫描结果基于版本号合并，迟到加载不能覆盖较新结果，不发布成功空缓存造成页面闪空。普通扫描结果采用 100 ms 尾沿合并（持续更新时每 500 ms 强制推进一次水位落盘），失效版本作为高优先级立即串行写入；原子写失败保留上一完整文件与待写快照并标记错误可重试。结果持久化到 `~/Library/Application Support/zmole/background_scan_cache.json`（Schema 2）；schema 不匹配或损坏时整文件忽略并按无缓存安全恢复。写入成功后按数据影响集合精准使受影响结果失效并重扫。单项失败保留上次成功结果并标记失败状态，其他项继续；无结果的失败最多每小时重试一次。页面打开时若有结果直接显示并标出扫描时间；手动刷新复用进行中的同类扫描。无 FDA 时安装包名单项不跑（会遍历 Desktop/Documents/Downloads），授权后补跑。demo 模式不启动后台扫描。

### 重扫描资源准入与调度

应用装配唯一重扫描调度器 `HeavyScanScheduler`，纳管五类后台任务、概览目录估算探测与磁盘测量子树遍历的并发名额准入与完整生命周期计账（生产默认名额为 3，防饥饿界限为 3）。当前页面可见需求提升优先级，切页后撤回提升，已运行任务不被抢占；后台任务达到防饥饿界限后获得下一可用位。通道可用性作为准入前提，不占名额等通道亦不占通道等名额；status watch、轻量卷容量查询、目录首层有界列出与缓存 I/O 不占重扫描名额。任务取消等待底层所有子任务与 worker 退出后释放名额。

## 捆绑与进程边界

- 钉死版本的 mole 安装树放在 `Contents/Resources/mole/`，入口为 `Contents/Resources/mole/mole`，Go helper 为 `Contents/Resources/mole/bin/analyze-go` 与 `Contents/Resources/mole/bin/status-go`。入口用绝对路径，**不**搜 PATH、**不**调用 brew `mo`、**不**把命令装进 `/usr/local/bin`。
- **捆绑组合**：Bash 安装树与 Go 辅助程序都来自同一上游 tag **`V1.55.0`（`69ab325d`）**，不用研究用克隆的 `main`。Go helper 用该 tag 的 `analyze-darwin-arm64`/`amd64` 与 `status-darwin-*`，装入 `bin/analyze-go`、`bin/status-go`（lipo 成 Universal，或 bundle 内按 arch 各一份且运行时选对）。主程序与 helper **均须** arm64+x86_64，禁止只打本机 arch。
- 对应源码不进 Release zip；README / Release 写明上述 tag。
- 禁止在 GUI 暴露捆绑副本的 `update` / `remove`。
- 不给 `Process` 挂 TTY、不解析 ANSI 画面。禁止代发方向键等 TUI 按键；卸载的 `y\n` 见上节。
- 无 TTY 时 mole 的 sudo 走 `osascript`（标题可能仍是 Mole）。本仓不自造 sudo。
- 首版非沙盒；本地用自签证书 `Zmole Local Signing` 签名（`scripts/setup_signing_identity.sh` 一次性建入登录钥匙串）。代码身份跨重建稳定，TCC 授权与 FDA 不会因重新打包失效；不公证。
- 无完全磁盘访问权限（FDA）时，跳过会遍历 Desktop/Documents/Downloads 的扫描（概览 `/Users` 段、安装包名单与安装包预跑），页面以权限横幅引导授权；授权后回到页面自动全量重扫/补跑。FDA 探测读系统 TCC 数据库，不读内容、不触发系统弹窗。
- 与商业版 Mole for Mac（mole.fit）无关。

## 状态流

`StatusWatchService` 以单个 `mole status --watch --interval 1s` 流为源，按订阅者 fan-out `StatusWatchUpdate`，维护有界趋势序列。全局 `StatusFeaturePolicy` 控制监控功能启用状态：停用时拒绝所有 start/retry/resample 请求，立即终止底层 watch 进程并清除数据快照；侧边栏与命令面板隐藏状态页入口，当前状态页转到概览。重新开启时按当前可见页面按需单次启动。StatusViewModel 负责页面生命周期；离页或无订阅者时停止流。首帧慢字段缺失、磁盘 I/O 首次基线和陈旧进程数据均以显式状态展示，不把初始化零值伪装成真实速率。

## 概览与磁盘估算

概览复用共享 `StatusViewModel` 的采样：健康分、CPU、内存、可用磁盘、进程趋势都来自同一 `status --watch` 流。状态功能停用时，采样指标显示明确「已停用」，不继续显示旧值。概览磁盘容量使用独立的轻量卷容量查询（`VolumeCapacityProviding`），不依赖 `status-go`；状态停用时磁盘容量与目录估算仍可正常刷新。概览与状态页可见时 watch 运行，导航到其它目的地时停止（由窗口壳按目的地统一 start/stop）。

磁盘五段为估算，`mole status` 只给总量/已用/可用，没有分类。`StorageEstimateLoader` 用 `analyze` 目录求和：应用程序 `/Applications`、开发者 `~/Library/Developer`、用户数据 `/Users` 减去开发者；系统段按 `/System` 顶层目录子项逐个 `analyze` 并求和，跳过 `/System/Volumes`（数据卷与快照 1.4 TB 不参与扫描，也不计入系统段），任一子项读取失败该段即视为不可用；其他 = status 已用减去前四段且不小于 0。各探测经 3 条独立估算通道并发执行（单通道内串行，平均分摊）。任一输入缺失该段为空占位，不填演示常量。界面标明“估算”。

估算结果缓存四个目录字节和于 App 容器 `~/Library/Application Support/zmole/storage_estimate.json`（含 `schemaVersion`/`capturedAt`）。概览进入即先用缓存即时渲染并启动目录扫描（“其他”用实时 status 已用现算；status 迟到只更新“其他”，不影响扫描与已有分段）。触发点为：概览出现、写入失效信号、已用空间由无到有（仅重派生展示，不重扫）。完成的扫描（含部分）即展示并落盘；缺失段保持占位并保留「估算不完整」标记，随后自动补扫一次且只探测缺失段；写入失效落在扫描在飞期间时，即使该次扫描完整结束也保留失效状态并自动补排一次全量重扫；无 FDA 时 `/Users` 段整段跳过、不留补扫（授权事件到来再全量重扫）；扫描任务由 ViewModel 持有，不随视图消失取消。缓存超过 TTL（6 小时）或收到写入失效信号时全量重算并回写；超过最大年龄（7 天）或 schema 不符即作废。扫描被取消（应用退出）时不落盘。估算通道单条命令超时 600 秒。不提供手动计算按钮。

最近操作复用 `history --json`。概览不再绘制趋势条；状态页的系统负载图在采样点不足时显示等待说明，不伪造趋势。

## 磁盘页扫描

磁盘页不调用 mole：生产扫描根是 `/`，底层由统一测量会话服务 `DiskMeasurementSession` 持有排队、在途任务、扫描世代与结果事实，`AnalyzeViewModel` 仅负责页面浏览与交互展示。扫描使用 `LiveDiskScanner` 只读遍历（`lstat`）。文件大小取 `st_blocks × 512`；符号链接只计链接自身；同一统计范围内的硬链接只计一次（兄弟目录间共享 inode 按规范化路径排序确定归属，不随 worker 完成先后改变；独立目录自身合计与父范围去重贡献分别命名和独立计入）；与父目录设备号不同的子目录标记为 `.otherDevice` 不计入父合计，进入后单独计算。进入正在测量的祖先目录下的子目录时复用祖先在途遍历，不重复扫描；祖先完成后通知全部消费者并推送到最新终态。会话队列保持消费，退出、补位与取消由同一状态所有者串行仲裁；「重新分析」推进世代并取消旧请求，迟到结果不污染新世代。会话共享全局内存驻留预算（生产默认 4000 条目），超出预算的目录及 inode 索引由临时数据库 `DiskSessionStore` 外存化，内存仅保留工作集，按需分页并支持带背压的分批发布；临时空间超限或写入失败保留上一完整快照且不认证部分合计为最终值；会话取消与关闭后释放句柄并清理临时文件。demo 模式注入内存目录源，不读真实文件系统。概览五段估算仍走 `analyze`，与本路径无关。

## Demo 装配边界

`--demo` 使用相同生产 Views/ViewModels，但注入内存 fake process/streaming，禁止解析或 spawn 捆绑 mole。`--demo-page`、`--demo-state`、`--demo-language`、`--demo-appearance` 固定验收状态且仅在 `--demo` 下生效；`--demo-data-root` 只接受用户临时目录内的路径（越界值忽略并回退随机 scratch 目录），将 clean-list 与 whitelist 写入该目录，不触碰 `~/.config/mole/`。demo 假件、fixture 与 `DemoConfiguration` 集中在 `App/DemoSupport.swift`；`AppDependencies.swift` 只保留生产装配与装配辅助（`MoleProcessBox`、unavailable 通道）。

## 与上游关系

- 上游 CLI：<https://github.com/tw93/mole>
- 本机研究用克隆：`~/kar/github_repo/mole`（只读对照；不从此路径打进 Release）
- 商标：公开发布不用 “Mole” 名称与官方 logo

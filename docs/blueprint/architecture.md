# 架构

## 目标

macOS 原生窗口 App（zmole）：把开源 CLI [mole](https://github.com/tw93/mole) 的可脚本化能力做成 GUI。清理语义仍由捆绑的 mole 执行；本仓不重写清理引擎，不解析 TUI 帧。

## 模块划分

|模块|职责|边界|
|---|---|---|
|`App`|窗口、侧边栏十页导航、本地化、设置、依赖装配|不直接 `Process`|
|`Features/*`|Overview / Status / History / Analyze / Clean / Uninstall / Optimize / Purge / Installers / Whitelist / Settings / Confirmation / Operations|用户意图 → Bridge API + UI 状态|
|`MoleBridge`|定位 bundle 内 mole、拼参数、跑 `Process`、读 stdout/stderr、解析退出码与 JSON|唯一允许 spawn mole 的层|
|`Models`|预留共享值类型落点（当前为空目录）；命令结果、预览条目、白名单行等值类型按 Feature 就近存放|与 UI 解耦|

侧边栏主导航为十个目的地：概览、清理、卸载、磁盘、优化、状态、项目清理、安装包、历史、设置。设置从系统菜单升为正式页面，系统菜单的设置命令选中该页。⌘K 命令面板只做页面跳转，不承载删除或执行动作。自定义窗口壳只替换导航；各页面继续呈现既有功能，破坏性语义留在各自的页面 task。优化与项目清理是两个独立页面：任务/产物行只读，计划来自本次 dry-run，执行范围由 mole 决定；两者的删除保持永久删除，白名单与扫描目录分别在设置与项目清理页编辑。

安装包不使用上游全屏菜单：捆绑 installer 增加非交互接口 `--list-json`（列出绝对路径、字节大小、来源、身份）与 `--remove <path> --size <n> --identity <id>`（只接受调用方会话名单里的路径；直接核对目标自身——仍在扫描根内、该深度、候选扩展名，且大小与身份未变——`MOLE_DELETE_MODE=trash` 移入废纸篓，失败保留原文件）。删除不重新遍历扫描根（t029）；扫描规则仍由捆绑脚本负责，界面（t023）只消费该接口。

设置页字段：界面语言（跟随系统/简中/繁中/英文）与外观（跟随系统/浅色/深色）经 `@AppStorage` 持久化并即时生效；登录项用 `SMAppService` 注册/取消，失败时开关保持关闭并显示原因；项目扫描目录复用项目清理的 `purge_paths` 编辑器；两份白名单——clean（路径）与 optimize（任务 id）——分别编辑 `~/.config/mole/whitelist` 与 `~/.config/mole/whitelist_optimize`，保存成功后使清理预览失效；CLI 行显示捆绑 `SOURCE_VERSION` 的 tag 与 bundle 内路径，不探测系统 `mo`；关于见设置与侧边栏底部。不做菜单栏常驻，关闭最后一个窗口即退出进程。

## App 装配与共享协调

`AppDependencies` 是 App 生命周期所有者，统一创建共享 `MoleBridge`、`OperationCoordinator`、四类写入 ViewModel、白名单编辑器与只读查询/状态 ViewModel。页面只接收已装配依赖，不在 View 内创建生产 Bridge。

`OperationCoordinator` 为 clean、uninstall、optimize、purge、protectionRules 提供跨页面/窗口的单写入 lease；保存保护规则成功后递增 preview generation，使受影响 clean 预览失效。ViewModel 释放 lease 后才允许下一项写入。

## 数据流

```
用户操作 → Feature → MoleBridge.run(argv)
                      → Process(<bundle>/Contents/Resources/mole/mole …)
                      → stdout / stderr / exitCode
                      → Model → UI
```

- 破坏性命令：本次预览成功 → 界面确认（对象与预览一致）→ 再 spawn 执行。预览失败、取消、目标变化后禁止执行。确认前不创建**执行**用 `Process`（预览 spawn 允许）。
- `clean --dry-run` 的 `~/.config/mole/clean-list.txt` 是预览快照，执行时 mole 会重扫；UI 须写明。只展示**本次** dry-run 写入的内容，禁止沿用旧文件。用户预览开始前会等待被取消的预跑进程完全退出，避免两侧并发写同一文件。
- 白名单：读写 `~/.config/mole/whitelist`（及 optimize 对应文件），不跑 whitelist TUI。
- App 设置（语言覆盖等）存本应用容器；mole 配置仍在 `~/.config/mole/`。
- mole 配置文件（`purge_paths`、`whitelist`、`whitelist_optimize`）在本仓视为纯数据：GUI 逐行校验形状后原样写入，由 mole 负责解释与展开安全；GUI 不做 shell 转义（也不按 shell 求值）。

### 卸载确认协议

命名卸载（`uninstall <name> [--dry-run]`）会先打印 `Proceed with uninstallation? [y/N]` 并 `read -r`。空 stdin 导致中止。允许 MoleBridge **只**向 stdin 写入 `y\n`（mole 自己的行确认）；随后 batch 的 `read -n1` 遇 EOF 视为 Enter。禁止 PTY、方向键、解析 TUI 帧。

身份：list 的主键是 `path` + `bundle_id`。仅当 `uninstall_name` 在当前 list 中唯一对应那一行时才把它传给 CLI。同名不同 path、path 消失或重新匹配落到别的 path：拒绝执行。

### 进程生命周期

MoleBridge 对每个功能页最多一个 in-flight mole 进程。第二次提交须失败或排队（第一版：拒绝并保持忙碌）。`cancel` 结束该进程组。超时同上。终态：成功 / 失败（非零或无法解析）/ 取消；把 stdout/stderr 摘要交给 UI。切走页面不自动再开一个进程。写端管道忽略 SIGPIPE（fd 级 `F_SETNOSIGPIPE`），SIGTERM→SIGKILL 前复核进程组身份（`getpgid(pid) == pid`）；应用退出时由 AppDelegate 取消全部活跃 runner，限时等待 2 秒。子进程环境在启动时剥离全部 `MOLE_*` 变量，其余继承。

`MoleBridge` 每个实例只允许一个 active runner。App 装配按命令类型分通道（`MoleCommandLanes`）：每个一次性消费者（history、uninstall、installer、clean 执行、optimize、purge、概览估算）各持独立 `MoleBridge`，互不阻塞；概览估算持 3 条通道以并发探测多个目录（单通道内串行）；卸载名单流与空闲预跑各持独立实例；`status --watch` 与 `clean --dry-run` 流各持独立实例。写入命令之间仍由 `OperationCoordinator` 单一租约互斥，与通道数量无关。磁盘页不占通道：它在应用内只读扫描（见下节）。

### 卸载名单与确认

卸载名单走 `uninstall --list-stream`：先输出已发现的应用身份（名称/路径），再按应用输出完整行（bundle id、卸载名、来源、大小、版本、上次使用时间来自同一次扫描；版本读目标自身 Info.plist，不用 Spotlight）。界面先列名单、大小随后补上，尚无大小的行不显示为 0；图标在列表可交互后异步补上。同一次会话的预览与确认复用这份名单：确认前只做轻量身份核对（路径存在、bundle id 未变），不重跑全量大小扫描；身份变化时拒绝执行、不 spawn 卸载命令，并重新扫描名单。「检查关联文件」仍只在用户点击时对该应用跑一次 `uninstall --dry-run`。

### 空闲预跑

`PrewarmService` 在空闲时按固定顺序各跑一次只读扫描：卸载名单、安装包名单、`clean --dry-run`、`optimize --dry-run`、`purge --dry-run`；任意时刻只有一个在跑，不获取写入租约。空闲 = 无写入租约、无用户可见的页面扫描（含磁盘页扫描与正在查看的清理预览）。写入开始取消当前预跑；写入成功后作废全部预跑结果，回到空闲再跑一遍。用户重新扫描某一项会取消当前预跑并把该项交给用户扫描。失败的项跳过继续、下一次空闲重试。页面打开时若有对应预跑结果则直接显示并标出扫描时间，不立刻重扫；确认框开着时新结果不替换正在确认的一份。demo 模式不启动预跑。

## 捆绑与进程边界

- 钉死版本的 mole 安装树放在 `Contents/Resources/mole/`，入口为 `Contents/Resources/mole/mole`，Go helper 为 `Contents/Resources/mole/bin/analyze-go` 与 `Contents/Resources/mole/bin/status-go`。入口用绝对路径，**不**搜 PATH、**不**调用 brew `mo`、**不**把命令装进 `/usr/local/bin`。
- **捆绑组合**：Bash 安装树与 Go 辅助程序都来自同一上游 tag **`V1.55.0`（`69ab325d`）**，不用研究用克隆的 `main`。Go helper 用该 tag 的 `analyze-darwin-arm64`/`amd64` 与 `status-darwin-*`，装入 `bin/analyze-go`、`bin/status-go`（lipo 成 Universal，或 bundle 内按 arch 各一份且运行时选对）。主程序与 helper **均须** arm64+x86_64，禁止只打本机 arch。
- 对应源码不进 Release zip；README / Release 写明上述 tag。
- 禁止在 GUI 暴露捆绑副本的 `update` / `remove`。
- 不给 `Process` 挂 TTY、不解析 ANSI 画面。禁止代发方向键等 TUI 按键；卸载的 `y\n` 见上节。
- 无 TTY 时 mole 的 sudo 走 `osascript`（标题可能仍是 Mole）。本仓不自造 sudo。
- 首版非沙盒；ad-hoc 签名便于本机 TCC。不公证。
- 与商业版 Mole for Mac（mole.fit）无关。

## 状态流

`StatusWatchService` 以单个 `mole status --watch --interval 1s` 流为源，按订阅者 fan-out `StatusWatchUpdate`，维护有界趋势序列。StatusViewModel 负责 start/pause/stop/retry 与页面生命周期；离页或无订阅者时停止流。首帧慢字段缺失、磁盘 I/O 首次基线和陈旧进程数据均以显式状态展示，不把初始化零值伪装成真实速率。

## 概览与磁盘估算

概览复用共享 `StatusViewModel` 的采样：健康分、CPU、内存、可用磁盘、进程趋势都来自同一 `status --watch` 流。概览与状态页可见时 watch 运行，导航到其它目的地时停止（由窗口壳按目的地统一 start/stop）。

磁盘五段为估算，`mole status` 只给总量/已用/可用，没有分类。`StorageEstimateLoader` 用 `analyze` 目录求和：应用程序 `/Applications`、开发者 `~/Library/Developer`、用户数据 `/Users` 减去开发者；系统段按 `/System` 顶层目录子项逐个 `analyze` 并求和，跳过 `/System/Volumes`（数据卷与快照 1.4 TB 不参与扫描，也不计入系统段），任一子项读取失败该段即视为不可用；其他 = status 已用减去前四段且不小于 0。各探测经 3 条独立估算通道并发执行（单通道内串行，平均分摊）。任一输入缺失该段为空占位，不填演示常量。界面标明“估算”。

估算结果缓存四个目录字节和于 App 容器 `~/Library/Application Support/zmole/storage_estimate.json`（含 `schemaVersion`/`capturedAt`）。概览进入即先用缓存即时渲染并启动目录扫描（“其他”用实时 status 已用现算；status 迟到只更新“其他”，不影响扫描与已有分段）。触发点为：概览出现、写入失效信号、已用空间由无到有（仅重派生展示，不重扫）。完成的扫描（含部分）即展示并落盘；缺失段保持占位并保留「估算不完整」标记，随后自动补扫一次且只探测缺失段；扫描任务由 ViewModel 持有，不随视图消失取消。缓存超过 TTL（6 小时）或收到写入失效信号时全量重算并回写；超过最大年龄（7 天）或 schema 不符即作废。扫描被取消（应用退出）时不落盘。估算通道单条命令超时 600 秒。不提供手动计算按钮。

最近操作复用 `history --json`。概览不再绘制趋势条；状态页的系统负载图在采样点不足时显示等待说明，不伪造趋势。

## 磁盘页扫描

磁盘页不调用 mole：生产扫描根是 `/`，`LiveDiskScanner` 在应用内只读遍历目录（`lstat`）。文件大小取 `st_blocks × 512`；符号链接只计链接自身；同一扫描内指向同一文件的硬链接只计一次（行仍显示自身分配块，父扫描已计入的文件其子目录层合计不再重复计入）；与父目录设备号不同的子目录不计入父合计，进入后单独计算。进入目录先列出直接子项与直接文件大小，子目录大小在后台补上（最多 3 路并发，测量子任务随刷新取消）；扫描完成的层级保留在 `AnalyzeViewModel` 的会话缓存中（受容量上限约束），再次进入不再读盘，只有「重新分析」重扫当前目录及其子树并替换结果。大小未知的目录显示计算中、不显示为 0、不计入合计与面积图；无法读取的目录显示未扫描。demo 模式注入内存目录源，不读真实文件系统。概览五段估算仍走 `analyze`，与本路径无关。

## Demo 装配边界

`--demo` 使用相同生产 Views/ViewModels，但注入内存 fake process/streaming，禁止解析或 spawn 捆绑 mole。`--demo-page`、`--demo-state`、`--demo-language`、`--demo-appearance` 固定验收状态且仅在 `--demo` 下生效；`--demo-data-root` 只接受用户临时目录内的路径（越界值忽略并回退随机 scratch 目录），将 clean-list 与 whitelist 写入该目录，不触碰 `~/.config/mole/`。

## 与上游关系

- 上游 CLI：<https://github.com/tw93/mole>
- 本机研究用克隆：`~/kar/github_repo/mole`（只读对照；不从此路径打进 Release）
- 商标：公开发布不用 “Mole” 名称与官方 logo

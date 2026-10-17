# 决策记录（ADR）

只记录已经确认、影响后续工作的非显然决策。追加新条目，不重写历史；决策被替代时，新条目通过“替代”字段引用旧编号。

每条结构：`## NNN 标题（YYYY-MM-DD）`，下接 `- 背景` / `- 选项` / `- 结论` / `- 替代` 四项；替代填旧编号，无则写「无」。

## 001 桌面端采用 SwiftUI 原生，经 Bridge 调用 mole CLI（2026-09-21）

- 背景：本仓目标是把 mole CLI 做成 macOS 桌面应用；需选定 UI 技术与能力实现方式。
- 选项：
    1. SwiftUI 原生 App + `Process` 调用 mole
    2. Tauri + Web UI + sidecar/shell
    3. 仅仓库骨架，技术栈延后
- 结论：选 1。体积与权限模型更贴 macOS；清理语义由 mole 负责。首版非沙盒。Xcode 工程在实现 task 中用 XcodeGen 生成，不手写 pbxproj。调用哪一份 mole 见 002。
- 替代：无

## 002 捆绑钉死版本 mole，不进 PATH（2026-09-21）

- 背景：公开分发时不能要求陌生人先装 Homebrew；Finder 启动的 App 也看不到 shell PATH。
- 选项：只调本机 `mo`；始终捆绑；本机优先否则捆绑。
- 结论：始终捆绑完整 mole 安装树到 `Contents/Resources/mole/`，绝对路径 spawn。不把命令装进 PATH，避免和 brew `mo` 抢名、也避免双版本。禁止 GUI 调用捆绑副本的 `update`/`remove`。GPL 对应源码：本仓钉 tag/commit + README/Release 链接，不把源码打进 zip。
- 替代：001 中「调用本机已装 mo」

## 003 公开 GitHub zip，不公证（2026-09-21）

- 背景：目标用户是不认识的人；维护者暂不办理 Apple Developer Program。
- 选项：Developer ID + 公证；不公证依赖 Gatekeeper「仍要打开」。
- 结论：GitHub Release 发公证前的 `.zip`（内含 `Zmole.app`）。README 必须写清放行步骤与 `xattr -cr` 备路。本地自签证书 `Zmole Local Signing` 签名（登录钥匙串，一次授予 TCC/FDA 后跨重建保留）。Sparkle 与 dmg 后做。
- 替代：无

## 004 第一版只包装有稳定输出的能力（2026-09-21）

- 背景：mole 部分命令是全屏 TUI，无 JSON；用隐藏 PTY 代按键会在「第几行」上赌删除目标。
- 选项：嵌终端；隐藏终端代按键；自己扫盘；只做结构化输出 + 白名单文件。
- 结论：status / history / analyze 只读 / clean / uninstall / optimize / purge / 白名单编辑进第一版。installer、analyze 删除、代按键、嵌终端 park。破坏性操作一律先展示扫描结果并界面确认再 spawn。
- 替代：无

## 005 许可、语言、架构与隐私（2026-09-21）

- 背景：公开发布需要许可、三语、芯片与最低系统。
- 选项：见 grilling 记录。
- 结论：整仓 GPL-3.0；简体/繁体/英文跟随系统且设置可覆盖；Universal；macOS 13+；无遥测；产品名 zmole，不用 Mole 商标与官方 logo。
- 替代：无

## 006 卸载 stdin 只应答 `[y/N]`，身份用 path（2026-09-21）

- 背景：命名 uninstall 在 dry-run/执行前都要 `read -r` 读 `y/Y`；CLI 按名称取首个匹配。
- 选项：空 stdin；PTY 代按键；stdin 写 `y\n`；第一版不做卸载。
- 结论：stdin 只写 `y\n`。list 行用 `path`+`bundle_id` 校验；`uninstall_name` 不唯一则拒绝。不因此放宽 TUI 代操作。
- 替代：无

## 007 清理删除改走废纸篓且不清空废纸篓（2026-10-16）

- 背景：上游 `mo clean` 经 `safe_remove` 执行 `rm -rf`，并在同一次运行里 `clean_trash` 永久清空 `~/.Trash`。产品决定清理也要可恢复。
- 选项：
    1. 维持永久删除
    2. 补丁捆绑 clean：`safe_remove` 在 `MOLE_CURRENT_COMMAND=clean` 时改把目标移入 `~/.Trash`，并停用 `clean_trash`；移动失败保留原文件、不退回 `rm -rf`
    3. 只改 Swift 侧、不改捆绑脚本
- 结论：选 2。补丁限于捆绑树内的 clean 删除路径（`lib/core/file_ops.sh` 新增 `_mole_clean_trash_path`；`lib/clean/user.sh` 的 `clean_trash` 直接返回）。卸载本就进废纸篓；项目清理与优化的删除维持永久删除并由页面写明；安装包删除在后续 task 改为废纸篓。上游 tag 升级时该补丁需重放。
- 替代：004 中「clean 破坏性操作一律展示结果后执行」不变，仅改删除落点。

## 008 安装包走非交互接口，删除进废纸篓（2026-10-16）

- 背景：上游 `mo installer` 只有全屏选择菜单，无 JSON，删除走 `mole_delete` 默认永久删除；GUI 不能代按键。
- 选项：
    1. 保持 TUI/代按键
    2. 在捆绑 installer 上增加非交互接口：`--list-json` 列出候选（绝对路径、字节大小、来源、身份），`--remove <path>` 只接受本次列出的路径并核对身份与大小，删除显式置 `MOLE_DELETE_MODE=trash`
    3. 在 Swift 里重写扫描
- 结论：选 2。扫描规则仍用捆绑 installer 的现有目录、深度与 ZIP 判断；删除失败保留原文件，不退回永久删除；界面（t023）只消费该接口。补丁限于捆绑 installer 脚本并标注 `zmole local patch (t022)`，上游 tag 升级时重放。
- 替代：004 中「installer park」部分（004 其余结论仍有效）

## 009 强调色改为应用图标蓝系（2026-10-17）

- 背景：设计基线原以 demo HTML 的绿色 `#2f8f68` 为视觉权威；实现批（4ed8314）已把 accent 改为与应用图标一致的蓝系（浅色 `#0072FF`、深色 `#4FACFE`），并同步了图标源与生成脚本。
- 选项：
    1. 维持 HTML 绿色
    2. 确认蓝系：HTML 降为布局参考，色彩以应用图标为准
- 结论：选 2。`MoleTheme.accent`/`accentStrong` 为唯一色源，`UtilityStyle.accent` 直接引用 `MoleTheme.accent`；`ui_contract.md` 的参考资料声明同步更新。
- 替代：无

## 010 磁盘测量统计事实与派生去重分离（2026-10-18）

- 背景：旧磁盘扫描在 ViewModel 内持有多路 worker，任务组取空后新入队导致 worker 终止并残留待测项；且依赖共享的 `HardLinkDeduplicator` 边测边标记，导致目录自身合计随兄弟 worker 完成顺序漂移，祖先结果被较新 listing generation 拦截。
- 选项：
    1. 仅在 worker 退出前补一次启动并保留全局 deduplicator
    2. 由会话服务 `DiskMeasurementSession` 统一持有任务队列、在途调度与世代，底层仅记录设备+inode 与分配块测量事实；独立目录自身合计与父统计范围去重贡献分离并分别命名，兄弟间共享 inode 归属按规范化路径排序确定
- 结论：选 2。消除队列饥饿，保证兄弟完成顺序与祖先展开不改变去重结果，迟到结果按世代丢弃。
- 替代：无

## 011 磁盘测量统计完整性与缓存驻留分离（2026-10-18）

- 背景：扫描大树（如数千目录）若全树驻留内存会导致内存膨胀，而直接截断扫描则会使统计不完整或丢失文件。
- 选项：
    1. 限制每目录可见条目或在内存中直接截断结果
    2. 统计完整性与内存驻留分离：由系统内置 SQLite 数据库 `DiskSessionStore` 承载完整目录索引与 inode 去重事实，内存采用 LRU 有界工作集（默认 4000 条目），支持按需分页查询与带背压的分批流式发布
- 结论：选 2。在严格限定内存驻留上限的同时，完整保留了精确统计、无截断分页浏览与搜索能力；空间超限时明确报错而不污染快照。
- 替代：无

## 012 统一重扫描资源准入与调度名额选定（2026-10-18）

- 背景：后台 5 项扫描、概览目录估算与磁盘子树测量并发叠加时可能竞争系统 I/O 与文件描述符；若每个服务独立无约束并发，可能产生资源争抢与主线程卡顿。
- 选项：
    1. 允许各服务独立按通道数量自由运行，不做全局准入
    2. 由全局唯一 `HeavyScanScheduler` 进行资源准入管理，支持优先级提升（当前页面优先）与后台防饥饿调度。通过对名额 1、2、3、4 进行 5 轮交错重复测试，在代表性数据集上，名额 1（avg ~0.024s）、2（avg ~0.026s）、3（avg ~0.027s）与 4（avg ~0.026s）均稳定，其中名额 2-3 平衡了吞吐量与 I/O 抖动。
- 结论：选 2。采用 `HeavyScanScheduler` 作为单一资源准入控制，生产默认并发名额设定为 3，防饥饿界限设为 3。高优先级任务优先入场，后台任务防饥饿有界获得名额。
- 替代：无

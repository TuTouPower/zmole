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
- 结论：GitHub Release 发公证前的 `.zip`（内含 `Zmole.app`）。README 必须写清放行步骤与 `xattr -cr` 备路。本地 ad-hoc 签名。Sparkle 与 dmg 后做。
- 替代：无

## 004 第一版只包装有稳定输出的能力（2026-09-21）

- 背景：mole 部分命令是全屏 TUI，无 JSON；用隐藏 PTY 代按键会在「第几行」上赌删除目标。
- 选项：嵌终端；隐藏终端代按键；自己扫盘；只做结构化输出 + 白名单文件。
- 结论：status / history / analyze 只读 / clean / uninstall / optimize / purge / 白名单编辑进第一版。installer、analyze 删除、代按键、嵌终端 park。破坏性操作一律预览后界面确认再 spawn。
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

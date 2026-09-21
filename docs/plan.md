# plan：zmole 第一版

2026-09-21 需求grilling 已确认。本文是第一版切分；落地后以 `docs/tasks/` 与 `docs/blueprint/` 为准。

对照源码：`~/kar/github_repo/mole`（`V1.55.0` / `0659e906`）。运行时用 **App 捆绑的那一份**，不调用用户 brew 的 `mo`，不从 github_repo 路径打包进 Release。

## 已锁定产品

|项|结论|
|---|---|
|形态|标准窗口 App（侧栏 + 内容），SwiftUI，macOS 13+，Universal|
|分发|GitHub Release `.zip`（内含 `Zmole.app`）；不办公证、不上架 App Store|
|Gatekeeper|README 写「仍要打开 / 右键打开 / `xattr -cr`」；本地 ad-hoc `codesign`|
|命名|zmole；不用 Mole 商标与 logo；关于页写基于开源 CLI mole|
|语言|简体 / 繁体 / 英文；跟随系统，设置可覆盖|
|许可|整仓 GPL-3.0|
|mole|捆绑钉死版本；不进 PATH；不暴露 update/remove|
|破坏性|预览 → 界面确认 → 再 spawn；确认前不创建会删东西的进程|
|隐私|无遥测|
|更新|手动下 Release；Sparkle 以后再说|

## 第一版做 / 不做

做（后台跑命令，包装结构化输出）：

- status 快照、history、analyze **只读**浏览
- clean / uninstall / optimize / purge（均先预览）
- 白名单原生编辑（`~/.config/mole/whitelist`）
- 设置：语言、关于、版本、打开 GitHub Releases
- 独立图标、Gatekeeper 说明、zip

不做（已 park，见 `docs/pending/parked/`）：

- installer、analyze 删除、嵌终端代按键、捆绑 mole 的 update/remove
- Sparkle、公证、dmg

## 架构要点

```
SwiftUI Features → MoleBridge → Process(bundle 内 mole 绝对路径)
```

- 唯一 spawn 点：`MoleBridge`
- 布局：`Zmole.app/Contents/Resources/mole/`（完整 mole 安装树：入口脚本 + `lib/` + `bin/` + Go 辅助程序）
- 钉版本：本仓记录上游 tag/commit；构建时打进 bundle；README 与 Release 写明对应源码链接（源码不进 zip）
- 无 TTY：不解析 TUI；sudo 沿用 mole 的 `osascript`（对话框标题可能仍是 Mole）
- 空 stdin 对部分 `read -n1` 等于 Enter → **确认前禁止 spawn 破坏性命令**
- Finder PATH 无关：不搜 `/opt/homebrew/bin`

工程：根目录 `project.yml`（XcodeGen）生成 `Zmole.xcodeproj`，不手写 pbxproj。

## Backlog（已建，待创建 commit）

```
s001 mole_cli_fixtures
t001 xcode_app_skeleton
t002 mole_bundle_bridge          ← t001
t003 app_shell_i18n              ← t002
t004 status_snapshot             ← t003
t005 history_list                ← t003
t006 analyze_browser             ← t003
t007 whitelist_editor            ← t003
t008 clean_run                   ← t003
t009 uninstall_run               ← t008
t010 optimize_run                ← t008
t011 purge_run                   ← t008；预览 `purge --dry-run --yes`（s001/d001）
t012 icon_and_release_zip        ← t001（可与功能并行）
```

t004–t007 与 t008 在 t003 后可并行。破坏性确认组件由 t003 提供空壳，t008 先接上，t009–t011 跟 t008。

## 测试

- Bridge：假可执行夹具（参数、超时、非零退出）
- JSON：spike fixture 做解码
- 破坏性：测「未确认不调用 Bridge」；真删除不进自动测试
- 集成：对捆绑 mole 跑只读命令

## 环境（非 task）

- `sudo xcode-select -s /Applications/Xcode.app && xcodebuild -version`
- 构建机需要能编 mole 的 Go 辅助程序（或从已钉版本的上游 release 取 darwin 双 arch 二进制）

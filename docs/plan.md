# plan：zmole 第一版

2026-09-21 需求 grilling 已确认。本文是第一版切分；落地后以 `docs/tasks/` 与 `docs/blueprint/` 为准。

对照源码：`~/kar/github_repo/mole` 仅研究。**捆绑钉上游 tag `V1.55.0`（commit `69ab325d`）** 的 Bash 树 + 同 tag Go helper。不要用研究仓 `main`（曾见 `0659e906`）打进 App。

## 已锁定产品

|项|结论|
|---|---|
|形态|标准窗口 App（侧栏 + 内容），SwiftUI，macOS 13+，Universal（主程序与 mole helper 都要 arm64+x86_64）|
|分发|GitHub Release `.zip`（内含 `Zmole.app`）；不办公证、不上架 App Store|
|Gatekeeper|README 写「仍要打开 / 右键打开 / `xattr -cr`」；本地 ad-hoc `codesign`|
|命名|zmole；不用 Mole 商标与 logo；关于页写基于开源 CLI mole|
|语言|简体 / 繁体 / 英文；跟随系统，设置可覆盖|
|许可|整仓 GPL-3.0|
|mole|捆绑钉死 **V1.55.0 / 69ab325d**；不进 PATH；不暴露 update/remove|
|破坏性|本次预览成功 → 界面确认（对象一致）→ 再执行；确认前不 spawn 执行进程|
|卸载协议|stdin 只写 `y\n` 应答 `[y/N]`；身份用 list 的 `path`+`bundle_id`，`uninstall_name` 不唯一则拒绝|
|隐私|无遥测|
|更新|手动下 Release；Sparkle 以后再说|
|Releases URL|`https://github.com/TuTouPower/zmole/releases`|

## 第一版做 / 不做

做（后台跑命令，包装结构化输出）：

- status 快照、history、analyze **只读**浏览
- clean / uninstall / optimize / purge（均先预览）
- 白名单原生编辑（`~/.config/mole/whitelist`）
- 设置：语言、关于、版本、打开 GitHub Releases
- 独立图标、Gatekeeper 说明、zip 与解压验收

不做（已 park，见 `docs/pending/parked/`）：

- installer、analyze 删除、嵌终端代按键、捆绑 mole 的 update/remove
- Sparkle、公证、dmg

## 架构要点

```
SwiftUI Features → MoleBridge → Process(bundle 内 mole 绝对路径)
```

- 唯一 spawn 点：`MoleBridge`；每页最多一个 in-flight；cancel 杀进程组
- 布局：`Zmole.app/Contents/Resources/mole/`
- 无 TTY：不解析 TUI；sudo 沿用 mole 的 `osascript`
- 卸载 `y\n` 是文档化行确认，不是驱 TUI
- purge 预览：`purge --dry-run`；执行：`purge --yes`

工程：根目录 `project.yml`（XcodeGen）生成 `Zmole.xcodeproj`。

## Backlog

```
s001 mole_cli_fixtures           （已关闭，结论见 d001）
t001 xcode_app_skeleton
t002 mole_bundle_bridge          ← t001；Universal helper 必交
t003 app_shell_i18n              ← t002
t004 status_snapshot             ← t003
t005 history_list                ← t003
t006 analyze_browser             ← t003
t007 whitelist_editor            ← t003
t008 clean_run                   ← t003；共享预览世代与执行生命周期
t009 uninstall_run               ← t008
t010 optimize_run                ← t008
t011 purge_run                   ← t008
t012 icon_and_release_zip        ← t001；仅图标+README
t013 release_zip_verify          ← t002–t012；zip 与 Finder 只读验收
```

t004–t007 与 t008 在 t003 后可并行。t009–t011 跟 t008。

## 测试

- Bridge：假可执行夹具（参数、stdin、超时、取消、忙碌）
- JSON：s001 + 源码字段夹具
- 破坏性：预览世代、未确认不执行、同名拒绝
- 发布：lipo 双架构 + 解压启动只读页

## 环境（非 task）

- `sudo xcode-select -s /Applications/Xcode.app && xcodebuild -version`
- 构建取 tag `V1.55.0` 的 darwin 双 arch Go 二进制（或从该 tag 源码交叉编译后 lipo）

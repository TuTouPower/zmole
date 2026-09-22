# 架构

## 目标

macOS 原生窗口 App（zmole）：把开源 CLI [mole](https://github.com/tw93/mole) 的可脚本化能力做成 GUI。清理语义仍由捆绑的 mole 执行；本仓不重写清理引擎，不解析 TUI 帧。

## 模块划分

|模块|职责|边界|
|---|---|---|
|`App`|窗口、五模式导航、本地化、设置、依赖装配|不直接 `Process`|
|`Features/*`|Status / History / Analyze / Clean / Uninstall / Optimize / Purge / Whitelist|用户意图 → Bridge API + UI 状态|
|`MoleBridge`|定位 bundle 内 mole、拼参数、跑 `Process`、读 stdout/stderr、解析退出码与 JSON|唯一允许 spawn mole 的层|
|`Models`|命令结果、预览条目、白名单行等值类型|与 UI 解耦|

顶部主导航固定五模式：Clean、Software、Optimize、Analyze、Status。Software 内含 Uninstall/Protection rules；Optimize 内含 Maintenance/Purge；Status 内含 Live/History。第一版不出现：installer、analyze 删除、update、remove。

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
- `clean --dry-run` 的 `~/.config/mole/clean-list.txt` 是预览快照，执行时 mole 会重扫；UI 须写明。只展示**本次** dry-run 写入的内容，禁止沿用旧文件。
- 白名单：读写 `~/.config/mole/whitelist`（及 optimize 对应文件），不跑 whitelist TUI。
- App 设置（语言覆盖等）存本应用容器；mole 配置仍在 `~/.config/mole/`。

### 卸载确认协议

命名卸载（`uninstall <name> [--dry-run]`）会先打印 `Proceed with uninstallation? [y/N]` 并 `read -r`。空 stdin 导致中止。允许 MoleBridge **只**向 stdin 写入 `y\n`（mole 自己的行确认）；随后 batch 的 `read -n1` 遇 EOF 视为 Enter。禁止 PTY、方向键、解析 TUI 帧。

身份：list 的主键是 `path` + `bundle_id`。仅当 `uninstall_name` 在当前 list 中唯一对应那一行时才把它传给 CLI。同名不同 path、path 消失或重新匹配落到别的 path：拒绝执行。

### 进程生命周期

MoleBridge 对每个功能页最多一个 in-flight mole 进程。第二次提交须失败或排队（第一版：拒绝并保持忙碌）。`cancel` 结束该进程组。超时同上。终态：成功 / 失败（非零或无法解析）/ 取消；把 stdout/stderr 摘要交给 UI。切走页面不自动再开一个进程。

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

## Demo 装配边界

`--demo` 使用相同生产 Views/ViewModels，但注入内存 fake process/streaming，禁止解析或 spawn 捆绑 mole。`--demo-page`、`--demo-state`、`--demo-language`、`--demo-appearance` 固定验收状态；`--demo-data-root` 将 clean-list 与 whitelist 写入指定 scratch 目录，不触碰 `~/.config/mole/`。

## 与上游关系

- 上游 CLI：<https://github.com/tw93/mole>
- 本机研究用克隆：`~/kar/github_repo/mole`（只读对照；不从此路径打进 Release）
- 商标：公开发布不用 “Mole” 名称与官方 logo

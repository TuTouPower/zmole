# 架构

## 目标

macOS 原生窗口 App（zmole）：把开源 CLI [mole](https://github.com/tw93/mole) 的可脚本化能力做成 GUI。清理语义仍由捆绑的 mole 执行；本仓不重写清理引擎，不解析 TUI 帧。

## 模块划分

|模块|职责|边界|
|---|---|---|
|`App`|窗口、侧栏导航、本地化、设置、权限失败引导|不直接 `Process`|
|`Features/*`|Status / History / Analyze / Clean / Uninstall / Optimize / Purge / Whitelist|用户意图 → Bridge API + UI 状态|
|`MoleBridge`|定位 bundle 内 mole、拼参数、跑 `Process`、读 stdout/stderr、解析退出码与 JSON|唯一允许 spawn mole 的层|
|`Models`|命令结果、预览条目、白名单行等值类型|与 UI 解耦|

侧栏第一版不出现：installer、analyze 删除、update、remove。

## 数据流

```
用户操作 → Feature → MoleBridge.run(argv)
                      → Process(<bundle>/Contents/Resources/mole/mole …)
                      → stdout / stderr / exitCode
                      → Model → UI
```

- 破坏性命令：先 dry-run/列表 → 界面确认 → 再 spawn 执行。确认前不创建该 `Process`。
- `clean --dry-run` 的 `~/.config/mole/clean-list.txt` 是预览快照，执行时 mole 会重扫；UI 须写明。
- 白名单：读写 `~/.config/mole/whitelist`（及 optimize 对应文件），不跑 whitelist TUI。
- App 设置（语言覆盖等）存本应用容器；mole 配置仍在 `~/.config/mole/`。

## 捆绑与进程边界

- 钉死版本的 mole 安装树放在 `Contents/Resources/mole/`。入口用绝对路径，**不**搜 PATH、**不**调用 brew `mo`、**不**把命令装进 `/usr/local/bin`。
- 对应源码不进 Release zip；本仓记录上游 tag/commit，README / Release 给链接。
- 禁止在 GUI 暴露捆绑副本的 `update` / `remove`。
- 不给 `Process` 挂 TTY、不解析 ANSI 画面、不代发按键。
- 无 TTY 时 mole 的 sudo 走 `osascript`（标题可能仍是 Mole）。本仓不自造 sudo。
- 首版非沙盒；ad-hoc 签名便于本机 TCC。不公证。
- 与商业版 Mole for Mac（mole.fit）无关。

## 与上游关系

- 上游 CLI：<https://github.com/tw93/mole>
- 本机研究用克隆：`~/kar/github_repo/mole`（只读对照；不从此路径打进 Release）
- 商标：公开发布不用 “Mole” 名称与官方 logo

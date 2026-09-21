# 架构

## 目标

macOS 原生桌面壳，把 [mole](https://github.com/tw93/mole) CLI 的能力以 GUI 暴露出来。清理、卸载、优化等**业务语义仍由 `mo` 执行**；本仓不重写清理逻辑。

## 模块划分

|模块|职责|边界|
|---|---|---|
|`App`（SwiftUI）|窗口、导航、设置、权限提示、结果展示|不直接拼 shell；只调 Bridge API|
|`Features/*`|Clean / Uninstall / Optimize / Analyze / Status / Purge / Installer 等功能页|把用户意图变成 Bridge 调用与 UI 状态|
|`MoleBridge`|定位 `mo` 可执行文件、拼参数、跑 `Process`、读 stdout/stderr、解析退出码与（若有）JSON|唯一允许 spawn `mo` 的层|
|`Models`|命令结果、进度、白名单、历史条目等值类型|与 UI 解耦；JSON 解码落这里|

## 数据流

```
用户操作 → Feature ViewModel → MoleBridge.run(command, args)
                                 → Process(mo …)
                                 → stdout / stderr / exitCode
                                 → 解析为 Model → 更新 UI
```

- 破坏性操作（clean / uninstall / purge / installer / remove）默认先走 dry-run 或二次确认，再真正执行。
- 长任务：Bridge 提供流式输出或分阶段回调；UI 显示进度与可取消（若 CLI 支持信号）。
- 配置：App 设置存本应用容器（UserDefaults / 应用 Support）；mole 自身白名单等仍写 `~/.config/mole/`，由 CLI 管理。

## 进程与权限边界

- **不内嵌** mole 源码为默认路径；依赖系统 PATH 或用户配置的 `mo` 路径。后续若支持 sidecar 捆绑，须单独决策并更新本文件。
- App 以普通用户身份启动；需要管理员权限时，沿用 mole 的提权方式（由 `mo` 触发），不在 App 内自造 sudo 包装。
- 沙盒：首版**非沙盒** App（便于调用用户安装的 CLI 与访问其配置）。若日后上架 Mac App Store，须另开 ADR 处理沙盒与 helper。

## 与上游关系

- 上游 CLI：<https://github.com/tw93/mole>
- 上游商业桌面端 Mole for Mac（mole.fit）与本仓无关；功能可参考，实现不依赖、不复用其私有代码。

# 卸载（uninstall）

- 来源 task：t009、t019、t029、t043、t044、t053
- 生效范围：卸载页、名单流、确认协议、关联文件
- 最后更新：2026-10-18

## 行为契约

- 名单走 `uninstall --list-stream`：由扫描服务统一持有；渐进行先出名称/路径，随后补 bundle id、卸载名、来源、大小、版本、最近使用（同一扫描）；流式产生行最长 100 ms 聚合发布，流停止时 100 ms 内交付尾批；尚无大小的行不显示为 0（显示计算中）；图标在列表可交互后异步补上。名单未成功完成前禁止确认执行。
- `--list-stream` 元数据解析受父命令管理：并发 worker 必须登记并在完成时等待、取消时退出，stdin 为 `/dev/null`，关闭继承的写端 fd 3；不启动脱离父进程生命周期的后台 disown 任务；同一名单行大小只探测一次；元数据不可读时保留显式未知，致命错误不输出成功 done。
- 刷新经扫描服务统一请求；会话内确认复用同一份名单，不重跑全量大小扫描。页面离开仅解除订阅，不影响底层共享任务。
- 选择：真多选；搜索只过滤显示不清空选择；未选择不能确认执行。
- 选择后「卸载…」直接打开确认 sheet，不再生成或展示预览结果；不运行 `uninstall --dry-run` 作为执行门禁。
- 同一名单两条 `uninstall_name` 相同（path 不同）时禁止确认并说明无法唯一匹配；任何生产 argv 不含 `--permanent`。
- 确认前只做轻量身份核对（path 存在 + bundle id 未变）；变化则拒绝执行、不 spawn 卸载命令，并重新扫描名单。确认后 spawn `uninstall <names>`（stdin `y\n`，无 `--dry-run`）。
- 取消确认/未确认不执行；执行中忙碌、重复提交不创建第二进程；取消结束该进程。
- 结果未知态：CLI 输出无法证明逐项成功时显示「结果未知」与原文摘要；失败/部分完成保留摘要（errorMessageKey 分支携带 detail）；失败/取消等错误经本地化 key 渲染。
- 执行成功后剔除已处理行与选中；部分完成后后台重扫名单。
- 「检查关联文件」是非必需的详情动作：只在用户点击时对该项跑一次 `uninstall --dry-run`；解析真实输出行（ANSI 前缀 `✓` / `System:` / `Review only:` 与尾随尺寸均被剥离），未点不跑，失败给出可重试提示；未做 dry-run 不展示关联路径。
- 名单扫描取消时保留已解析行并显示「扫描已取消/继续扫描」状态；全坏 JSON 流抛解析错误而不是伪空列表。
- 详情：选中项显示名称与 path；搜索过滤后选中保留；版本/最近使用缺失显示未知；大小不可解析显示未知；多选合计为应用本体估计。

## 验证

- `tests/unit/UninstallTests.swift`、`tests/unit/UninstallDetailTests.swift`、`tests/unit/BatchUninstallTests.swift`、`tests/unit/UninstallStreamTests.swift`、`tests/unit/BackgroundScanTests.swift`
- `tests/integration/uninstall_stream_test.sh`（含命名卸载空 stdin 中止与 `y\n` dry-run 真实协议；dry-run 仍用于「检查关联文件」）

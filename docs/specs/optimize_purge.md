# 优化与项目清理（optimize_purge）

- 来源 task：t010、t011、t021、t043、t044
- 生效范围：优化页、项目清理页
- 最后更新：2026-10-17

## 行为契约

- 两页数据来自后台只读扫描：`optimize --dry-run` 与 `purge --dry-run`；结果落盘并在 24 小时内复用，页面打开直接显示。
- 页头动作为「刷新」；点击触发对应后台扫描，扫描中按钮变为「取消」且不重复触发；完成后页面自动更新并显示扫描时间。
- 无数据时显示「暂无数据」与刷新入口；扫描失败显示失败提示并保留上次成功数据。
- 执行 argv：优化为 `optimize`（无 `--dry-run`），项目清理为 `purge --yes`（不含 `--dry-run`）；不存在「无 `--dry-run` 且无 `--yes`」的 purge 路径。运行范围由 mole 决定，界面不裁剪子集（argv 不含任务 id 或勾选路径）。
- 任务行只读；跳过原因显示在对应行；会删除文件的任务标「永久删除」；无法识别的行保守展示原文并标注未知，不猜状态。
- 存在扫描结果即可打开确认 sheet；确认 sheet 携带本次结果摘要。取消或关闭不执行。
- 扫描目录编辑：读写 `~/.config/mole/purge_paths`；每行必须是绝对路径或 `~/` 开头；保存成功使当前 purge 结果失效；加载失败（含未知 IO 错误）显示通用错误并禁用保存，避免用空内容覆盖原文件；非法保存失败时编辑内容留在界面。
- 两页文案写明永久删除（不写移入废纸篓）；结果错误经本地化 key 渲染。
- 执行结果：失败/部分完成保留摘要；成功才显示 checkmark 结果通知（失败摘要并入错误通知）。

## 验证

- `tests/unit/OptimizeTests.swift`、`tests/unit/PurgeTests.swift`、`tests/unit/OptimizePurgePageTests.swift`、`tests/unit/BackgroundScanTests.swift`
- `tests/unit/OptimizePurgePageTests.swift`（真实 dry-run 样本解析，样本位于 `docs/archive/spikes/s001_mole_cli_fixtures/samples/`）

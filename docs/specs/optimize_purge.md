# 优化与项目清理（optimize_purge）

- 来源 task：t010、t011、t021
- 生效范围：优化页、项目清理页
- 最后更新：2026-10-17

## 行为契约

- 优化预览 argv 为 `optimize --dry-run`；确认后 argv 为 `optimize`（无 `--dry-run`）。运行范围由 mole 决定，界面不裁剪子集（argv 不含任务 id 子集）。
- 任务行只读；跳过原因显示在对应行；会删除文件的任务标「永久删除」；无法识别的行保守展示原文并标注未知，不猜状态。
- 预览非零退出时执行按钮不可用，不保留上一次成功预览文本当作本次；取消确认后必须重新预览才能执行；预览过期（协调器失效信号/再次预览）同样需重新预览。
- 项目清理预览 argv 为 `purge --dry-run`（不含 `--yes`）；确认后 argv 含 `purge` 与 `--yes`（不含 `--dry-run`）；不存在「无 `--dry-run` 且无 `--yes`」的 purge 路径；执行范围由 mole 决定，非勾选子集。
- 扫描目录编辑：读写 `~/.config/mole/purge_paths`；每行必须是绝对路径或 `~/` 开头；保存成功使当前 purge 预览失效；加载失败（含未知 IO 错误）显示通用错误并禁用保存，避免用空内容覆盖原文件；非法保存失败时编辑内容留在界面。
- 两页文案写明永久删除（不写移入废纸篓）；确认 sheet 携带本次预览摘要。
- 执行结果：失败/部分完成保留摘要；成功才显示 checkmark 结果通知（失败摘要并入错误通知）；结果错误经本地化 key 渲染。

## 验证

- `tests/unit/OptimizeTests.swift`、`tests/unit/PurgeTests.swift`、`tests/unit/OptimizePurgePageTests.swift`
- `tests/unit/OptimizePurgePageTests.swift`（真实 dry-run 样本解析，样本位于 `docs/archive/spikes/s001_mole_cli_fixtures/samples/`）

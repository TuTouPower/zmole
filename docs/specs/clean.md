# 清理（clean）

- 来源 task：t008、t017、t018
- 生效范围：清理页、清洁删除落点、预览快照一致性
- 最后更新：2026-10-17

## 行为契约

- 预览 argv 为 `clean --dry-run`（流式优先，可显示当前扫描阶段名）；确认前不出现无 `--dry-run` 的 clean。
- 预览只读**本次** dry-run 写出的 `~/.config/mole/clean-list.txt`（可注入路径）；不展示目录旧文件。dry-run 非零退出或未写出本次列表即预览失败，确认不可用。
- 预览 UI 含「执行时会重新扫描、列表可能变化」的说明；扫描显示当前阶段译名（如 Browsers），不显示百分比。
- 确认使用本次预览；取消确认/取消预览/再次预览后旧预览失效，需重新预览才能确认。执行前校验列表文件内容未变（同长度覆写也会拒绝）。
- 确认后 spawn `clean`（无 `--dry-run`）；执行中忙碌、重复提交不创建第二进程；取消结束该进程；非零退出展示失败摘要（非瞬时提示）。
- 预览成功后侧边栏清理角标等于本次预览可回收量；失败或未预览无角标。可回收合计来自真实 mole 尺寸格式（紧凑写法如 `2.40GB`），解析再大数值不崩溃。
- 删除落点：clean 的删除移入废纸篓（打包脚本补丁 `MOLE_DELETE_MODE=trash` 路径 + 停用 clean_trash）；移动失败保留原文件、不退回 `rm -rf`；dry-run 不把清空用户废纸篓列为待删除项。
- 页面没有按勾选子集执行的控件；「保护」按钮把路径写入 clean 白名单并使当前预览失效；加白名单失败（重复/未加载/写盘失败）在清理页给出可见反馈。
- 用户预览开始前等待被取消的预跑进程完全退出，避免两侧并发写同一列表文件；预跑期间用户开始预览时，迟到的预跑结果被丢弃。
- zh-Hans 文案写明移入废纸篓，不写永久删除。

## 验证

- `tests/unit/CleanPageTests.swift`、`tests/unit/CleanPreviewStoreTests.swift`、`tests/unit/ZmoleTests.swift`
- `tests/integration/clean_trash_test.sh`（真实捆绑 clean + 隔离 HOME/Trash）

# 清理（clean）

- 来源 task：t008、t017、t018、t043、t044
- 生效范围：清理页、清理数据来源、删除落点、确认与执行
- 最后更新：2026-10-17

## 行为契约

- 页面数据来自后台 `clean --dry-run`（t043）：扫描在应用启动后自动执行，结果落盘并在 24 小时内复用；页面打开直接显示，不需要用户先点按钮。
- 页头动作为「刷新」；点击触发后台 clean 扫描，扫描中按钮变为「取消」且不重复触发。扫描完成后页面自动更新并显示扫描时间。
- 无数据时显示「暂无数据」与刷新入口；扫描失败显示失败提示并保留上次成功数据。
- 执行 argv 为 `clean`（无 `--dry-run`）；确认后 spawn，运行范围由 mole 决定，不按勾选子集执行。
- 存在扫描结果即可打开确认 sheet；确认 sheet 显示条目数与可回收量，并说明执行时 mole 会重新扫描、列表可能变化。取消或关闭不执行。
- 执行开始前取消后台 clean 扫描并等待其进程完全退出；写入租约持有期间后台 clean 不启动。执行不因 `clean-list.txt` 在扫描后变化而拒绝，实际删除以 mole 执行时重扫为准。
- 执行中忙碌、重复提交不创建第二进程；取消结束该进程；非零退出展示失败摘要（非瞬时提示）。
- 侧栏清理角标与概览可回收量来自最近一次清理扫描结果；无数据时显示「暂无数据」。可回收合计来自真实 mole 尺寸格式（紧凑写法如 `2.40GB`），解析再大数值不崩溃。
- 删除落点：clean 的删除移入废纸篓（打包脚本补丁 `MOLE_DELETE_MODE=trash` 路径 + 停用 clean_trash）；移动失败保留原文件、不退回 `rm -rf`；dry-run 不把清空用户废纸篓列为待删除项。
- 页面没有按勾选子集执行的控件；「保护」按钮把路径写入 clean 白名单并使当前清理结果失效；加白名单失败（重复/未加载/写盘失败）在清理页给出可见反馈。
- zh-Hans 文案写明移入废纸篓，不写永久删除。

## 验证

- `tests/unit/CleanPageTests.swift`、`tests/unit/CleanPreviewStoreTests.swift`、`tests/unit/BackgroundScanTests.swift`、`tests/unit/ZmoleTests.swift`
- `tests/integration/clean_trash_test.sh`（真实捆绑 clean + 隔离 HOME/Trash）

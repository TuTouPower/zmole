# 确定性 UI 演示入口

演示模式复用生产 `AppShellView`、页面 View 与 ViewModel，但把 `MoleProcessControlling` 与磁盘页的目录源 `DiskScanning` 注入为内存假服务。演示进程不会定位、启动或取消捆绑 `mole`；磁盘页由内存目录源驱动，不读真实目录；也不会写入 `~/.config/mole/`。

```text
Zmole.app/Contents/MacOS/Zmole \
  --demo \
  --demo-page disk \
  --demo-state populated \
  --demo-language zh-Hans \
  --demo-appearance light \
  --demo-data-root "$PWD/.scratch/ui_rebuild/demo_data"
```

支持页面（侧边栏十目的地）：`overview`、`clean`、`uninstall`、`disk`、`optimize`、`status`、`purge`、`installers`、`history`、`settings`；旧名 `analyze`→`disk`、`software`→`uninstall` 作为别名保留。未传 `--demo-page` 时默认为 `overview`。`--demo-state` 支持 `populated`、`empty`、`busy`、`error`、`partial`、`stale`，所有状态仍由生产 View/ViewModel 展示。

窗口默认 1200 × 780 pt，内容最小尺寸为 1100 × 700 pt。浅色/深色由 `--demo-appearance light|dark` 固定；语言由 `--demo-language en|zh-Hans|zh-Hant` 固定。

传入 `--demo-data-root` 后，演示会在该目录创建 `clean-list.txt` 与 `whitelist`，不访问 `~/.config/mole/`。视觉验收应使用仓库 `.scratch/` 下目录，避免污染真实配置。

# p015 后台扫描 clean deferred 压制与 cancelAndWait 收尾缺单元覆盖

- 来源：t043 遗留（t043_test_f005，minor）
- 内容：`BackgroundScanService` 的「用户接管后 `deferredClean` 压制 `request(.clean)`」与「`cancelAndWait` 不再手动清 `tasks`、交由 `run` defer 收尾」两条并发修复对应的反事实测试缺失（删除任一改动现有 296 用例仍全绿）。t044 重写 clean 刷新路径时补：预置/取消场景断言 deferred 期间 request 不产生新进程、`noteActivityChanged` 后恢复；以及取消后紧接 request 只产生一个新任务。
- 处理：未开

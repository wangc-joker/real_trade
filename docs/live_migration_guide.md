# 旧实盘仓位迁移到新目录的安全步骤

这份说明用于把你现在在 `D:\test\ft_userdata` 里跑的原版实盘，安全迁移到 `D:\test\real_trade` 里的新策略实盘，同时尽量继续接管原来的持仓。

## 先说结论

如果你希望新目录里的 bot 继续管理旧仓位，核心不是只搬配置文件，而是要保证：

- 新 bot 使用同一套交易所账户
- 新 bot 继续读取旧 bot 的交易数据库状态
- 不要让两个 bot 同时写同一个 sqlite 数据库

最稳妥的做法是：

1. 先停旧 bot
2. 备份旧数据库
3. 把旧数据库复制到新目录
4. 用新目录启动新策略
5. 先确认旧仓位能正常显示，再放行继续交易

## 关键判断

### 1. `available_capital` 不是仓位状态

`available_capital` 只是资金基数，不是持仓记录。

它会影响：

- 初始可用资金怎么算
- 已实现盈亏如何滚动到后续资金池

它不会保存：

- 当前持仓
- 挂单
- 已开仓状态
- 交易历史

这些都在 bot 的数据库里。

### 2. 真正需要迁移的是数据库

如果你想让新 bot 接着接管旧仓位，通常要迁移的是：

- `tradesv3*.sqlite`
- 如果存在，还要一起带上：
  - `*.sqlite-wal`
  - `*.sqlite-shm`
  - `*.sqlite-journal`

## 安全步骤

### 第 1 步：先确认旧 bot 还在什么状态

先看旧 bot 有没有：

- 开仓中的仓位
- 未成交挂单
- 还在等待处理的部分成交订单

建议先记一下当前状态，方便迁移后比对。

旧目录参考：

- [D:\test\ft_userdata](/D:/test/ft_userdata)

### 第 2 步：正常停掉旧 bot

不要直接删文件，也不要让两个 bot 同时在线。

先正常停止旧服务，确认它已经不再写数据库。

### 第 3 步：备份旧数据库

把旧目录里和当前实盘对应的 sqlite 先完整备份一份。

建议一起备份这些文件：

- 主数据库文件
- `-wal`
- `-shm`
- `-journal`

这样可以避免数据库还在 WAL 模式时只拷主文件导致状态不完整。

### 第 4 步：把旧数据库复制到新目录

把旧 bot 当前使用的数据库，复制到新目录：

- [D:\test\real_trade\user_data](/D:/test/real_trade/user_data)

新目录里的 live 启动脚本当前默认会使用类似这种数据库名：

- [start_nfi_dynamic_top40_302u_max2_live.ps1](/D:/test/real_trade/scripts/start_nfi_dynamic_top40_302u_max2_live.ps1)

对应数据库路径是：

`/freqtrade/user_data/tradesv3_nfi_dynamic_top40_302u_max2_live.sqlite`

如果你是用别的实盘脚本，也要把它对应的数据库一并放到新目录。

### 第 5 步：确认新目录配置一致

新 bot 仍然应该保持这些一致：

- 同一个 Binance 合约账户
- 同一套 API key / secret
- 同样的 `trading_mode`
- 同样的 `margin_mode`
- 同样的交易所类型

如果这些变了，就不再是“接着管理原仓位”。

### 第 6 步：先启动，但先别急着放行

先启动新目录的 bot，让它读取数据库、恢复状态，但先观察：

- 旧仓位是否显示出来
- 挂单是否还在
- 有没有“找不到 trade”之类的异常
- 有没有重复开单迹象

建议先用状态查看脚本确认：

- [show_nfi_dynamic_top40_302u_max2_live_status.ps1](/D:/test/real_trade/scripts/show_nfi_dynamic_top40_302u_max2_live_status.ps1)

### 第 7 步：前 10 到 20 分钟重点观察

重点看：

- 有没有重复下单
- 旧仓位是否被识别成已有持仓
- 退出信号是否异常提前
- 补仓逻辑是否按预期执行

这一步很关键，因为迁移后最容易出问题的就是第一轮状态同步。

### 第 8 步：确认稳定后再长期跑

如果状态正常，再继续让新 bot 运行。

如果有异常，先停 bot，回滚到备份数据库，再重新检查。

## 不要做的事

- 不要让两个 bot 同时写同一个 sqlite
- 不要在数据库没备份时直接覆盖
- 不要在没确认旧仓位同步成功时就让新 bot 自动进场
- 不要把“改策略文件”误当成“迁移仓位”本身

## 最稳妥的执行顺序

1. 停旧 bot
2. 备份旧数据库
3. 复制旧数据库到 `D:\test\real_trade\user_data`
4. 用新目录启动新策略
5. 检查状态脚本
6. 确认旧仓位正常接管
7. 再继续运行

## 相关文件

- 新实盘目录：[D:\test\real_trade](/D:/test/real_trade)
- 旧实盘目录：[D:\test\ft_userdata](/D:/test/ft_userdata)
- 新实盘启动脚本：[start_nfi_dynamic_top40_302u_max2_live.ps1](/D:/test/real_trade/scripts/start_nfi_dynamic_top40_302u_max2_live.ps1)
- 新实盘状态脚本：[show_nfi_dynamic_top40_302u_max2_live_status.ps1](/D:/test/real_trade/scripts/show_nfi_dynamic_top40_302u_max2_live_status.ps1)


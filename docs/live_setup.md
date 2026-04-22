# 实盘使用说明

这个仓库是 `nfi_dynamic_top40_302u_max2` 这套实盘机器人的精简版仓库，只保留实盘运行、状态查看、动态币池更新、策略评审相关文件。

当前默认实盘币池已经切到“平衡版动态 Top40”。

## 当前实盘参数

- 策略：`NostalgiaForInfinityX7`
- 交易市场：`Binance Futures`
- 资金：`302.6 USDT`
- 最大持仓：`2`
- 币池来源：平衡版动态 Top40

## 关键文件

- 实盘配置模板：[config.live.nfi.dynamic.top40.302u.max2.json](/D:/work/real_trade/user_data/config.live.nfi.dynamic.top40.302u.max2.json)
- 策略文件：[NostalgiaForInfinityX7.py](/D:/work/real_trade/user_data/strategies/NostalgiaForInfinityX7.py)
- 当前动态币池更新入口：[update_nfi_dynamic_coin_40.cmd](/D:/work/real_trade/scripts/update_nfi_dynamic_coin_40.cmd)
- 当前动态币池调度脚本：[update_nfi_dynamic_coin_40.ps1](/D:/work/real_trade/scripts/update_nfi_dynamic_coin_40.ps1)
- 当前默认币池生成脚本：[update_nfi_dynamic_top40_302u_balanced.ps1](/D:/work/real_trade/scripts/update_nfi_dynamic_top40_302u_balanced.ps1)
- 备用/历史币池脚本：[update_nfi_dynamic_top40_302u.ps1](/D:/work/real_trade/scripts/update_nfi_dynamic_top40_302u.ps1)
- 启动脚本：[start_nfi_dynamic_top40_302u_max2_live.ps1](/D:/work/real_trade/scripts/start_nfi_dynamic_top40_302u_max2_live.ps1)
- 状态查看脚本：[show_nfi_dynamic_top40_302u_max2_live_status.ps1](/D:/work/real_trade/scripts/show_nfi_dynamic_top40_302u_max2_live_status.ps1)
- 自动恢复脚本：[auto_recover_nfi_dynamic_top40_302u_max2_live.ps1](/D:/work/real_trade/scripts/auto_recover_nfi_dynamic_top40_302u_max2_live.ps1)

当前实盘实际使用的币池更新链路是：

`update_nfi_dynamic_coin_40.cmd` -> `update_nfi_dynamic_coin_40.ps1` -> `update_nfi_dynamic_top40_302u_balanced.ps1`

这条链路会：

- 刷新本地平衡版 Top40 币池文件
- 同步更新运行中的 `.runtime.json` whitelist
- 如果 bot 正在运行，则调用 `reload_config` 让运行中服务直接加载新币池

## 密钥与敏感配置

仓库里不保存交易所密钥，也不提交带密钥的 runtime 配置。

默认读取的安全文件路径：

`D:\work\secure\secret_bin.json`

建议结构：

```json
{
  "exchange": {
    "key": "BINANCE_KEY",
    "secret": "BINANCE_SECRET"
  },
  "api_server": {
    "username": "Freqtrader",
    "password": "CHANGE_ME",
    "jwt_secret_key": "CHANGE_ME",
    "ws_token": "CHANGE_ME"
  }
}
```

也支持通过环境变量覆盖 API 信息：

- `FREQTRADE_API_USERNAME`
- `FREQTRADE_API_PASSWORD`
- `FREQTRADE_API_JWT_SECRET`
- `FREQTRADE_API_WS_TOKEN`

## 动态 Top40 币池规则

这一节描述的是“稳健版”规则，当前默认实盘不再使用它，保留它仅用于对照、排查或后续回切。

- 只保留 Binance Futures 的 `USDT` 永续合约
- 合约状态必须是 `TRADING`
- 上市时间至少满 `60` 天
- 过滤带这些后缀的杠杆币：`BULL`、`BEAR`、`UP`、`DOWN`
- 过滤 `1000*` 这类倍率面值合约
- 过滤明显不属于目标范围的标的：`XAU`、`XAG`、`XAUT`、`PAXG`、`TSLA`
- 计算最近 `30` 天平均日成交额
- 只保留最近 `30` 天平均日成交额大于 `1200万 USDT` 的币
- 只保留最近 `30` 天成交额中位数大于 `1000万 USDT` 的币
- 最近 `30` 天中，至少 `20` 天日成交额大于 `1000万 USDT`
- 单日最大成交额 / 30 天中位数 不得大于 `4`
- 再按最近 `30` 天平均日成交额从高到低排序
- 最多选取 `40` 个币种

生成文件位置：

- 币池列表：[pairs.dynamic.top40.302u.json](/D:/work/real_trade/user_data/generated/pairs.dynamic.top40.302u.json)
- 生成报告：[pairs.dynamic.top40.302u.report.json](/D:/work/real_trade/user_data/generated/pairs.dynamic.top40.302u.report.json)

## 平衡版 Top40 币池规则

这套规则是给“收益和稳健性之间取中间值”准备的，也是当前 `D:\work\real_trade` 默认实盘所使用的规则。

思路是：

- `28` 个核心币：继续使用稳健流动性规则
- `12` 个卫星币：适度放宽流动性门槛，保留一部分高弹性机会

核心币规则：

- 上市至少 `60` 天
- 近 `30` 天平均日成交额 `>= 1200万 USDT`
- 近 `30` 天成交额中位数 `>= 1000万 USDT`
- 最近 `30` 天至少 `20` 天日成交额 `>= 1000万 USDT`
- 单日最大成交额 / `30` 天中位数 `<= 4`

卫星币规则：

- 上市至少 `45` 天
- 近 `30` 天平均日成交额 `>= 800万 USDT`
- 近 `30` 天成交额中位数 `>= 600万 USDT`
- 最近 `30` 天至少 `14` 天日成交额 `>= 700万 USDT`
- 单日最大成交额 / `30` 天中位数 `<= 6`

共同过滤：

- 只保留 `USDT` 永续
- 合约状态必须是 `TRADING`
- 去掉 `BULL`、`BEAR`、`UP`、`DOWN`
- 去掉 `1000*`
- 去掉 `XAU`、`XAG`、`XAUT`、`PAXG`、`TSLA`

生成文件位置：

- 平衡版币池列表：[pairs.dynamic.top40.302u.balanced.json](/D:/work/real_trade/user_data/generated/pairs.dynamic.top40.302u.balanced.json)
- 平衡版生成报告：[pairs.dynamic.top40.302u.balanced.report.json](/D:/work/real_trade/user_data/generated/pairs.dynamic.top40.302u.balanced.report.json)

## 日常操作

### 1. 启动实盘

运行：

`[start_nfi_dynamic_top40_302u_max2_live.cmd](/D:/work/real_trade/scripts/start_nfi_dynamic_top40_302u_max2_live.cmd)`

执行内容：

- 优先读取本地已有的平衡版动态 Top40 币池文件
- 只有在本地币池文件不存在时，才自动刷新一次
- 把密钥注入 runtime 配置
- 启动 Docker Compose
- 等待 API 可用
- 发送 bot 启动命令

### 1.1 更新币池

运行：

`[update_nfi_dynamic_coin_40.cmd](/D:/work/real_trade/scripts/update_nfi_dynamic_coin_40.cmd)`

执行内容：

- 刷新本地平衡版 Top40 币池文件
- 把新 whitelist 写回当前 `.runtime.json`
- 如果 bot 正在运行，则调用 `reload_config`

### 2. 查看状态

运行：

`[show_nfi_dynamic_top40_302u_max2_live_status.cmd](/D:/work/real_trade/scripts/show_nfi_dynamic_top40_302u_max2_live_status.cmd)`

会显示：

- bot 状态
- 当前加载币种数
- 当前持仓
- 盈亏
- 账户余额
- 最近平仓记录

### 3. 自动恢复

运行：

`[auto_recover_nfi_dynamic_top40_302u_max2_live.cmd](/D:/work/real_trade/scripts/auto_recover_nfi_dynamic_top40_302u_max2_live.cmd)`

执行内容：

- 检查 Clash 是否启动
- 检查 Docker Desktop 是否可用
- 检查 bot API 是否已在运行
- 如果没有运行，则自动拉起 bot

### 4. 迁移旧仓位

如果你想把旧目录 `D:\work\ft_userdata` 里的实盘仓位，迁移到这个新目录继续管理，可以先看这份说明：

- [旧实盘仓位迁移到新目录的安全步骤](/D:/work/real_trade/docs/live_migration_guide.md)

这份文档会讲清楚：

- 为什么要迁移数据库
- 为什么不能同时开两个 bot 写同一个 sqlite
- 迁移前后应该先检查什么
- 怎么确认新 bot 已经接住旧仓位

## 目录说明

- `scripts`
  放启动、查看状态、恢复、更新币池、策略评审脚本
- `user_data/strategies`
  放当前实盘策略
- `user_data/generated`
  放动态币池生成结果
- `user_data/reviews`
  放每次策略评审的 diff、回测、结论
- `user_data/logs`
  放日志

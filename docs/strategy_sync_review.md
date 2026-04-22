# 策略同步与评审说明

这套流程的目标不是“自动替换实盘策略”，而是每周帮你评估一次：

- 上游 `NostalgiaForInfinityX7` 有没有更新
- 新版本和当前实盘版本相比改了什么
- 用同一套回测配置、同一时间区间重新跑一遍
- 判断这次更新有没有明显收益优势
- 判断风险点是否值得接受

## 当前参与评审的策略

- 当前实盘版本：
  [NostalgiaForInfinityX7.py](/D:/test/real_trade/user_data/strategies/NostalgiaForInfinityX7.py)
- 上游仓库：
  `D:\test\NostalgiaForInfinity`

## 评审用回测配置

评审不是直接用实盘动态币池，而是用固定的静态对比配置：

- [config.backtest.review.nfi.top40.302u.max2.json](/D:/test/real_trade/user_data/config.backtest.review.nfi.top40.302u.max2.json)

这样做的原因是：

- 每周 review 都用同一套币池
- 可以排除“币池变化”对结果的干扰
- 更容易看清楚是“策略代码变化”带来的影响

评审配置固定内容：

- 资金：`302.6 USDT`
- 最大持仓：`2`
- 固定 Top40 币池
- futures 模式

## 怎么执行

运行：

`[review_upstream_nfi_strategy.cmd](/D:/test/real_trade/scripts/review_upstream_nfi_strategy.cmd)`

默认行为：

- 先到 `D:\test\NostalgiaForInfinity` 执行 `git pull --ff-only`
- 读取上游最新的 `NostalgiaForInfinityX7.py`
- 和当前实盘版本做 diff
- 用相同配置、相同时间区间，分别跑当前版和候选版回测
- 输出英文版明细和中文版结论

## 默认回测区间

如果你不传 `-Timerange`，默认会取：

- 结束时间：自动对齐到你本地回测数据的最后一天
- 开始时间：以这个结束时间往前推 `6` 个月

也就是默认评审“最近半年且按本地数据尾部对齐”的表现，避免拿到本地还没补齐的数据日期去比较。

如果你要手动指定时间区间，也可以运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File D:\test\real_trade\scripts\review_upstream_nfi_strategy.ps1 -Timerange 20251001-20260401
```

如果你不想在这次 review 里拉上游最新代码，可以加：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File D:\test\real_trade\scripts\review_upstream_nfi_strategy.ps1 -SkipPull
```

## 每次评审会生成什么

每次都会生成一个独立目录，例如：

`user_data\reviews\YYYYMMDD_HHMMSS\`

里面主要有：

- `current\`
  当前策略副本
- `candidate\`
  上游候选策略副本
- `diff.patch`
  原始代码差异
- `diff.stat.txt`
  差异统计
- `backtests\current\`
  当前策略回测结果
- `backtests\candidate\`
  候选策略回测结果
- `review.md`
  英文版明细
- `review.zh-CN.md`
  中文版结论
- `review.json`
  结构化评审结果

结果里还会额外记录：

- 上游 commit id
- 当前仓库 commit id
- 如果当前仓库还没有 commit，则记录当前策略文件的 SHA256

## 脚本会自动看哪些风险点

如果 diff 命中这些区域，脚本会把它标成风险点：

- `stoploss / custom_stoploss`
- `custom_exit`
- `confirm_trade_entry / confirm_trade_exit`
- `ROI / trailing`
- 币池相关分组
- 仓位、加仓相关逻辑
- 成交、滑点、执行确认逻辑
- protections

## 当前结论类型

脚本现在会给三类结论：

- `keep_current`
  保留当前策略，不建议更新
- `review_manually`
  需要人工复核后再决定是否更新
- `candidate_looks_safe`
  候选策略表现稳定，可考虑更新

## 结论是怎么判断的

当前是比较保守的一套规则：

- 如果候选版本最大回撤大于 `10%`
  倾向保留当前版本
- 如果候选收益明显低于当前版本
  倾向保留当前版本
- 如果交易数掉太多
  倾向人工复核
- 如果命中了高敏感逻辑改动
  倾向人工复核
- 如果收益、回撤、交易数都合理
  才会给“可考虑更新”

## 使用建议

### 不建议直接在持仓中替换策略

如果当前 bot 有持仓，直接替换策略文件意味着：

- 后续这些持仓会按新策略继续管理
- 原本会继续持有的仓位，可能提前退出
- 原本会加仓的，可能不再加仓

更稳的方式是：

- 先 review
- 再看 diff 和中文结论
- 最好在空仓时再切换策略

### review 只是评审，不会自动更新实盘

这套脚本不会自动把候选版覆盖到当前实盘策略。

它只负责：

- 同步上游
- 做对比
- 跑回测
- 给结论

最终是否更新，还是由你决定。

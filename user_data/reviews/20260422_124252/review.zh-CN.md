# 策略评审结论

## 总结

- 生成时间：2026-04-22 12:49:43 +08:00
- 回测区间：20251020-20260420
- 上游 commit id：5ea2fe34a6b8db86ff5118595752c7f8ff7f9f4e
- 当前 commit id：当前仓库暂无 commit，策略文件 SHA256：F62F29A51A4100F1730FA40A8783183B2B092D00BAB5C48D49CFD4414D94F490
- 结论：需要人工复核后再决定是否更新

## 核心对比

| 策略 | 最终资金 | 绝对收益 | 收益率 | 最大回撤 | 交易数 | 胜率 |
|---|---:|---:|---:|---:|---:|---:|
| 当前版本 | 1001.9285 | 699.3285 | 231.11% | 0% | 72 | 100% |
| 候选版本 | 2609.1109 | 2306.5109 | 762.23% | 0% | 71 | 100% |

## 差异解读

- 收益变化：1607.1824 USDT
- 收益率变化：531.12 pct
- 最大回撤变化：0 pct
- 交易数变化：-1

## 修改点摘要

- 止损相关逻辑有改动
- 仓位或加仓逻辑有改动
- 保护机制有改动

## 风险点

- Stoploss logic changed [high]
- Stake sizing logic changed [medium]
- Protection logic changed [medium]

## 建议

- 如果你现在账户里有持仓，先不要直接替换策略文件。
- 先看 diff.patch 里是否动到了止损、出场、仓位相关代码。
- 如果本次结论是“可考虑更新”，也建议先空仓切换，或者先用模拟盘观察一轮。

## 文件位置

- 中文结论：D:\test\real_trade\user_data\reviews\20260422_124252\review.zh-CN.md
- 英文明细：D:\test\real_trade\user_data\reviews\20260422_124252\review.md
- 原始 diff：D:\test\real_trade\user_data\reviews\20260422_124252\diff.patch
- 当前策略回测：D:\test\real_trade\user_data\reviews\20260422_124252\backtests\current\backtest-result-2026-04-22_04-46-09.zip
- 候选策略回测：D:\test\real_trade\user_data\reviews\20260422_124252\backtests\candidate\backtest-result-2026-04-22_04-49-40.zip
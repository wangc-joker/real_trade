# 策略评审结论

## 总结

- 生成时间：2026-04-23 09:29:17 +08:00
- 回测区间：20251020-20260420
- 上游 commit id：ea83d5d6a5cf27a145b3a7732bb6f4e32df80f0a
- 当前 commit id：560a9afe71efcf4fd59a229dcb436a6e27b32131
- 结论：需要人工复核后再决定是否更新

## 核心对比

| 策略 | 最终资金 | 绝对收益 | 收益率 | 最大回撤 | 交易数 | 胜率 |
|---|---:|---:|---:|---:|---:|---:|
| 当前版本 | 1001.9285 | 699.3285 | 231.11% | 0% | 72 | 100% |
| 候选版本 | 2543.0079 | 2240.4079 | 740.39% | 0% | 70 | 100% |

## 差异解读

- 收益变化：1541.0793 USDT
- 收益率变化：509.28 pct
- 最大回撤变化：0 pct
- 交易数变化：-2

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

- 中文结论：D:\test\real_trade\user_data\reviews\20260423_092140\review.zh-CN.md
- 英文明细：D:\test\real_trade\user_data\reviews\20260423_092140\review.md
- 原始 diff：D:\test\real_trade\user_data\reviews\20260423_092140\diff.patch
- 当前策略回测：D:\test\real_trade\user_data\reviews\20260423_092140\backtests\current\backtest-result-2026-04-23_01-25-37.zip
- 候选策略回测：D:\test\real_trade\user_data\reviews\20260423_092140\backtests\candidate\backtest-result-2026-04-23_01-29-14.zip
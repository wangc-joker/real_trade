# real_trade

This repository contains only the files needed to run the live `nfi_dynamic_top40_302u_max2` bot and to review weekly strategy updates from the upstream `NostalgiaForInfinity` project.

The default live pair update path now uses the balanced dynamic Top40 rules.

## Included

- Live config template for `NostalgiaForInfinityX7`
- Balanced Dynamic Top40 update script using a `core + satellite` liquidity model as the default live pair source
- Stable Dynamic Top40 update script kept for comparison and rollback
- Live start / status / recovery scripts
- Weekly upstream sync and review script
- Review backtest config used to compare current vs candidate strategy

## Not committed

- Exchange API keys and secrets
- Runtime config with injected secrets
- Review artifacts and logs

## Expected local secure file

By default the scripts look for:

`D:\work\secure\secret_bin.json`

Suggested structure:

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

## Main entry points

- Start live bot: [scripts/start_nfi_dynamic_top40_302u_max2_live.cmd](/D:/test/real_trade/scripts/start_nfi_dynamic_top40_302u_max2_live.cmd)
- Show live status: [scripts/show_nfi_dynamic_top40_302u_max2_live_status.cmd](/D:/test/real_trade/scripts/show_nfi_dynamic_top40_302u_max2_live_status.cmd)
- Auto recovery: [scripts/auto_recover_nfi_dynamic_top40_302u_max2_live.cmd](/D:/test/real_trade/scripts/auto_recover_nfi_dynamic_top40_302u_max2_live.cmd)
- Review upstream strategy: [scripts/review_upstream_nfi_strategy.cmd](/D:/test/real_trade/scripts/review_upstream_nfi_strategy.cmd)

See [docs/live_setup.md](/D:/test/real_trade/docs/live_setup.md) and [docs/strategy_sync_review.md](/D:/test/real_trade/docs/strategy_sync_review.md).

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

$repoRoot = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $repoRoot "user_data\config.live.nfi.dynamic.top40.302u.max2.runtime.json"
$balancedPairsPath = Join-Path $repoRoot "user_data\generated\pairs.dynamic.top40.302u.balanced.json"

if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
    throw "Runtime config not found: $configPath"
}

$runtimeConfig = Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json
$baseUrl = "http://127.0.0.1:8084"
$username = $runtimeConfig.api_server.username
$password = $runtimeConfig.api_server.password

$auth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${username}:${password}"))
$headers = @{ Authorization = "Basic $auth" }

function Invoke-WithRetry {
    param([string]$Uri)

    for ($i = 0; $i -lt 5; $i++) {
        try {
            return Invoke-RestMethod -Headers $headers -Uri $Uri
        }
        catch {
            if ($i -eq 4) {
                throw
            }
            Start-Sleep -Seconds 2
        }
    }
}

$config = Invoke-WithRetry "$baseUrl/api/v1/show_config"
$profit = Invoke-WithRetry "$baseUrl/api/v1/profit"
$status = Invoke-WithRetry "$baseUrl/api/v1/status"
$trades = Invoke-WithRetry "$baseUrl/api/v1/trades"
$balance = Invoke-WithRetry "$baseUrl/api/v1/balance"

$openCount = @($status).Count
$recentTrades = @($trades) | Sort-Object close_date -Descending | Select-Object -First 5
$currencies = @($balance.currencies) | Select-Object currency, free, used, balance, bot_owned, est_stake
$pairCount = @($config.exchange.pair_whitelist).Count
$pairSource = if (Test-Path -LiteralPath $balancedPairsPath -PathType Leaf) { "Balanced Dynamic Top40" } else { "Dynamic Top40" }

Write-Host ""
Write-Host "NFI Dynamic Top40 302.6U Max2 Live Status" -ForegroundColor Cyan
Write-Host "----------------------------------------"
Write-Host ("Bot Name       : {0}" -f $config.bot_name)
Write-Host ("Strategy       : {0}" -f $config.strategy)
Write-Host ("Run Mode       : {0}" -f $config.runmode)
Write-Host ("State          : {0}" -f $config.state)
Write-Host ("Pair Source    : {0}" -f $pairSource)
Write-Host ("Pairs Loaded   : {0}" -f $pairCount)
Write-Host ("Open Trades    : {0}" -f $openCount)
Write-Host ("Trade Count    : {0}" -f $profit.trade_count)
Write-Host ("Closed Trades  : {0}" -f $profit.closed_trade_count)
Write-Host ("Closed Profit  : {0} USDT" -f ([math]::Round([double]$profit.profit_closed_coin, 4)))
Write-Host ("Total Profit   : {0} USDT" -f ([math]::Round([double]$profit.profit_all_coin, 4)))

Write-Host ""
Write-Host "Account Balance" -ForegroundColor Cyan
Write-Host "----------------------------------------"
Write-Host ("Total Equity   : {0} {1}" -f ([math]::Round([double]$balance.total, 6)), $balance.stake)
Write-Host ("Bot Equity     : {0} {1}" -f ([math]::Round([double]$balance.total_bot, 6)), $balance.stake)
if (@($currencies).Count -gt 0) {
    $currencies | Format-Table -AutoSize
}
else {
    Write-Host "No balance rows returned."
}

Write-Host ""
Write-Host "Open Positions" -ForegroundColor Cyan
Write-Host "----------------------------------------"
if ($openCount -eq 0) {
    Write-Host "No open positions."
}
else {
    @($status) |
        Select-Object pair, is_short, amount, open_rate, current_rate, profit_pct, profit_abs |
        Format-Table -AutoSize
}

Write-Host ""
Write-Host "Recent Closed Trades" -ForegroundColor Cyan
Write-Host "----------------------------------------"
if (@($recentTrades).Count -eq 0) {
    Write-Host "No completed trades yet."
}
else {
    @($recentTrades) |
        Select-Object pair, is_short, enter_tag, exit_reason, profit_pct, profit_abs, close_date |
        Format-Table -AutoSize
}

Write-Host ""
Read-Host "Press Enter to close"

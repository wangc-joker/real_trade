[CmdletBinding()]
param(
    [string]$UpstreamRepoRoot = "D:\test\NostalgiaForInfinity",
    [string]$Timerange,
    [string]$DataDir = "D:\test\ft_userdata\user_data\data\binance",
    [switch]$SkipPull
)

[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$currentStrategyPath = Join-Path $repoRoot "user_data\strategies\NostalgiaForInfinityX7.py"
$reviewConfigPath = Join-Path $repoRoot "user_data\config.backtest.review.nfi.top40.302u.max2.json"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$reviewRoot = Join-Path $repoRoot ("user_data\reviews\{0}" -f $timestamp)
$currentDir = Join-Path $reviewRoot "current"
$candidateDir = Join-Path $reviewRoot "candidate"
$backtestRoot = Join-Path $reviewRoot "backtests"
$currentBacktestDir = Join-Path $backtestRoot "current"
$candidateBacktestDir = Join-Path $backtestRoot "candidate"
$candidateStrategyPath = Join-Path $UpstreamRepoRoot "NostalgiaForInfinityX7.py"
$diffPatchPath = Join-Path $reviewRoot "diff.patch"
$diffStatPath = Join-Path $reviewRoot "diff.stat.txt"
$reviewJsonPath = Join-Path $reviewRoot "review.json"
$reviewMdPath = Join-Path $reviewRoot "review.md"
$reviewZhPath = Join-Path $reviewRoot "review.zh-CN.md"
$pullLogPath = Join-Path $reviewRoot "upstream_pull.log"
$repoDataDir = Join-Path $repoRoot "user_data\data\binance"

function Run-LoggedCommand {
    param(
        [string]$FilePath,
        [string[]]$ArgumentList,
        [string]$WorkingDirectory,
        [string]$StdoutPath,
        [string]$StderrPath
    )

    $process = Start-Process -FilePath $FilePath `
        -ArgumentList $ArgumentList `
        -WorkingDirectory $WorkingDirectory `
        -NoNewWindow `
        -PassThru `
        -Wait `
        -RedirectStandardOutput $StdoutPath `
        -RedirectStandardError $StderrPath

    return $process.ExitCode
}

function Get-LatestBacktestSummary {
    param([string]$BacktestDir)

    $lastResultPath = Join-Path $BacktestDir ".last_result.json"
    if (-not (Test-Path -LiteralPath $lastResultPath -PathType Leaf)) {
        throw "Backtest result marker not found: $lastResultPath"
    }

    $lastResult = Get-Content -Raw -LiteralPath $lastResultPath | ConvertFrom-Json
    $zipPath = Join-Path $BacktestDir $lastResult.latest_backtest
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
        $jsonEntry = $zip.Entries | Where-Object {
            $_.FullName -like "*.json" -and $_.FullName -notlike "*_config.json"
        } | Select-Object -First 1

        if (-not $jsonEntry) {
            throw "Backtest JSON not found in $zipPath"
        }

        $reader = New-Object System.IO.StreamReader($jsonEntry.Open())
        try {
            $payload = $reader.ReadToEnd() | ConvertFrom-Json
        }
        finally {
            $reader.Close()
        }
    }
    finally {
        $zip.Dispose()
    }

    $strategyName = ($payload.strategy.PSObject.Properties | Select-Object -First 1).Name
    $stats = $payload.strategy.$strategyName

    return [pscustomobject]@{
        strategy_name = $strategyName
        final_balance = [double]$stats.final_balance
        profit_total_abs = [double]$stats.profit_total_abs
        profit_total_pct = [double]$stats.profit_total * 100.0
        cagr = [double]$stats.cagr * 100.0
        max_relative_drawdown = [double]$stats.max_relative_drawdown * 100.0
        max_drawdown_abs = [double]$stats.max_drawdown_abs
        total_trades = [int]$stats.total_trades
        winrate = [double]$stats.winrate * 100.0
        backtest_start = [string]$stats.backtest_start
        backtest_end = [string]$stats.backtest_end
        timerange = [string]$stats.timerange
        zip_path = $zipPath
    }
}

function Try-GetGitHead {
    param([string]$RepoPath)

    try {
        $value = (& git -C $RepoPath rev-parse HEAD 2>$null).Trim()
        if ([string]::IsNullOrWhiteSpace($value)) {
            return $null
        }
        return $value
    }
    catch {
        return $null
    }
}

function Get-StrategyFileSha256 {
    param([string]$Path)

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Get-DataAlignedTimerange {
    param(
        [string]$RepoRoot,
        [string]$ConfigPath
    )

    $config = Get-Content -Raw -LiteralPath $ConfigPath | ConvertFrom-Json
    $pairs = @($config.exchange.pair_whitelist)
    if (@($pairs).Count -eq 0) {
        throw "Review config does not contain pair_whitelist."
    }

    $tempScriptPath = Join-Path $RepoRoot "user_data\runtime\resolve_review_end_date.py"
    $pythonCode = @'
import json
from pathlib import Path
import pandas as pd

config_path = Path("/freqtrade/user_data/config.backtest.review.nfi.top40.302u.max2.json")
data_root = Path("/freqtrade/user_data/data/binance/futures")

config = json.loads(config_path.read_text(encoding="utf-8"))
pairs = config["exchange"]["pair_whitelist"]

def pair_to_filename(pair: str) -> str:
    return pair.replace("/", "_").replace(":", "_") + "-5m-futures.feather"

last_dates = []
for pair in pairs:
    file_path = data_root / pair_to_filename(pair)
    if not file_path.exists():
        continue
    df = pd.read_feather(file_path)
    if df.empty:
        continue
    last_dates.append(pd.to_datetime(df.iloc[-1]["date"], utc=True))

if not last_dates:
    raise SystemExit("NO_DATA")

aligned_end = min(last_dates).date()
print(aligned_end.isoformat())
'@
    [System.IO.File]::WriteAllText($tempScriptPath, $pythonCode, [System.Text.UTF8Encoding]::new($false))

    try {
        $raw = & docker compose run --rm --entrypoint python freqtrade /freqtrade/user_data/runtime/resolve_review_end_date.py
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to resolve local-data end date."
        }
        $lines = @($raw | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        $dateLine = $lines | Where-Object { $_ -match '^\d{4}-\d{2}-\d{2}$' } | Select-Object -Last 1
        if ([string]::IsNullOrWhiteSpace($dateLine)) {
            throw "Could not parse aligned end date from docker output."
        }

        $endDate = [datetime]::ParseExact($dateLine, "yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture)
        $startDate = $endDate.AddMonths(-6)
        return "{0}-{1}" -f $startDate.ToString("yyyyMMdd"), $endDate.ToString("yyyyMMdd")
    }
    finally {
        if (Test-Path -LiteralPath $tempScriptPath) {
            Remove-Item -LiteralPath $tempScriptPath -Force
        }
    }
}

function Get-RiskSignals {
    param([string]$DiffText)

    $rules = @(
        @{ pattern = 'stoploss|custom_stoploss'; label = 'Stoploss logic changed'; level = 'high' },
        @{ pattern = 'custom_exit|exit_reason|confirm_trade_exit'; label = 'Exit logic changed'; level = 'high' },
        @{ pattern = 'confirm_trade_entry|populate_entry'; label = 'Entry logic changed'; level = 'high' },
        @{ pattern = 'minimal_roi|trailing_stop|trailing_stop_positive'; label = 'ROI or trailing rules changed'; level = 'medium' },
        @{ pattern = 'grind_mode_coins|top_coins_mode_coins|pair_whitelist'; label = 'Coin selection logic changed'; level = 'medium' },
        @{ pattern = 'rebuy|rapid|stake|custom_stake'; label = 'Stake sizing logic changed'; level = 'medium' },
        @{ pattern = 'slippage|order_book|confirm_trade'; label = 'Execution behavior changed'; level = 'medium' },
        @{ pattern = 'protections|Cooldown|MaxDrawdown'; label = 'Protection logic changed'; level = 'medium' }
    )

    $matches = foreach ($rule in $rules) {
        if ($DiffText -match $rule.pattern) {
            [pscustomobject]@{
                label = $rule.label
                level = $rule.level
            }
        }
    }

    return @($matches)
}

function Get-Recommendation {
    param(
        [pscustomobject]$CurrentStats,
        [pscustomobject]$CandidateStats,
        [object[]]$RiskSignals
    )

    $profitRatio = if ($CurrentStats.profit_total_abs -eq 0) { 0 } else { $CandidateStats.profit_total_abs / $CurrentStats.profit_total_abs }
    $tradeRatio = if ($CurrentStats.total_trades -eq 0) { 0 } else { $CandidateStats.total_trades / $CurrentStats.total_trades }
    $highRiskCount = @($RiskSignals | Where-Object { $_.level -eq "high" }).Count

    if ($CandidateStats.max_relative_drawdown -gt 10.0) {
        return "keep_current"
    }
    if ($profitRatio -lt 0.8) {
        return "keep_current"
    }
    if ($tradeRatio -lt 0.8) {
        return "review_manually"
    }
    if ($highRiskCount -gt 0) {
        return "review_manually"
    }
    if ($CandidateStats.profit_total_abs -ge $CurrentStats.profit_total_abs) {
        return "candidate_looks_safe"
    }

    return "review_manually"
}

function Get-RecommendationChinese {
    param([string]$Recommendation)

    switch ($Recommendation) {
        "keep_current" { return "保留当前策略，不建议更新" }
        "review_manually" { return "需要人工复核后再决定是否更新" }
        "candidate_looks_safe" { return "候选策略表现稳定，可考虑更新" }
        default { return $Recommendation }
    }
}

function Get-ChangeSummaryChinese {
    param([string]$DiffText)

    $items = @()
    if ($DiffText -match 'stoploss|custom_stoploss') { $items += "止损相关逻辑有改动" }
    if ($DiffText -match 'custom_exit|exit_reason|confirm_trade_exit') { $items += "出场逻辑有改动" }
    if ($DiffText -match 'confirm_trade_entry|populate_entry') { $items += "入场逻辑有改动" }
    if ($DiffText -match 'minimal_roi|trailing_stop|trailing_stop_positive') { $items += "止盈或跟踪止盈规则有改动" }
    if ($DiffText -match 'grind_mode_coins|top_coins_mode_coins|pair_whitelist') { $items += "币种或模式分组有改动" }
    if ($DiffText -match 'rebuy|rapid|stake|custom_stake') { $items += "仓位或加仓逻辑有改动" }
    if ($DiffText -match 'slippage|order_book|confirm_trade') { $items += "执行与成交确认逻辑有改动" }
    if ($DiffText -match 'protections|Cooldown|MaxDrawdown') { $items += "保护机制有改动" }

    if (@($items).Count -eq 0) {
        return @("没有命中预设的高敏感改动关键词，可能是注释、小参数或局部实现调整。")
    }

    return $items
}

function Get-CommitLineChinese {
    param(
        [string]$UpstreamCommitId,
        [string]$CurrentCommitId,
        [string]$CurrentStrategySha256
    )

    if (-not [string]::IsNullOrWhiteSpace($CurrentCommitId)) {
        return "- 当前 commit id：$CurrentCommitId"
    }

    return "- 当前 commit id：当前仓库暂无 commit，策略文件 SHA256：$CurrentStrategySha256"
}

if (-not (Test-Path -LiteralPath $currentStrategyPath -PathType Leaf)) {
    throw "Current strategy not found: $currentStrategyPath"
}
if (-not (Test-Path -LiteralPath $candidateStrategyPath -PathType Leaf)) {
    throw "Upstream strategy not found: $candidateStrategyPath"
}
if (-not (Test-Path -LiteralPath $reviewConfigPath -PathType Leaf)) {
    throw "Review config not found: $reviewConfigPath"
}
if (-not (Test-Path -LiteralPath $DataDir -PathType Container)) {
    throw "Data directory not found: $DataDir"
}

New-Item -ItemType Directory -Force -Path $currentDir, $candidateDir, $currentBacktestDir, $candidateBacktestDir | Out-Null
New-Item -ItemType Directory -Force -Path $repoDataDir | Out-Null

Write-Host "Syncing backtest data into real_trade workspace..." -ForegroundColor Cyan
& robocopy $DataDir $repoDataDir /E /NFL /NDL /NJH /NJS /NC /NS | Out-Null
$robocopyExit = $LASTEXITCODE
if ($robocopyExit -ge 8) {
    throw "robocopy failed while syncing data. Exit code: $robocopyExit"
}

if ([string]::IsNullOrWhiteSpace($Timerange)) {
    $Timerange = Get-DataAlignedTimerange -RepoRoot $repoRoot -ConfigPath $reviewConfigPath
}

if (-not $SkipPull) {
    $pullOut = Join-Path $reviewRoot "pull.stdout.log"
    $pullErr = Join-Path $reviewRoot "pull.stderr.log"
    $pullExit = Run-LoggedCommand -FilePath "git" -ArgumentList @("pull", "--ff-only") -WorkingDirectory $UpstreamRepoRoot -StdoutPath $pullOut -StderrPath $pullErr
    if ($pullExit -ne 0) {
        "git pull exit code: $pullExit" | Set-Content -LiteralPath $pullLogPath -Encoding UTF8
        if (Test-Path -LiteralPath $pullOut) { Get-Content -LiteralPath $pullOut | Add-Content -LiteralPath $pullLogPath -Encoding UTF8 }
        if (Test-Path -LiteralPath $pullErr) { Get-Content -LiteralPath $pullErr | Add-Content -LiteralPath $pullLogPath -Encoding UTF8 }
    }
}

Copy-Item -LiteralPath $currentStrategyPath -Destination (Join-Path $currentDir "NostalgiaForInfinityX7.py") -Force
Copy-Item -LiteralPath $candidateStrategyPath -Destination (Join-Path $candidateDir "NostalgiaForInfinityX7.py") -Force

$patchOut = Join-Path $reviewRoot "gitdiff.stdout.log"
$patchErr = Join-Path $reviewRoot "gitdiff.stderr.log"
Run-LoggedCommand -FilePath "git" -ArgumentList @("--no-pager", "diff", "--no-index", "--", $currentStrategyPath, $candidateStrategyPath) -WorkingDirectory $repoRoot -StdoutPath $diffPatchPath -StderrPath $patchErr | Out-Null
Run-LoggedCommand -FilePath "git" -ArgumentList @("--no-pager", "diff", "--no-index", "--stat", "--", $currentStrategyPath, $candidateStrategyPath) -WorkingDirectory $repoRoot -StdoutPath $diffStatPath -StderrPath $patchErr | Out-Null

$currentOut = Join-Path $currentBacktestDir "stdout.log"
$currentErr = Join-Path $currentBacktestDir "stderr.log"
$candidateOut = Join-Path $candidateBacktestDir "stdout.log"
$candidateErr = Join-Path $candidateBacktestDir "stderr.log"

$currentExit = Run-LoggedCommand -FilePath "docker" `
    -ArgumentList @(
        "compose", "run", "--rm", "freqtrade",
        "backtesting",
        "--config", "/freqtrade/user_data/config.backtest.review.nfi.top40.302u.max2.json",
        "--strategy", "NostalgiaForInfinityX7",
        "--strategy-path", ("/freqtrade/user_data/reviews/{0}/current" -f $timestamp),
        "--timerange", $Timerange,
        "--datadir", "/freqtrade/user_data/data/binance",
        "--cache", "none",
        "--backtest-directory", ("/freqtrade/user_data/reviews/{0}/backtests/current" -f $timestamp),
        "--export", "trades"
    ) `
    -WorkingDirectory $repoRoot `
    -StdoutPath $currentOut `
    -StderrPath $currentErr

if ($currentExit -ne 0) {
    throw "Current strategy backtest failed with exit code $currentExit"
}

$candidateExit = Run-LoggedCommand -FilePath "docker" `
    -ArgumentList @(
        "compose", "run", "--rm", "freqtrade",
        "backtesting",
        "--config", "/freqtrade/user_data/config.backtest.review.nfi.top40.302u.max2.json",
        "--strategy", "NostalgiaForInfinityX7",
        "--strategy-path", ("/freqtrade/user_data/reviews/{0}/candidate" -f $timestamp),
        "--timerange", $Timerange,
        "--datadir", "/freqtrade/user_data/data/binance",
        "--cache", "none",
        "--backtest-directory", ("/freqtrade/user_data/reviews/{0}/backtests/candidate" -f $timestamp),
        "--export", "trades"
    ) `
    -WorkingDirectory $repoRoot `
    -StdoutPath $candidateOut `
    -StderrPath $candidateErr

if ($candidateExit -ne 0) {
    throw "Candidate strategy backtest failed with exit code $candidateExit"
}

$currentStats = Get-LatestBacktestSummary -BacktestDir $currentBacktestDir
$candidateStats = Get-LatestBacktestSummary -BacktestDir $candidateBacktestDir
$diffText = if (Test-Path -LiteralPath $diffPatchPath) { Get-Content -Raw -LiteralPath $diffPatchPath } else { "" }
$riskSignals = Get-RiskSignals -DiffText $diffText
$recommendation = Get-Recommendation -CurrentStats $currentStats -CandidateStats $candidateStats -RiskSignals $riskSignals
$recommendationZh = Get-RecommendationChinese -Recommendation $recommendation
$changeSummaryZh = Get-ChangeSummaryChinese -DiffText $diffText
$upstreamCommitId = Try-GetGitHead -RepoPath $UpstreamRepoRoot
$currentRepoCommitId = Try-GetGitHead -RepoPath $repoRoot
$currentStrategySha256 = Get-StrategyFileSha256 -Path $currentStrategyPath

$profitDeltaAbs = $candidateStats.profit_total_abs - $currentStats.profit_total_abs
$profitDeltaPct = $candidateStats.profit_total_pct - $currentStats.profit_total_pct
$drawdownDeltaPct = $candidateStats.max_relative_drawdown - $currentStats.max_relative_drawdown
$tradeDelta = $candidateStats.total_trades - $currentStats.total_trades

$review = [pscustomobject]@{
    generated_at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss zzz")
    timerange = $Timerange
    upstream_repo = $UpstreamRepoRoot
    review_root = $reviewRoot
    upstream_commit_id = $upstreamCommitId
    current_repo_commit_id = $currentRepoCommitId
    current_strategy_sha256 = $currentStrategySha256
    current = $currentStats
    candidate = $candidateStats
    risk_signals = @($riskSignals)
    recommendation = $recommendation
    recommendation_zh = $recommendationZh
}

[System.IO.File]::WriteAllText(
    $reviewJsonPath,
    ($review | ConvertTo-Json -Depth 16),
    [System.Text.UTF8Encoding]::new($false)
)

$riskLines = if (@($riskSignals).Count -eq 0) {
    "- no automatic risk keywords matched"
}
else {
    @($riskSignals) | ForEach-Object { "- {0} ({1})" -f $_.label, $_.level }
}

$reviewMarkdown = @"
# Strategy Review

## Summary

- Generated at: $($review.generated_at)
- Timerange: $Timerange
- Upstream commit id: $upstreamCommitId
- Current repo commit id: $currentRepoCommitId
- Current strategy SHA256: $currentStrategySha256
- Recommendation: `$recommendation`

## Backtest Comparison

| Strategy | Final Balance | Profit | Profit % | Max Drawdown % | Trades | Winrate % |
|---|---:|---:|---:|---:|---:|---:|
| Current | $([math]::Round($currentStats.final_balance, 4)) | $([math]::Round($currentStats.profit_total_abs, 4)) | $([math]::Round($currentStats.profit_total_pct, 2)) | $([math]::Round($currentStats.max_relative_drawdown, 2)) | $($currentStats.total_trades) | $([math]::Round($currentStats.winrate, 2)) |
| Candidate | $([math]::Round($candidateStats.final_balance, 4)) | $([math]::Round($candidateStats.profit_total_abs, 4)) | $([math]::Round($candidateStats.profit_total_pct, 2)) | $([math]::Round($candidateStats.max_relative_drawdown, 2)) | $($candidateStats.total_trades) | $([math]::Round($candidateStats.winrate, 2)) |

## Risk Signals

$($riskLines -join "`r`n")

## Files

- Diff stat: $diffStatPath
- Diff patch: $diffPatchPath
- Current backtest: $($currentStats.zip_path)
- Candidate backtest: $($candidateStats.zip_path)
"@

[System.IO.File]::WriteAllText(
    $reviewMdPath,
    $reviewMarkdown,
    [System.Text.UTF8Encoding]::new($false)
)

$riskLinesZh = if (@($riskSignals).Count -eq 0) {
    "- 未命中预设高风险关键词"
}
else {
    @($riskSignals) | ForEach-Object { "- $($_.label) [$($_.level)]" }
}

$changeSummaryLinesZh = @($changeSummaryZh) | ForEach-Object { "- $_" }
$currentCommitLineZh = Get-CommitLineChinese -UpstreamCommitId $upstreamCommitId -CurrentCommitId $currentRepoCommitId -CurrentStrategySha256 $currentStrategySha256

$reviewZhMarkdown = @"
# 策略评审结论

## 总结

- 生成时间：$($review.generated_at)
- 回测区间：$Timerange
- 上游 commit id：$upstreamCommitId
$currentCommitLineZh
- 结论：$recommendationZh

## 核心对比

| 策略 | 最终资金 | 绝对收益 | 收益率 | 最大回撤 | 交易数 | 胜率 |
|---|---:|---:|---:|---:|---:|---:|
| 当前版本 | $([math]::Round($currentStats.final_balance, 4)) | $([math]::Round($currentStats.profit_total_abs, 4)) | $([math]::Round($currentStats.profit_total_pct, 2))% | $([math]::Round($currentStats.max_relative_drawdown, 2))% | $($currentStats.total_trades) | $([math]::Round($currentStats.winrate, 2))% |
| 候选版本 | $([math]::Round($candidateStats.final_balance, 4)) | $([math]::Round($candidateStats.profit_total_abs, 4)) | $([math]::Round($candidateStats.profit_total_pct, 2))% | $([math]::Round($candidateStats.max_relative_drawdown, 2))% | $($candidateStats.total_trades) | $([math]::Round($candidateStats.winrate, 2))% |

## 差异解读

- 收益变化：$([math]::Round($profitDeltaAbs, 4)) USDT
- 收益率变化：$([math]::Round($profitDeltaPct, 2)) pct
- 最大回撤变化：$([math]::Round($drawdownDeltaPct, 2)) pct
- 交易数变化：$tradeDelta

## 修改点摘要

$($changeSummaryLinesZh -join "`r`n")

## 风险点

$($riskLinesZh -join "`r`n")

## 建议

- 如果你现在账户里有持仓，先不要直接替换策略文件。
- 先看 `diff.patch` 里是否动到了止损、出场、仓位相关代码。
- 如果本次结论是“可考虑更新”，也建议先空仓切换，或者先用模拟盘观察一轮。

## 文件位置

- 中文结论：$reviewZhPath
- 英文明细：$reviewMdPath
- 原始 diff：$diffPatchPath
- 当前策略回测：$($currentStats.zip_path)
- 候选策略回测：$($candidateStats.zip_path)
"@

[System.IO.File]::WriteAllText(
    $reviewZhPath,
    $reviewZhMarkdown,
    [System.Text.UTF8Encoding]::new($false)
)

Write-Host ""
Write-Host "Strategy review completed." -ForegroundColor Green
Write-Host ("Review folder   : {0}" -f $reviewRoot)
Write-Host ("Recommendation  : {0}" -f $recommendation)
Write-Host ("RecommendationZH: {0}" -f $recommendationZh)
Write-Host ("Current profit  : {0}" -f ([math]::Round($currentStats.profit_total_abs, 4)))
Write-Host ("Candidate profit: {0}" -f ([math]::Round($candidateStats.profit_total_abs, 4)))

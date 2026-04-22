$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

$repoRoot = Split-Path -Parent $PSScriptRoot
$pairsPath = Join-Path $repoRoot "user_data\generated\pairs.dynamic.top40.302u.balanced.json"
$reportPath = Join-Path $repoRoot "user_data\generated\pairs.dynamic.top40.302u.balanced.report.json"

$targetCount = 30
$coreTargetCount = 21
$satelliteTargetCount = $targetCount - $coreTargetCount
$quoteAsset = "USDT"
$excludedSuffixes = @("BULL", "BEAR", "UP", "DOWN")
$excludedBaseAssets = @("XAU", "XAG", "XAUT", "PAXG", "TSLA")

$coreRule = @{
    minimumListingDays = 60
    minimumAverageDailyQuoteVolume = 12000000
    minimumMedianDailyQuoteVolume = 10000000
    minimumQualifiedDays = 20
    minimumQualifiedDayQuoteVolume = 10000000
    maximumSpikeToMedianRatio = 4.0
}

$satelliteRule = @{
    minimumListingDays = 45
    minimumAverageDailyQuoteVolume = 8000000
    minimumMedianDailyQuoteVolume = 6000000
    minimumQualifiedDays = 14
    minimumQualifiedDayQuoteVolume = 7000000
    maximumSpikeToMedianRatio = 6.0
}

function Get-Json {
    param([string]$Uri)
    Invoke-RestMethod -Uri $Uri -Method Get -TimeoutSec 60
}

function Get-DailyQuoteVolumeStats30d {
    param([string]$Symbol)

    $uri = "https://fapi.binance.com/fapi/v1/klines?symbol=$Symbol&interval=1d&limit=30"
    $klines = Get-Json $uri
    if (-not $klines -or @($klines).Count -eq 0) {
        return $null
    }

    $values = foreach ($kline in $klines) {
        [double]$kline[7]
    }

    if (@($values).Count -eq 0) {
        return $null
    }

    $sortedValues = @($values | Sort-Object)
    $count = $sortedValues.Count
    if ($count % 2 -eq 1) {
        $median = [double]$sortedValues[[int][math]::Floor($count / 2)]
    }
    else {
        $upper = [double]$sortedValues[$count / 2]
        $lower = [double]$sortedValues[($count / 2) - 1]
        $median = ($lower + $upper) / 2.0
    }

    $average = [double](($values | Measure-Object -Average).Average)
    $maxValue = [double](($values | Measure-Object -Maximum).Maximum)

    return [pscustomobject]@{
        average = $average
        median = [double]$median
        maxValue = $maxValue
        values = @($values)
        sampleDays = [int]$count
    }
}

function Get-LiquidityMetrics {
    param(
        [pscustomobject]$DailyStats,
        [hashtable]$Rule
    )

    $qualifiedDays = @($DailyStats.values | Where-Object { $_ -ge $Rule.minimumQualifiedDayQuoteVolume }).Count
    $spikeToMedianRatio = if ($DailyStats.median -gt 0) { $DailyStats.maxValue / $DailyStats.median } else { [double]::PositiveInfinity }

    return [pscustomobject]@{
        qualifiedDays = [int]$qualifiedDays
        spikeToMedianRatio = [double]$spikeToMedianRatio
    }
}

function Test-EligibleSymbol {
    param(
        [string]$BaseAsset,
        [string]$Status,
        [string]$ContractType,
        [string]$QuoteAsset,
        [object]$OnboardDate,
        [int]$MinimumListingDays
    )

    if ($QuoteAsset -ne "USDT") { return $false }
    if ($Status -ne "TRADING") { return $false }
    if ($ContractType -ne "PERPETUAL") { return $false }
    if ([string]::IsNullOrWhiteSpace($BaseAsset)) { return $false }
    if ($BaseAsset -notmatch '^[A-Z0-9]+$') { return $false }
    if ($excludedBaseAssets -contains $BaseAsset) { return $false }
    if ($BaseAsset -like '1000*') { return $false }

    foreach ($suffix in $excludedSuffixes) {
        if ($BaseAsset.EndsWith($suffix, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $false
        }
    }

    if (-not $OnboardDate) { return $false }

    $listedAt = [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$OnboardDate)
    $listedDays = ((Get-Date).ToUniversalTime() - $listedAt.UtcDateTime).TotalDays
    if ($listedDays -lt $MinimumListingDays) { return $false }

    return $true
}

function Test-LiquidityRule {
    param(
        [pscustomobject]$Item,
        [hashtable]$Rule
    )

    if ($Item.sampleDays30d -lt 30) { return $false }
    if ($Item.listed_days -lt $Rule.minimumListingDays) { return $false }
    if ($Item.avgDailyQuoteVolume30d -lt $Rule.minimumAverageDailyQuoteVolume) { return $false }
    if ($Item.medianDailyQuoteVolume30d -lt $Rule.minimumMedianDailyQuoteVolume) { return $false }
    if ($Item.qualifiedDays30d -lt $Rule.minimumQualifiedDays) { return $false }
    if ($Item.spikeToMedianRatio30d -gt $Rule.maximumSpikeToMedianRatio) { return $false }
    return $true
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $pairsPath) | Out-Null

$exchangeInfo = Get-Json "https://fapi.binance.com/fapi/v1/exchangeInfo"
$tickers = Get-Json "https://fapi.binance.com/fapi/v1/ticker/24hr"

$symbolMeta = @{}
foreach ($s in $exchangeInfo.symbols) {
    $symbolMeta[$s.symbol] = $s
}

$rankedItems = foreach ($ticker in $tickers) {
    $meta = $symbolMeta[$ticker.symbol]
    if (-not $meta) { continue }

    if (-not (Test-EligibleSymbol `
        -BaseAsset $meta.baseAsset `
        -Status $meta.status `
        -ContractType $meta.contractType `
        -QuoteAsset $meta.quoteAsset `
        -OnboardDate $meta.onboardDate `
        -MinimumListingDays $satelliteRule.minimumListingDays)) {
        continue
    }

    $dailyStats = Get-DailyQuoteVolumeStats30d -Symbol $ticker.symbol
    if (-not $dailyStats) { continue }

    $satelliteMetrics = Get-LiquidityMetrics -DailyStats $dailyStats -Rule $satelliteRule

    [pscustomobject]@{
        symbol = $ticker.symbol
        baseAsset = $meta.baseAsset
        pair = "{0}/{1}:{1}" -f $meta.baseAsset, $quoteAsset
        listed_days = [math]::Round((((Get-Date).ToUniversalTime() - [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$meta.onboardDate).UtcDateTime).TotalDays), 2)
        avgDailyQuoteVolume30d = [double]$dailyStats.average
        medianDailyQuoteVolume30d = [double]$dailyStats.median
        qualifiedDays30d = [int]$satelliteMetrics.qualifiedDays
        maxDailyQuoteVolume30d = [double]$dailyStats.maxValue
        spikeToMedianRatio30d = [double]$satelliteMetrics.spikeToMedianRatio
        sampleDays30d = [int]$dailyStats.sampleDays
        quoteVolume24h = [double]$ticker.quoteVolume
        quoteVolume = [double]$ticker.quoteVolume
        volume = [double]$ticker.volume
    }
}

$coreCandidates = @(
    $rankedItems |
        Where-Object { Test-LiquidityRule -Item $_ -Rule $coreRule } |
        Sort-Object avgDailyQuoteVolume30d -Descending
)

$satelliteCandidates = @(
    $rankedItems |
        Where-Object { Test-LiquidityRule -Item $_ -Rule $satelliteRule } |
        Sort-Object @{ Expression = 'medianDailyQuoteVolume30d'; Descending = $true }, @{ Expression = 'avgDailyQuoteVolume30d'; Descending = $true }
)

$coreSelected = @($coreCandidates | Select-Object -First $coreTargetCount)
$selectedMap = @{}
foreach ($item in $coreSelected) {
    $selectedMap[$item.pair] = $item
}

foreach ($item in $satelliteCandidates) {
    if ($selectedMap.ContainsKey($item.pair)) { continue }
    if ($selectedMap.Count -ge $targetCount) { break }
    $selectedMap[$item.pair] = $item
}

$selected = @($selectedMap.Values | Sort-Object avgDailyQuoteVolume30d -Descending)

if ($selected.Count -lt $targetCount) {
    foreach ($item in ($rankedItems | Sort-Object avgDailyQuoteVolume30d -Descending)) {
        if ($selectedMap.ContainsKey($item.pair)) { continue }
        $selectedMap[$item.pair] = $item
        if ($selectedMap.Count -ge $targetCount) { break }
    }
    $selected = @($selectedMap.Values | Sort-Object avgDailyQuoteVolume30d -Descending)
}

if ($selected.Count -eq 0) {
    throw "No eligible symbols passed the balanced dynamic Top40 filter."
}

[System.IO.File]::WriteAllText(
    $pairsPath,
    (@($selected.pair) | ConvertTo-Json -Depth 4),
    [System.Text.UTF8Encoding]::new($false)
)

$report = [pscustomobject]@{
    generated_at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss zzz")
    source = "Binance Futures 24h ticker quoteVolume"
    target_count = $targetCount
    core_target_count = $coreTargetCount
    satellite_target_count = $satelliteTargetCount
    core_eligible_count = $coreCandidates.Count
    satellite_eligible_count = $satelliteCandidates.Count
    selected_count = $selected.Count
    filter = [pscustomobject]@{
        quote_asset = $quoteAsset
        contract_type = "PERPETUAL"
        status = "TRADING"
        excluded_suffixes = $excludedSuffixes
        excluded_base_assets = $excludedBaseAssets
        core_rule = $coreRule
        satellite_rule = $satelliteRule
        selection_strategy = "Balanced Top40: select 28 core symbols with stable 30d liquidity, then fill up to 12 satellite symbols with moderately relaxed thresholds to keep some return elasticity without fully reverting to the old high-beta pool."
    }
    pairs = @($selected)
}

[System.IO.File]::WriteAllText(
    $reportPath,
    ($report | ConvertTo-Json -Depth 16),
    [System.Text.UTF8Encoding]::new($false)
)

Write-Host ""
Write-Host "Balanced Dynamic Top40 pairlist updated." -ForegroundColor Green
Write-Host ("Pairs  : {0}" -f $pairsPath)
Write-Host ("Report : {0}" -f $reportPath)
Write-Host ("Core eligible count: {0}" -f $coreCandidates.Count)
Write-Host ("Satellite eligible count: {0}" -f $satelliteCandidates.Count)
Write-Host ("Selected count: {0}" -f $selected.Count)
Write-Host ""
Write-Host "Selected pairs:" -ForegroundColor Cyan
@($selected.pair) | ForEach-Object { Write-Host $_ }

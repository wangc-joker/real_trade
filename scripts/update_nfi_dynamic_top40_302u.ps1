$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

$repoRoot = Split-Path -Parent $PSScriptRoot
$pairsPath = Join-Path $repoRoot "user_data\generated\pairs.dynamic.top40.302u.json"
$reportPath = Join-Path $repoRoot "user_data\generated\pairs.dynamic.top40.302u.report.json"

$targetCount = 40
$quoteAsset = "USDT"
$minimumListingDays = 60
$minimumAverageDailyQuoteVolume = 12000000
$minimumMedianDailyQuoteVolume = 10000000
$minimumQualifiedDays = 20
$minimumQualifiedDayQuoteVolume = 10000000
$maximumSpikeToMedianRatio = 4.0
$excludedSuffixes = @("BULL", "BEAR", "UP", "DOWN")
$excludedBaseAssets = @("XAU", "XAG", "XAUT", "PAXG", "TSLA")

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
    $qualifiedDays = @($values | Where-Object { $_ -ge $minimumQualifiedDayQuoteVolume }).Count
    $maxValue = [double](($values | Measure-Object -Maximum).Maximum)
    $spikeToMedianRatio = if ($median -gt 0) { $maxValue / $median } else { [double]::PositiveInfinity }

    return [pscustomobject]@{
        average = $average
        median = [double]$median
        qualifiedDays = [int]$qualifiedDays
        maxValue = $maxValue
        spikeToMedianRatio = [double]$spikeToMedianRatio
        sampleDays = [int]$count
    }
}

function Test-EligibleSymbol {
    param(
        [string]$BaseAsset,
        [string]$Status,
        [string]$ContractType,
        [string]$QuoteAsset,
        [object]$OnboardDate
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
    if ($listedDays -lt $minimumListingDays) { return $false }

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
        -OnboardDate $meta.onboardDate)) {
        continue
    }

    $dailyStats = Get-DailyQuoteVolumeStats30d -Symbol $ticker.symbol
    if (-not $dailyStats) { continue }

    [pscustomobject]@{
        symbol = $ticker.symbol
        baseAsset = $meta.baseAsset
        pair = "{0}/{1}:{1}" -f $meta.baseAsset, $quoteAsset
        listed_days = [math]::Round((((Get-Date).ToUniversalTime() - [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$meta.onboardDate).UtcDateTime).TotalDays), 2)
        avgDailyQuoteVolume30d = [double]$dailyStats.average
        medianDailyQuoteVolume30d = [double]$dailyStats.median
        qualifiedDays30d = [int]$dailyStats.qualifiedDays
        maxDailyQuoteVolume30d = [double]$dailyStats.maxValue
        spikeToMedianRatio30d = [double]$dailyStats.spikeToMedianRatio
        sampleDays30d = [int]$dailyStats.sampleDays
        quoteVolume24h = [double]$ticker.quoteVolume
        quoteVolume = [double]$ticker.quoteVolume
        volume = [double]$ticker.volume
    }
}

$eligibleByLiquidity = @(
    $rankedItems |
        Where-Object {
            $_.avgDailyQuoteVolume30d -ge $minimumAverageDailyQuoteVolume -and
            $_.medianDailyQuoteVolume30d -ge $minimumMedianDailyQuoteVolume -and
            $_.qualifiedDays30d -ge $minimumQualifiedDays -and
            $_.sampleDays30d -ge 30 -and
            $_.spikeToMedianRatio30d -le $maximumSpikeToMedianRatio
        } |
        Sort-Object avgDailyQuoteVolume30d -Descending
)

$selected = @($eligibleByLiquidity | Select-Object -First $targetCount)

if ($selected.Count -eq 0) {
    throw "No eligible symbols passed the 30d average daily quote-volume filter."
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
    eligible_count = $eligibleByLiquidity.Count
    selected_count = $selected.Count
    filter = [pscustomobject]@{
        quote_asset = $quoteAsset
        contract_type = "PERPETUAL"
        status = "TRADING"
        minimum_listing_days = $minimumListingDays
        minimum_average_daily_quote_volume_30d = $minimumAverageDailyQuoteVolume
        minimum_median_daily_quote_volume_30d = $minimumMedianDailyQuoteVolume
        minimum_qualified_days_30d = $minimumQualifiedDays
        minimum_qualified_day_quote_volume = $minimumQualifiedDayQuoteVolume
        maximum_spike_to_median_ratio_30d = $maximumSpikeToMedianRatio
        excluded_suffixes = $excludedSuffixes
        excluded_base_assets = $excludedBaseAssets
        selection_strategy = "Keep symbols with stable 30d liquidity: average >= threshold, median >= threshold, at least the minimum number of strong-volume days, and no extreme single-day spike dominance. Then sort by 30d average daily quote volume descending and take up to 40."
    }
    pairs = @($selected)
}

[System.IO.File]::WriteAllText(
    $reportPath,
    ($report | ConvertTo-Json -Depth 16),
    [System.Text.UTF8Encoding]::new($false)
)

Write-Host ""
Write-Host "Dynamic Top40 pairlist updated." -ForegroundColor Green
Write-Host ("Pairs  : {0}" -f $pairsPath)
Write-Host ("Report : {0}" -f $reportPath)
Write-Host ("Eligible count: {0}" -f $eligibleByLiquidity.Count)
Write-Host ("Selected count: {0}" -f $selected.Count)
Write-Host ""
Write-Host "Selected pairs:" -ForegroundColor Cyan
@($selected.pair) | ForEach-Object { Write-Host $_ }

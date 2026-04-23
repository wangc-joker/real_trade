$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

$repoRoot = Split-Path -Parent $PSScriptRoot
$pairsPath = Join-Path $repoRoot "user_data\generated\pairs.dynamic.top40.302u.balanced.json"
$reportPath = Join-Path $repoRoot "user_data\generated\pairs.dynamic.top40.302u.balanced.report.json"

# Keep existing output file paths for compatibility with the live machine.
$targetCount = 30
$quoteAsset = "USDT"
$requestDelaySeconds = 2
$script:lastRequestAt = $null
$strategyPath = if (-not [string]::IsNullOrWhiteSpace($env:NFI_STRATEGY_PATH)) {
    $env:NFI_STRATEGY_PATH
}
else {
    Join-Path $repoRoot "user_data\strategies\NostalgiaForInfinityX7.py"
}

function Get-Json {
    param([string]$Uri)

    if ($null -ne $script:lastRequestAt) {
        $elapsedSeconds = ((Get-Date) - $script:lastRequestAt).TotalSeconds
        $remainingSeconds = $requestDelaySeconds - $elapsedSeconds
        if ($remainingSeconds -gt 0) {
            Start-Sleep -Seconds ([int][math]::Ceiling($remainingSeconds))
        }
    }

    try {
        return Invoke-RestMethod -Uri $Uri -Method Get -TimeoutSec 60
    }
    finally {
        $script:lastRequestAt = Get-Date
    }
}

function Get-TopCoinsModeCoinsFromStrategy {
    param([string]$StrategyPath)

    if (-not (Test-Path -LiteralPath $StrategyPath -PathType Leaf)) {
        throw "Strategy file not found: $StrategyPath"
    }

    $source = Get-Content -Raw -LiteralPath $StrategyPath
    $match = [regex]::Match(
        $source,
        'top_coins_mode_coins\s*=\s*\[(?<body>.*?)\]',
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )

    if (-not $match.Success) {
        throw "Could not find top_coins_mode_coins in strategy file: $StrategyPath"
    }

    $coins = New-Object System.Collections.Generic.List[string]
    foreach ($coinMatch in [regex]::Matches($match.Groups['body'].Value, '["''](?<coin>[A-Za-z0-9]+)["'']')) {
        $coin = $coinMatch.Groups['coin'].Value.ToUpperInvariant()
        if (-not [string]::IsNullOrWhiteSpace($coin) -and -not $coins.Contains($coin)) {
            $coins.Add($coin)
        }
    }

    if ($coins.Count -eq 0) {
        throw "top_coins_mode_coins was found, but no coins could be parsed from: $StrategyPath"
    }

    return @($coins)
}

function Get-PerpetualUsdtSymbolMapBySymbol {
    param([object]$ExchangeInfo)

    $map = @{}
    foreach ($symbolInfo in $ExchangeInfo.symbols) {
        if ($symbolInfo.quoteAsset -ne "USDT") { continue }
        if ($symbolInfo.status -ne "TRADING") { continue }
        if ($symbolInfo.contractType -ne "PERPETUAL") { continue }
        if ([string]::IsNullOrWhiteSpace($symbolInfo.baseAsset)) { continue }
        if ([string]::IsNullOrWhiteSpace($symbolInfo.symbol)) { continue }

        $symbol = ([string]$symbolInfo.symbol).ToUpperInvariant()
        $map[$symbol] = $symbolInfo
    }

    return $map
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $pairsPath) | Out-Null

$mainCoins = @(Get-TopCoinsModeCoinsFromStrategy -StrategyPath $strategyPath)
$mainCoinSet = @{}
foreach ($coin in $mainCoins) {
    $mainCoinSet[$coin] = $true
}

$exchangeInfo = Get-Json "https://fapi.binance.com/fapi/v1/exchangeInfo"
$tickers = Get-Json "https://fapi.binance.com/fapi/v1/ticker/24hr"
$symbolMap = Get-PerpetualUsdtSymbolMapBySymbol -ExchangeInfo $exchangeInfo

$candidateList = New-Object System.Collections.Generic.List[object]
$seenBaseAssets = @{}
foreach ($ticker in $tickers) {
    $symbol = ([string]$ticker.symbol).ToUpperInvariant()
    if (-not $symbolMap.ContainsKey($symbol)) { continue }

    $meta = $symbolMap[$symbol]
    $baseAsset = ([string]$meta.baseAsset).ToUpperInvariant()
    if (-not $mainCoinSet.ContainsKey($baseAsset)) { continue }
    if ($seenBaseAssets.ContainsKey($baseAsset)) { continue }

    $seenBaseAssets[$baseAsset] = $true
    $candidateList.Add([pscustomobject]@{
        symbol = $meta.symbol
        baseAsset = $meta.baseAsset
        pair = ("{0}/{1}:{1}" -f $meta.baseAsset, $quoteAsset)
        currentQuoteVolume24h = [double]$ticker.quoteVolume
        currentVolume24h = [double]$ticker.volume
        weightedAvgPrice24h = [double]$ticker.weightedAvgPrice
        count24h = [int64]$ticker.count
        openPrice24h = [double]$ticker.openPrice
        lastPrice = [double]$ticker.lastPrice
        priceChangePercent24h = [double]$ticker.priceChangePercent
    })
}

$rankedCandidates = @($candidateList | Sort-Object currentQuoteVolume24h -Descending)
$selected = @($rankedCandidates | Select-Object -First $targetCount)

$missingFromExchange = @($mainCoins | Where-Object { -not $seenBaseAssets.ContainsKey($_) })

if ($selected.Count -eq 0) {
    throw "No Binance Futures symbols could be selected from the strategy main coin pool."
}

if ($selected.Count -lt $targetCount) {
    Write-Warning ("Only {0} eligible symbols were available from the strategy main coin pool; target was {1}." -f $selected.Count, $targetCount)
}

[System.IO.File]::WriteAllText(
    $pairsPath,
    (@($selected.pair) | ConvertTo-Json -Depth 4),
    [System.Text.UTF8Encoding]::new($false)
)

$report = [pscustomobject]@{
    generated_at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss zzz")
    source = "Binance Futures 24h ticker quoteVolume, restricted to the strategy main coin pool"
    strategy_path = $strategyPath
    target_count = $targetCount
    request_delay_seconds = $requestDelaySeconds
    main_coin_count = $mainCoins.Count
    eligible_candidate_count = $rankedCandidates.Count
    selected_count = $selected.Count
    missing_from_binance_futures = @($missingFromExchange)
    filter = [pscustomobject]@{
        quote_asset = $quoteAsset
        contract_type = "PERPETUAL"
        status = "TRADING"
        selection_strategy = "Read the latest top_coins_mode_coins from NostalgiaForInfinityX7.py on every run, treat it as the main coin pool, then select the 30 symbols with the highest current 24h quote volume."
    }
    main_coins = @($mainCoins)
    pairs = @($selected)
}

[System.IO.File]::WriteAllText(
    $reportPath,
    ($report | ConvertTo-Json -Depth 16),
    [System.Text.UTF8Encoding]::new($false)
)

Write-Host ""
Write-Host "Dynamic MainCoin Top30 pairlist updated." -ForegroundColor Green
Write-Host ("Strategy: {0}" -f $strategyPath)
Write-Host ("Pairs   : {0}" -f $pairsPath)
Write-Host ("Report  : {0}" -f $reportPath)
Write-Host ("Main coins in strategy : {0}" -f $mainCoins.Count)
Write-Host ("Eligible candidates    : {0}" -f $rankedCandidates.Count)
Write-Host ("Selected count         : {0}" -f $selected.Count)
if ($missingFromExchange.Count -gt 0) {
    Write-Host ("Missing futures symbols: {0}" -f (@($missingFromExchange) -join ', ')) -ForegroundColor Yellow
}
Write-Host ""
Write-Host "Selected pairs:" -ForegroundColor Cyan
@($selected.pair) | ForEach-Object { Write-Host $_ }

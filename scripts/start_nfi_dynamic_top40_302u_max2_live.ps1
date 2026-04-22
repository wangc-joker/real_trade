[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$templateConfigPath = Join-Path $repoRoot "user_data\config.live.nfi.dynamic.top40.302u.max2.json"
$runtimeConfigPath = Join-Path $repoRoot "user_data\config.live.nfi.dynamic.top40.302u.max2.runtime.json"
$pairsPath = Join-Path $repoRoot "user_data\generated\pairs.dynamic.top40.302u.balanced.json"
$preservedPairsPath = Join-Path $repoRoot "user_data\runtime\preserved_open_pairs.json"
$updateScriptPath = Join-Path $repoRoot "scripts\update_nfi_dynamic_top40_302u_balanced.ps1"
$secureConfigPath = "D:\work\secure\secret_bin.json"
$containerService = "freqtrade"
$baseUrl = "http://127.0.0.1:8084"
$liveDbPath = "/freqtrade/user_data/tradesv3_nfi_dynamic_top40_302u_max2_live.sqlite"

function Get-OptionalSecureConfig {
    if (Test-Path -LiteralPath $secureConfigPath -PathType Leaf) {
        return Get-Content -Raw -LiteralPath $secureConfigPath | ConvertFrom-Json
    }

    return $null
}

function Get-RequiredValue {
    param(
        [string]$CurrentValue,
        [string]$EnvName,
        [string]$SecureValue,
        [string]$Label
    )

    if (-not [string]::IsNullOrWhiteSpace($CurrentValue) -and $CurrentValue -notlike "CHANGE_ME*") {
        return $CurrentValue
    }
    if (-not [string]::IsNullOrWhiteSpace($SecureValue)) {
        return $SecureValue
    }
    $envItem = Get-Item -Path ("Env:{0}" -f $EnvName) -ErrorAction SilentlyContinue
    if ($envItem -and -not [string]::IsNullOrWhiteSpace($envItem.Value)) {
        return $envItem.Value
    }

    throw "Missing required $Label. Set it in $secureConfigPath or environment variable $EnvName."
}

function Merge-PreservedPairs {
    param(
        [object[]]$PrimaryPairs,
        [string]$PreservedPairsPath
    )

    $merged = New-Object System.Collections.Generic.List[string]
    foreach ($pair in @($PrimaryPairs)) {
        if (-not [string]::IsNullOrWhiteSpace($pair) -and -not $merged.Contains($pair)) {
            $merged.Add($pair)
        }
    }

    if (Test-Path -LiteralPath $PreservedPairsPath -PathType Leaf) {
        $preservedPairs = Get-Content -Raw -LiteralPath $PreservedPairsPath | ConvertFrom-Json
        foreach ($pair in @($preservedPairs)) {
            if (-not [string]::IsNullOrWhiteSpace($pair) -and -not $merged.Contains($pair)) {
                $merged.Add($pair)
            }
        }
    }

    return @($merged)
}

if (-not (Test-Path -LiteralPath $templateConfigPath -PathType Leaf)) {
    throw "Template config not found: $templateConfigPath"
}

if (-not (Test-Path -LiteralPath $updateScriptPath -PathType Leaf)) {
    throw "Update script not found: $updateScriptPath"
}

if (-not (Test-Path -LiteralPath $pairsPath -PathType Leaf)) {
    Write-Host "Balanced dynamic top40 pairlist not found locally. Refreshing..." -ForegroundColor Cyan
    & powershell -ExecutionPolicy Bypass -File $updateScriptPath
}
else {
    Write-Host "Using existing balanced dynamic top40 pairlist file." -ForegroundColor Cyan
    Write-Host ("Pairs  : {0}" -f $pairsPath)
}

if (-not (Test-Path -LiteralPath $pairsPath -PathType Leaf)) {
    throw "Dynamic pair file not found: $pairsPath"
}

$templateConfig = Get-Content -Raw -LiteralPath $templateConfigPath | ConvertFrom-Json
$pairs = Get-Content -Raw -LiteralPath $pairsPath | ConvertFrom-Json
$pairs = Merge-PreservedPairs -PrimaryPairs @($pairs) -PreservedPairsPath $preservedPairsPath
$secureConfig = Get-OptionalSecureConfig

$apiKey = $secureConfig.exchange.key
$apiSecret = $secureConfig.exchange.secret
if ([string]::IsNullOrWhiteSpace($apiKey) -or [string]::IsNullOrWhiteSpace($apiSecret)) {
    throw "Secure API config does not contain exchange key/secret: $secureConfigPath"
}

$templateConfig.exchange.key = $apiKey
$templateConfig.exchange.secret = $apiSecret
$templateConfig.exchange.pair_whitelist = @($pairs)
$templateConfig.api_server.username = Get-RequiredValue -CurrentValue $templateConfig.api_server.username -EnvName "FREQTRADE_API_USERNAME" -SecureValue $secureConfig.api_server.username -Label "API username"
$templateConfig.api_server.password = Get-RequiredValue -CurrentValue $templateConfig.api_server.password -EnvName "FREQTRADE_API_PASSWORD" -SecureValue $secureConfig.api_server.password -Label "API password"
$templateConfig.api_server.jwt_secret_key = Get-RequiredValue -CurrentValue $templateConfig.api_server.jwt_secret_key -EnvName "FREQTRADE_API_JWT_SECRET" -SecureValue $secureConfig.api_server.jwt_secret_key -Label "API JWT secret"
$templateConfig.api_server.ws_token = Get-RequiredValue -CurrentValue $templateConfig.api_server.ws_token -EnvName "FREQTRADE_API_WS_TOKEN" -SecureValue $secureConfig.api_server.ws_token -Label "API websocket token"

[System.IO.File]::WriteAllText(
    $runtimeConfigPath,
    ($templateConfig | ConvertTo-Json -Depth 32),
    [System.Text.UTF8Encoding]::new($false)
)

$composeEnv = @{
    FREQTRADE_COMMAND = "trade"
    FREQTRADE_CONFIG = (Split-Path -Leaf $runtimeConfigPath)
    FREQTRADE_DB_URL = "sqlite:///$liveDbPath"
    FREQTRADE_STRATEGY = "NostalgiaForInfinityX7"
}

$apiUser = $templateConfig.api_server.username
$apiPassword = $templateConfig.api_server.password

Push-Location $repoRoot
try {
    foreach ($entry in $composeEnv.GetEnumerator()) {
        Set-Item -Path ("Env:{0}" -f $entry.Key) -Value $entry.Value
    }

    Write-Host "Starting container..." -ForegroundColor Cyan
    docker compose up -d --force-recreate --remove-orphans $containerService | Out-Host

    $authText = "{0}:{1}" -f $apiUser, $apiPassword
    $authToken = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($authText))
    $headers = @{ Authorization = "Basic $authToken" }

    Write-Host "Waiting for bot API..." -ForegroundColor Cyan
    for ($i = 0; $i -lt 45; $i++) {
        try {
            Invoke-RestMethod -Uri "$baseUrl/api/v1/ping" | Out-Null
            break
        }
        catch {
            if ($i -eq 44) {
                throw "API did not become ready in time."
            }
            Start-Sleep -Seconds 2
        }
    }

    Invoke-RestMethod -Method Post -Headers $headers -Uri "$baseUrl/api/v1/start" | Out-Null
    $status = Invoke-RestMethod -Headers $headers -Uri "$baseUrl/api/v1/status"
    $showConfig = Invoke-RestMethod -Headers $headers -Uri "$baseUrl/api/v1/show_config"

    Write-Host ""
    Write-Host "NFI Balanced Dynamic Top40 302.6U live bot started." -ForegroundColor Green
    Write-Host ("Runtime config: {0}" -f $runtimeConfigPath)
    Write-Host ("Strategy      : {0}" -f $showConfig.strategy)
    Write-Host ("Runmode       : {0}" -f $showConfig.runmode)
    Write-Host ("State         : {0}" -f $showConfig.state)
    Write-Host ("Pairs loaded  : {0}" -f @($showConfig.exchange.pair_whitelist).Count)
    Write-Host ("Open trades   : {0}" -f @($status).Count)
}
finally {
    Pop-Location
}

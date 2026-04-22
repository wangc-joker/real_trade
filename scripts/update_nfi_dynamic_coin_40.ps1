$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

$repoRoot = Split-Path -Parent $PSScriptRoot
$updateScriptPath = Join-Path $repoRoot "scripts\update_nfi_dynamic_top40_302u_balanced.ps1"
$pairsPath = Join-Path $repoRoot "user_data\generated\pairs.dynamic.top40.302u.balanced.json"
$runtimeConfigPath = Join-Path $repoRoot "user_data\config.live.nfi.dynamic.top40.302u.max2.runtime.json"
$preservedPairsPath = Join-Path $repoRoot "user_data\runtime\preserved_open_pairs.json"
$baseUrl = "http://127.0.0.1:8084"

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

function Wait-ApiReady {
    param(
        [hashtable]$Headers,
        [string]$BaseUrl,
        [int]$MaxAttempts = 30,
        [int]$DelaySeconds = 2
    )

    for ($i = 0; $i -lt $MaxAttempts; $i++) {
        try {
            Invoke-RestMethod -Headers $Headers -Uri "$BaseUrl/api/v1/ping" | Out-Null
            return $true
        }
        catch {
            if ($i -eq ($MaxAttempts - 1)) {
                return $false
            }
            Start-Sleep -Seconds $DelaySeconds
        }
    }

    return $false
}

if (-not (Test-Path -LiteralPath $updateScriptPath -PathType Leaf)) {
    throw "Update script not found: $updateScriptPath"
}

Write-Host "Refreshing balanced dynamic top40 pairlist..." -ForegroundColor Cyan
& powershell -ExecutionPolicy Bypass -File $updateScriptPath

if (-not (Test-Path -LiteralPath $pairsPath -PathType Leaf)) {
    throw "Updated pair file not found: $pairsPath"
}

$pairs = Get-Content -Raw -LiteralPath $pairsPath | ConvertFrom-Json
$pairs = Merge-PreservedPairs -PrimaryPairs @($pairs) -PreservedPairsPath $preservedPairsPath

if (Test-Path -LiteralPath $runtimeConfigPath -PathType Leaf) {
    $runtimeConfig = Get-Content -Raw -LiteralPath $runtimeConfigPath | ConvertFrom-Json
    $runtimeConfig.exchange.pair_whitelist = @($pairs)

    [System.IO.File]::WriteAllText(
        $runtimeConfigPath,
        ($runtimeConfig | ConvertTo-Json -Depth 32),
        [System.Text.UTF8Encoding]::new($false)
    )

    $apiUser = [string]$runtimeConfig.api_server.username
    $apiPassword = [string]$runtimeConfig.api_server.password

    if (-not [string]::IsNullOrWhiteSpace($apiUser) -and -not [string]::IsNullOrWhiteSpace($apiPassword)) {
        $authText = "{0}:{1}" -f $apiUser, $apiPassword
        $authToken = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($authText))
        $headers = @{ Authorization = "Basic $authToken" }

        try {
            Invoke-RestMethod -Headers $headers -Uri "$baseUrl/api/v1/ping" | Out-Null
            Invoke-RestMethod -Method Post -Headers $headers -Uri "$baseUrl/api/v1/reload_config" | Out-Null
            if (Wait-ApiReady -Headers $headers -BaseUrl $baseUrl) {
                Invoke-RestMethod -Method Post -Headers $headers -Uri "$baseUrl/api/v1/start" | Out-Null
                Write-Host "Running bot config reloaded and bot restarted." -ForegroundColor Green
            }
            else {
                Write-Warning "Runtime config reloaded, but bot API did not come back in time. Start the bot manually if needed."
            }
        }
        catch {
            Write-Warning "Runtime config updated, but running bot API was not reachable. The new whitelist will apply on the next bot restart."
        }
    }
    else {
        Write-Warning "Runtime config updated, but API credentials are unavailable. The new whitelist will apply on the next bot restart."
    }
}
else {
    Write-Warning "Runtime config not found. Pair file was updated, and the new whitelist will apply on the next bot start."
}

Write-Host ("Whitelist pair count: {0}" -f @($pairs).Count)

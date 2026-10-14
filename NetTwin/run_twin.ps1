$ErrorActionPreference = "Stop"

$root = "C:\NetTwin"

$masterCollector = Join-Path $root "collect_master_telemetry.ps1"
$slaveCollector  = Join-Path $root "collect_once.ps1"
$twinBuilder     = Join-Path $root "build_digital_twin_v3.ps1"
$twinFile        = Join-Path $root "digital_twin_v3.json"

Write-Host "======================================"
Write-Host "       NETTWIN LIVE TWIN ENGINE"
Write-Host "======================================"

# Start the continuous Slave collector separately.
$runningCollectors = @(
    Get-CimInstance Win32_Process |
    Where-Object {
        $_.Name -match '^powershell(\.exe)?$' -and
        $_.CommandLine -and
        $_.CommandLine -match '(?i)-File\s+"?C:\\NetTwin\\collect_once\.ps1"?'
    }
)

if ($runningCollectors.Count -eq 0) {
    Write-Host "Starting continuous Slave collector..." `
        -ForegroundColor Cyan

    Start-Process `
        -FilePath "powershell.exe" `
        -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File "C:\NetTwin\collect_once.ps1"' `
        -WorkingDirectory $root
}
else {
    Write-Host "Slave collector is already running." `
        -ForegroundColor Yellow
}

Start-Sleep -Seconds 2

while ($true) {
    try {
        Write-Host ""
        Write-Host "======================================"
        Write-Host "Starting a new telemetry cycle"
        Write-Host "======================================"

        # 1. Collect current Master telemetry.
        Write-Host "[1/3] Collecting Master telemetry..." `
            -ForegroundColor Cyan

        & $masterCollector

        # 2. Build the structured three-node Digital Twin.
        Write-Host "[2/3] Building structured Digital Twin..." `
            -ForegroundColor Yellow

        & $twinBuilder

        # 3. Validate the generated JSON.
        Write-Host "[3/3] Validating Digital Twin..." `
            -ForegroundColor Cyan

        if (-not (Test-Path $twinFile)) {
            throw "digital_twin.json was not created."
        }

        $twin = Get-Content $twinFile -Raw |
            ConvertFrom-Json -ErrorAction Stop

        $nodeNames = @(
            $twin.PhysicalNodes |
            ForEach-Object { $_.Name }
        )

        if ($nodeNames.Count -ne 3) {
            throw "Expected 3 nodes; found $($nodeNames.Count)."
        }

        foreach ($expected in @("Master", "Slave1", "Slave2")) {
            if ($nodeNames -notcontains $expected) {
                throw "Missing Digital Twin node: $expected"
            }
        }

        Write-Host "SUCCESS: All three nodes are present." `
            -ForegroundColor Green

        Write-Host "Generated at: $($twin.GeneratedAt)"
        Write-Host "Overall health: $($twin.OverallHealth)"
        Write-Host "JSON: $twinFile"
    }
    catch {
        Write-Host "CYCLE FAILED: $($_.Exception.Message)" `
            -ForegroundColor Red
    }

    Write-Host "Next cycle in 10 seconds..." `
        -ForegroundColor Yellow

    Start-Sleep -Seconds 10
}


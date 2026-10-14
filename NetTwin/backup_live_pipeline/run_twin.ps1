$collector = "C:\NetTwin\collect_once.ps1"
$twinBuilder = "C:\NetTwin\build_digital_twin.ps1"

Write-Host "======================================"
Write-Host "       NETTWIN LIVE ENGINE"
Write-Host "======================================"

while ($true) {

    Write-Host ""
    Write-Host "Collecting telemetry..." -ForegroundColor Cyan

    & $collector

    Write-Host "Building Digital Twin..." -ForegroundColor Yellow

    & $twinBuilder

    Write-Host "Digital Twin synchronized." `
        -ForegroundColor Green

    Start-Sleep -Seconds 5
}
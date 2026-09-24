$dataFile = "C:\NetTwin\network_data.csv"
$eventFile = "C:\NetTwin\network_events.csv"

$data = Import-Csv $dataFile

if ($data.Count -eq 0) {
    Write-Host "No telemetry data available."
    exit
}

# Get the latest record for each node
$latest = $data |
    Group-Object HOSTNAME |
    ForEach-Object {
        $_.Group | Select-Object -Last 1
    }

Write-Host ""
Write-Host "======================================"
Write-Host "       NETTWIN FAULT ANALYSIS"
Write-Host "======================================"

foreach ($node in $latest) {

    $fault = "NORMAL"

    $cpu = [double]$node.CPU
    $ramTotal = [double]$node.RAM_TOTAL_GB
    $ramFree = [double]$node.RAM_FREE_GB
    $diskTotal = [double]$node.DISK_TOTAL_GB
    $diskFree = [double]$node.DISK_FREE_GB

    # Calculate percentages
    $ramUsedPercent = (($ramTotal - $ramFree) / $ramTotal) * 100
    $diskUsedPercent = (($diskTotal - $diskFree) / $diskTotal) * 100

    # Fault classification
    if ($cpu -ge 90) {
        $fault = "HIGH_CPU"
    }
    elseif ($ramUsedPercent -ge 90) {
        $fault = "HIGH_RAM"
    }
    elseif ($diskUsedPercent -ge 90) {
        $fault = "LOW_DISK_SPACE"
    }

    Write-Host ""
    Write-Host "Node       : $($node.HOSTNAME)"
    Write-Host "CPU        : $cpu %"
    Write-Host "RAM Used   : $([math]::Round($ramUsedPercent,2)) %"
    Write-Host "Disk Used  : $([math]::Round($diskUsedPercent,2)) %"
    Write-Host "Status     : $fault"

    # Record detected fault
    if ($fault -ne "NORMAL") {

        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

        $line = "$timestamp,$($node.HOSTNAME),FAULT,$fault"

        Add-Content -Path $eventFile -Value $line
    }
}

Write-Host ""
Write-Host "======================================"
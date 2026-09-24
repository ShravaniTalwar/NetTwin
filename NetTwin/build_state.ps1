$csv = "C:\NetTwin\network_data.csv"
$stateFile = "C:\NetTwin\network_state.json"

if (-not (Test-Path $csv)) {
    Write-Host "Telemetry file not found."
    exit
}

$data = Import-Csv $csv

$latest = $data |
    Group-Object Node |
    ForEach-Object {
        $_.Group | Select-Object -Last 1
    }

$nodes = @()

foreach ($row in $latest) {

    $cpu = 0
    [double]::TryParse($row.CPU, [ref]$cpu) | Out-Null

    $ramTotal = 0
    $ramFree = 0

    [double]::TryParse($row.RAM_TOTAL_GB, [ref]$ramTotal) | Out-Null
    [double]::TryParse($row.RAM_FREE_GB, [ref]$ramFree) | Out-Null

    $ramUsed = $ramTotal - $ramFree

    $status = "ONLINE"

    if ($cpu -ge 90) {
        $status = "HIGH_CPU"
    }

    if ($ramTotal -gt 0) {
        $ramPercent = ($ramUsed / $ramTotal) * 100

        if ($ramPercent -ge 90) {
            $status = "HIGH_RAM"
        }
    }

    $nodes += [PSCustomObject]@{
        Node       = $row.Node
        IP         = $row.IP
        Hostname   = $row.HOSTNAME
        CPU        = $cpu
        RAM_Total  = $ramTotal
        RAM_Free   = $ramFree
        RAM_Used   = [math]::Round($ramUsed,2)
        Status     = $status
        Timestamp  = $row.Timestamp
    }
}

$state = [PSCustomObject]@{
    UpdatedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Nodes     = $nodes
}

$state | ConvertTo-Json -Depth 5 |
    Set-Content $stateFile

Write-Host "Network state updated:"
Get-Content $stateFile
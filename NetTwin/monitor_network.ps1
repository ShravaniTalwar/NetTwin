$nodes = @(
    @{
        Name = "Slave1"
        IP = "10.184.79.207"
    },
    @{
        Name = "Slave2"
        IP = "10.184.79.48"
    }
)

$eventFile = "C:\NetTwin\network_events.csv"

# Create CSV file if it does not exist
if (!(Test-Path $eventFile)) {
    "Timestamp,Node,IP,Status" | Out-File $eventFile
}

# Store previous states
$previousState = @{}

foreach ($node in $nodes) {
    $previousState[$node.Name] = "UNKNOWN"
}

Write-Host ""
Write-Host "======================================"
Write-Host "       NETTWIN NETWORK MONITOR"
Write-Host "======================================"
Write-Host "Monitoring started..."
Write-Host ""

while ($true) {

    foreach ($node in $nodes) {

        $online = Test-Connection `
            -ComputerName $node.IP `
            -Count 2 `
            -Quiet

        if ($online) {
            $currentState = "ONLINE"
        }
        else {
            $currentState = "OFFLINE"
        }

        # Record only when state changes
        if ($currentState -ne $previousState[$node.Name]) {

            $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

            $line = "$timestamp,$($node.Name),$($node.IP),$currentState"

            Add-Content -Path $eventFile -Value $line

            if ($currentState -eq "ONLINE") {
                Write-Host "$timestamp  $($node.Name) : ONLINE" -ForegroundColor Green
            }
            else {
                Write-Host "$timestamp  $($node.Name) : OFFLINE" -ForegroundColor Red
            }

            $previousState[$node.Name] = $currentState
        }
    }

    Start-Sleep -Seconds 5
}
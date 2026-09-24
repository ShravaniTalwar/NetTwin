$nodes = @(
    @{
        Name = "Slave1"
        IP = " "
        User = " "
    },
    @{
        Name = "Slave2"
        IP = ""
        User = ""
    }
)

$dataFile = "C:\NetTwin\network_data.csv"

$fields = @(
    "Timestamp",
    "NODE",
    "HOSTNAME",
    "CPU",
    "RAM_TOTAL_GB",
    "RAM_FREE_GB",
    "RAM_USED_GB",
    "DISK_TOTAL_GB",
    "DISK_FREE_GB",
    "NETWORK",
    "LINK_SPEED",
    "PACKETS_SENT",
    "PACKETS_RECEIVED",
    "BYTES_SENT",
    "BYTES_RECEIVED",
    "PACKET_ERRORS",
    "PACKET_DISCARDS",
    "TCP_CONNECTIONS",
    "LISTENING_PORTS",
    "FIREWALL",
    "DEFENDER"
)

# Create the CSV if it doesn't exist
if (!(Test-Path $dataFile)) {
    ($fields -join ",") | Set-Content $dataFile
}

while ($true) {

    Write-Host ""
    Write-Host "========================================"
    Write-Host "       NETTWIN TELEMETRY CYCLE"
    Write-Host "========================================"

    foreach ($node in $nodes) {

        Write-Host ""
        Write-Host "Collecting from $($node.Name)..." -ForegroundColor Cyan

        try {

            $sshTarget = "$($node.User)@$($node.IP)"

            $output = ssh $sshTarget `
                "powershell -ExecutionPolicy Bypass -File C:\NetTwinMonitor.ps1" 2>&1

            if ($LASTEXITCODE -ne 0) {
                throw "SSH connection failed"
            }

            $values = @{}

            foreach ($line in $output) {

                if ($line -match "^([^=]+)=(.*)$") {

                    $key = $matches[1]
                    $value = $matches[2]

                    $values[$key] = $value
                }
            }

            # Verify that this is actually v2 telemetry
            if (!$values.ContainsKey("BYTES_SENT")) {
                throw "NetTwinMonitor v2 telemetry not received"
            }

            $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

            $row = @(
                $timestamp
                $node.Name
                $values["HOSTNAME"]
                $values["CPU"]
                $values["RAM_TOTAL_GB"]
                $values["RAM_FREE_GB"]
                $values["RAM_USED_GB"]
                $values["DISK_TOTAL_GB"]
                $values["DISK_FREE_GB"]
                $values["NETWORK"]
                $values["LINK_SPEED"]
                $values["PACKETS_SENT"]
                $values["PACKETS_RECEIVED"]
                $values["BYTES_SENT"]
                $values["BYTES_RECEIVED"]
                $values["PACKET_ERRORS"]
                $values["PACKET_DISCARDS"]
                $values["TCP_CONNECTIONS"]
                $values["LISTENING_PORTS"]
                $values["FIREWALL"]
                $values["DEFENDER"]
            )

            $escapedRow = $row | ForEach-Object {
                '"' + ($_ -replace '"','""') + '"'
            }

            Add-Content `
                -Path $dataFile `
                -Value ($escapedRow -join ",")

            Write-Host "$($node.Name) telemetry collected." `
                -ForegroundColor Green
        }
        catch {

            Write-Host "$($node.Name) collection FAILED." `
                -ForegroundColor Red

            Write-Host $_
        }
    }

    # Build the Digital Twin immediately after collection
    Write-Host ""
    Write-Host "Synchronizing Digital Twin..." `
        -ForegroundColor Yellow

    & "C:\NetTwin\build_digital_twin.ps1"

    Write-Host ""
    Write-Host "Digital Twin synchronized." `
        -ForegroundColor Green

    Start-Sleep -Seconds 10
}

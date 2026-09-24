$nodes = @(
    @{
        Name = "Slave1"
        IP = "10.184.79.207"
        User = "Neha"
    },
    @{
        Name = "Slave2"
        IP = "10.184.79.48"
        User = "rushda"
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

# Create CSV with new structure
if (!(Test-Path $dataFile)) {
    ($fields -join ",") | Out-File $dataFile
}

while ($true) {

    foreach ($node in $nodes) {

        Write-Host ""
        Write-Host "Collecting from $($node.Name)..." -ForegroundColor Cyan

        try {

            $sshTarget = "$($node.User)@$($node.IP)"

            $output = ssh $sshTarget `
                "powershell -ExecutionPolicy Bypass -File C:\NetTwinMonitor.ps1"

            $values = @{}

            foreach ($line in $output) {

                if ($line -match "^([^=]+)=(.*)$") {

                    $key = $matches[1]
                    $value = $matches[2]

                    $values[$key] = $value
                }
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

            Write-Host "$($node.Name) collected successfully." `
                -ForegroundColor Green

        }
        catch {

            Write-Host "$($node.Name) collection failed." `
                -ForegroundColor Red

            Write-Host $_
        }
    }

    Write-Host ""
    Write-Host "Waiting 10 seconds..." -ForegroundColor Yellow

    Start-Sleep -Seconds 10
}
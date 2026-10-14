$nodes = @(
    @{
        Name = "Slave1"
        IP = "10.11.251.207"
        User = "Neha"
    },
    @{
        Name = "Slave2"
        IP = "10.11.251.48"
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
    "DEFENDER",
    "LATENCY_MS",
    "CONNECTIVITY",
    "PACKET_LOSS_PERCENT",
    "BANDWIDTH_MBPS",
    "NODE_HEALTH",
    "OVERALL_HEALTH"
)

# --------------------------------------------------
# CREATE CSV HEADER
# --------------------------------------------------

if (!(Test-Path $dataFile)) {

    $headerLine = $fields -join ","

    [System.IO.File]::AppendAllText(
        $dataFile,
        $headerLine + [Environment]::NewLine,
        (New-Object System.Text.UTF8Encoding($true))
    )
}

# --------------------------------------------------
# STORE PREVIOUS BYTE COUNTERS
# --------------------------------------------------

$previousBytes = @{}

# --------------------------------------------------
# CONTINUOUS COLLECTION
# --------------------------------------------------

while ($true) {

    Write-Host ""
    Write-Host "========================================"
    Write-Host "       NETTWIN TELEMETRY CYCLE"
    Write-Host "========================================"

    $cycleNodeHealth = @{}
    $cycleConnectivity = @{}
    $cycleRows = @()

    foreach ($node in $nodes) {

        Write-Host ""
        Write-Host "Collecting from $($node.Name)..." -ForegroundColor Cyan

        try {

            # --------------------------------------------------
            # CONNECTIVITY + LATENCY + PACKET LOSS
            # --------------------------------------------------

            $pingResults = @(
                Test-Connection `
                    -ComputerName $node.IP `
                    -Count 10 `
                    -ErrorAction SilentlyContinue
            )

            $successfulPings = @(
                $pingResults | Where-Object {
                    $_.StatusCode -eq 0
                }
            )

            $received = $successfulPings.Count

            # --------------------------------------------------
            # PACKET LOSS
            # --------------------------------------------------

            $packetLoss = [math]::Round(
                ((10 - $received) / 10) * 100,
                2
            )

            # --------------------------------------------------
            # CONNECTIVITY STATUS
            # --------------------------------------------------

            if ($received -eq 10) {

                $connectivity = "ONLINE"

            }
            elseif ($received -gt 0) {

                $connectivity = "DEGRADED"

            }
            else {

                $connectivity = "OFFLINE"
            }

            # --------------------------------------------------
            # LATENCY
            # --------------------------------------------------

            if ($received -gt 0) {

                $latency = [math]::Round(
                    (
                        $successfulPings |
                        Measure-Object -Property ResponseTime -Average
                    ).Average,
                    2
                )

            }
            else {

                $latency = ""
            }

            Write-Host "$($node.Name) connectivity : $connectivity" `
                -ForegroundColor Yellow

            Write-Host "$($node.Name) latency : $latency ms" `
                -ForegroundColor Yellow

            Write-Host "$($node.Name) packet loss : $packetLoss %" `
                -ForegroundColor Yellow

            # --------------------------------------------------
            # SSH TELEMETRY
            # --------------------------------------------------

            $sshTarget = "$($node.User)@$($node.IP)"

            $output = ssh $sshTarget `
                "powershell -ExecutionPolicy Bypass -File C:\NetTwinMonitor.ps1" 2>&1

            if ($LASTEXITCODE -ne 0) {

                throw "SSH connection failed"
            }

            # --------------------------------------------------
            # PARSE TELEMETRY
            # --------------------------------------------------

            $values = @{}

            foreach ($line in $output) {

                if ($line -match "^([^=]+)=(.*)$") {

                    $key = $matches[1]
                    $value = $matches[2]

                    $values[$key] = $value
                }
            }

            if (!$values.ContainsKey("BYTES_SENT")) {

                throw "NetTwinMonitor telemetry not received"
            }

            if (!$values.ContainsKey("BYTES_RECEIVED")) {

                throw "BYTES_RECEIVED telemetry not received"
            }

            # --------------------------------------------------
            # BANDWIDTH CALCULATION
            # --------------------------------------------------

            $bandwidthMbps = ""

            $currentBytesSent = [double]$values["BYTES_SENT"]
            $currentBytesReceived = [double]$values["BYTES_RECEIVED"]

            if ($previousBytes.ContainsKey($node.Name)) {

                $previousBytesSent = $previousBytes[$node.Name].Sent
                $previousBytesReceived = $previousBytes[$node.Name].Received

                $sentDifference = $currentBytesSent - $previousBytesSent
                $receivedDifference = $currentBytesReceived - $previousBytesReceived

                # Handle counter reset
                if ($sentDifference -lt 0) {
                    $sentDifference = 0
                }

                if ($receivedDifference -lt 0) {
                    $receivedDifference = 0
                }

                $totalBytesDifference =
                    $sentDifference + $receivedDifference

                # Collection interval = 10 seconds
                $bandwidthMbps = [math]::Round(
                    ($totalBytesDifference * 8) / 10 / 1000000,
                    2
                )
            }

            # Store current counters for next cycle
            $previousBytes[$node.Name] = @{
                Sent = $currentBytesSent
                Received = $currentBytesReceived
            }

            Write-Host "$($node.Name) bandwidth : $bandwidthMbps Mbps" `
                -ForegroundColor Yellow

            # --------------------------------------------------
            # NODE HEALTH
            # --------------------------------------------------

            $ramTotal = [double]$values["RAM_TOTAL_GB"]
            $ramFree = [double]$values["RAM_FREE_GB"]

            if ($ramTotal -gt 0) {

                $ramUsedPercent = [math]::Round(
                    (($ramTotal - $ramFree) / $ramTotal) * 100,
                    2
                )

            }
            else {

                $ramUsedPercent = 0
            }

            $diskTotal = [double]$values["DISK_TOTAL_GB"]
            $diskFree = [double]$values["DISK_FREE_GB"]

            if ($diskTotal -gt 0) {

                $diskUsedPercent = [math]::Round(
                    (($diskTotal - $diskFree) / $diskTotal) * 100,
                    2
                )

            }
            else {

                $diskUsedPercent = 0
            }

            # Default
            $nodeHealth = "HEALTHY"

            # CPU
            if ([double]$values["CPU"] -ge 90) {

                $nodeHealth = "HIGH_CPU"
            }

            # RAM
            elseif ($ramUsedPercent -ge 90) {

                $nodeHealth = "HIGH_RAM"
            }

            # Disk
            elseif ($diskUsedPercent -ge 90) {

                $nodeHealth = "LOW_DISK"
            }

            # Firewall
            if ($values["FIREWALL"] -eq "DISABLED") {

                $nodeHealth = "SECURITY_WARNING"
            }

            # Connectivity also affects node health
            if ($connectivity -eq "OFFLINE") {

                $nodeHealth = "OFFLINE"
            }
            elseif (
                $connectivity -eq "DEGRADED" -and
                $nodeHealth -eq "HEALTHY"
            ) {

                $nodeHealth = "NETWORK_DEGRADED"
            }

            $cycleNodeHealth[$node.Name] = $nodeHealth
            $cycleConnectivity[$node.Name] = $connectivity

            # --------------------------------------------------
            # CREATE ROW DATA
            # --------------------------------------------------

            $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

            $rowData = [ordered]@{

                Timestamp = $timestamp

                NODE = $node.Name

                HOSTNAME = $values["HOSTNAME"]

                CPU = $values["CPU"]

                RAM_TOTAL_GB = $values["RAM_TOTAL_GB"]

                RAM_FREE_GB = $values["RAM_FREE_GB"]

                RAM_USED_GB = $values["RAM_USED_GB"]

                DISK_TOTAL_GB = $values["DISK_TOTAL_GB"]

                DISK_FREE_GB = $values["DISK_FREE_GB"]

                NETWORK = $values["NETWORK"]

                LINK_SPEED = $values["LINK_SPEED"]

                PACKETS_SENT = $values["PACKETS_SENT"]

                PACKETS_RECEIVED = $values["PACKETS_RECEIVED"]

                BYTES_SENT = $values["BYTES_SENT"]

                BYTES_RECEIVED = $values["BYTES_RECEIVED"]

                PACKET_ERRORS = $values["PACKET_ERRORS"]

                PACKET_DISCARDS = $values["PACKET_DISCARDS"]

                TCP_CONNECTIONS = $values["TCP_CONNECTIONS"]

                LISTENING_PORTS = $values["LISTENING_PORTS"]

                FIREWALL = $values["FIREWALL"]

                DEFENDER = $values["DEFENDER"]

                LATENCY_MS = $latency

                CONNECTIVITY = $connectivity

                PACKET_LOSS_PERCENT = $packetLoss

                BANDWIDTH_MBPS = $bandwidthMbps

                NODE_HEALTH = $nodeHealth

                OVERALL_HEALTH = ""
            }

            $cycleRows += ,$rowData

            Write-Host "$($node.Name) collected successfully." `
                -ForegroundColor Green
        }

        catch {

            Write-Host "$($node.Name) collection FAILED." `
                -ForegroundColor Red

            Write-Host $_

            # --------------------------------------------------
            # MARK NODE OFFLINE
            # --------------------------------------------------

            $cycleConnectivity[$node.Name] = "OFFLINE"
            $cycleNodeHealth[$node.Name] = "OFFLINE"

            $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

            $rowData = [ordered]@{

                Timestamp = $timestamp

                NODE = $node.Name

                HOSTNAME = ""

                CPU = ""

                RAM_TOTAL_GB = ""

                RAM_FREE_GB = ""

                RAM_USED_GB = ""

                DISK_TOTAL_GB = ""

                DISK_FREE_GB = ""

                NETWORK = ""

                LINK_SPEED = ""

                PACKETS_SENT = ""

                PACKETS_RECEIVED = ""

                BYTES_SENT = ""

                BYTES_RECEIVED = ""

                PACKET_ERRORS = ""

                PACKET_DISCARDS = ""

                TCP_CONNECTIONS = ""

                LISTENING_PORTS = ""

                FIREWALL = ""

                DEFENDER = ""

                LATENCY_MS = ""

                CONNECTIVITY = "OFFLINE"

                PACKET_LOSS_PERCENT = 100

                BANDWIDTH_MBPS = ""

                NODE_HEALTH = "OFFLINE"

                OVERALL_HEALTH = ""
            }

            $cycleRows += ,$rowData
        }
    }

    # --------------------------------------------------
    # OVERALL NETWORK HEALTH
    # --------------------------------------------------

    $overallHealth = "HEALTHY"

    if ($cycleConnectivity.Values -contains "OFFLINE") {

        $overallHealth = "NETWORK_DEGRADED"
    }

    elseif ($cycleConnectivity.Values -contains "DEGRADED") {

        $overallHealth = "NETWORK_DEGRADED"
    }

    if ($cycleNodeHealth.Values -contains "HIGH_CPU") {

        $overallHealth = "RESOURCE_WARNING"
    }

    if ($cycleNodeHealth.Values -contains "HIGH_RAM") {

        $overallHealth = "RESOURCE_WARNING"
    }

    if ($cycleNodeHealth.Values -contains "SECURITY_WARNING") {

        $overallHealth = "SECURITY_WARNING"
    }

    # --------------------------------------------------
    # WRITE ALL ROWS
    # --------------------------------------------------

    foreach ($rowData in $cycleRows) {

        $rowData["OVERALL_HEALTH"] = $overallHealth

        $row = @(
            $rowData.Timestamp
            $rowData.NODE
            $rowData.HOSTNAME
            $rowData.CPU
            $rowData.RAM_TOTAL_GB
            $rowData.RAM_FREE_GB
            $rowData.RAM_USED_GB
            $rowData.DISK_TOTAL_GB
            $rowData.DISK_FREE_GB
            $rowData.NETWORK
            $rowData.LINK_SPEED
            $rowData.PACKETS_SENT
            $rowData.PACKETS_RECEIVED
            $rowData.BYTES_SENT
            $rowData.BYTES_RECEIVED
            $rowData.PACKET_ERRORS
            $rowData.PACKET_DISCARDS
            $rowData.TCP_CONNECTIONS
            $rowData.LISTENING_PORTS
            $rowData.FIREWALL
            $rowData.DEFENDER
            $rowData.LATENCY_MS
            $rowData.CONNECTIVITY
            $rowData.PACKET_LOSS_PERCENT
            $rowData.BANDWIDTH_MBPS
            $rowData.NODE_HEALTH
            $rowData.OVERALL_HEALTH
        )

        $escapedRow = $row | ForEach-Object {

            '"' + ($_ -replace '"','""') + '"'
        }

        $csvLine = $escapedRow -join ","

        [System.IO.File]::AppendAllText(
            $dataFile,
            $csvLine + [Environment]::NewLine
        )
    }

    # --------------------------------------------------
    # DISPLAY STATUS
    # --------------------------------------------------

    Write-Host ""
    Write-Host "========================================"
    Write-Host "NETWORK STATUS"
    Write-Host "========================================"

    foreach ($node in $nodes) {

        Write-Host "$($node.Name)"
        Write-Host "  Connectivity : $($cycleConnectivity[$node.Name])"
        Write-Host "  Node Health  : $($cycleNodeHealth[$node.Name])"
    }

    Write-Host ""
    Write-Host "Overall Health : $overallHealth" -ForegroundColor Yellow

    Write-Host ""
    Write-Host "Waiting 10 seconds..." -ForegroundColor Yellow

    Start-Sleep -Seconds 10
}
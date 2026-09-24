$dataFile = "C:\NetTwin\network_data.csv"
$eventFile = "C:\NetTwin\network_events.csv"
$outputFile = "C:\NetTwin\digital_twin.json"

if (!(Test-Path $dataFile)) {
    Write-Host "Telemetry file not found."
    exit
}

$data = Import-Csv $dataFile

if ($data.Count -eq 0) {
    Write-Host "No telemetry data available."
    exit
}

# Get latest telemetry record for every node
$latestNodes = $data |
    Group-Object NODE |
    ForEach-Object {
        $_.Group | Select-Object -Last 1
    }

$nodes = @()

foreach ($record in $latestNodes) {

    $ramTotal = [double]$record.RAM_TOTAL_GB
    $ramFree = [double]$record.RAM_FREE_GB

    if ($ramTotal -gt 0) {
        $ramUsedPercent = [math]::Round(
            (($ramTotal - $ramFree) / $ramTotal) * 100,
            2
        )
    }
    else {
        $ramUsedPercent = 0
    }

    $diskTotal = [double]$record.DISK_TOTAL_GB
    $diskFree = [double]$record.DISK_FREE_GB

    if ($diskTotal -gt 0) {
        $diskUsedPercent = [math]::Round(
            (($diskTotal - $diskFree) / $diskTotal) * 100,
            2
        )
    }
    else {
        $diskUsedPercent = 0
    }

    # Basic health classification
    $health = "HEALTHY"

    if ([double]$record.CPU -ge 90) {
        $health = "HIGH_CPU"
    }
    elseif ($ramUsedPercent -ge 90) {
        $health = "HIGH_RAM"
    }
    elseif ($diskUsedPercent -ge 90) {
        $health = "LOW_DISK"
    }

    if ($record.FIREWALL -eq "DISABLED") {
        $health = "SECURITY_WARNING"
    }

    $node = [ordered]@{
        Name = $record.NODE
        Hostname = $record.HOSTNAME

        LastUpdated = $record.Timestamp

        Health = $health

        Resources = [ordered]@{
            CPU_Percent = [double]$record.CPU

            RAM_Total_GB = $ramTotal
            RAM_Free_GB = $ramFree
            RAM_Used_Percent = $ramUsedPercent

            Disk_Total_GB = $diskTotal
            Disk_Free_GB = $diskFree
            Disk_Used_Percent = $diskUsedPercent
        }

        Network = [ordered]@{
            Adapter = $record.NETWORK
            LinkSpeed = $record.LINK_SPEED

            PacketsSent = $record.PACKETS_SENT
            PacketsReceived = $record.PACKETS_RECEIVED

            BytesSent = $record.BYTES_SENT
            BytesReceived = $record.BYTES_RECEIVED

            PacketErrors = $record.PACKET_ERRORS
            PacketDiscards = $record.PACKET_DISCARDS

            TCPConnections = $record.TCP_CONNECTIONS

            ListeningPorts = $record.LISTENING_PORTS
        }

        Security = [ordered]@{
            Firewall = $record.FIREWALL
            Defender = $record.DEFENDER
        }
    }

    $nodes += $node
}

# Connectivity
$connectivity = @()

foreach ($node in $nodes) {

    $ip = ""

    if ($node.Name -eq "Slave1") {
        $ip = "10.184.79.207"
    }

    if ($node.Name -eq "Slave2") {
        $ip = "10.184.79.48"
    }

    if ($ip -ne "") {

        $online = Test-Connection `
            -ComputerName $ip `
            -Count 1 `
            -Quiet `
            -ErrorAction SilentlyContinue

        $status = if ($online) {
            "ONLINE"
        }
        else {
            "OFFLINE"
        }

        $connectivity += [ordered]@{
            Node = $node.Name
            IP = $ip
            Status = $status
        }
    }
}

# Overall network health
$overallHealth = "HEALTHY"

if ($connectivity.Status -contains "OFFLINE") {
    $overallHealth = "NETWORK_DEGRADED"
}

if ($nodes.Health -contains "HIGH_CPU") {
    $overallHealth = "RESOURCE_WARNING"
}

if ($nodes.Health -contains "HIGH_RAM") {
    $overallHealth = "RESOURCE_WARNING"
}

if ($nodes.Health -contains "SECURITY_WARNING") {
    $overallHealth = "SECURITY_WARNING"
}

# Build Digital Twin
$digitalTwin = [ordered]@{

    TwinName = "NetTwin"

    GeneratedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    OverallHealth = $overallHealth

    PhysicalNodes = $nodes

    Connectivity = $connectivity
}

$digitalTwin |
    ConvertTo-Json -Depth 10 |
    Set-Content $outputFile

Write-Host ""
Write-Host "======================================"
Write-Host "       NETTWIN DIGITAL TWIN"
Write-Host "======================================"
Write-Host ""
Write-Host "Overall Health : $overallHealth"

foreach ($node in $nodes) {

    Write-Host "$($node.Name) : $($node.Health)"
}

Write-Host ""
Write-Host "Digital Twin updated:"
Write-Host $outputFile
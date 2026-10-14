
# ==========================================
# NetTwin Digital Twin Builder v2
# Telemetry + Security + Software Inventory
# ==========================================

$dataFile = "C:\NetTwin\network_data.csv"
$eventFile = "C:\NetTwin\network_events.csv"
$outputFile = "C:\NetTwin\digital_twin.json"
$healthFile = "C:\NetTwin\network_health.csv"
$assessmentFile = "C:\NetTwin\security_assessment.csv"
$softwareFile = "C:\NetTwin\software_inventory.csv"

if (!(Test-Path $dataFile)) {
    Write-Host "Telemetry file not found."
    exit
}

$data = @(Import-Csv $dataFile)

if ($data.Count -eq 0) {
    Write-Host "No telemetry data available."
    exit
}

# ---------- LATEST TELEMETRY PER NODE ----------

$latestNodes = @(
    $data |
        Group-Object NODE |
        ForEach-Object {
            $_.Group | Select-Object -Last 1
        }
)

# ---------- LATEST SECURITY ASSESSMENT PER NODE ----------

$securityByNode = @{}

if (Test-Path $assessmentFile) {
    $assessmentData = @(Import-Csv $assessmentFile)

    foreach ($group in ($assessmentData | Group-Object Node)) {
        $latestAssessment = $group.Group | Select-Object -Last 1
        $securityByNode[$group.Name] = $latestAssessment
    }
}

# ---------- SOFTWARE COUNTS PER NODE ----------

$softwareCounts = @{}

if (Test-Path $softwareFile) {
    $softwareData = @(Import-Csv $softwareFile)

    foreach ($group in ($softwareData | Group-Object Node)) {
        $softwareCounts[$group.Name] = @($group.Group).Count
    }
}

# ---------- BUILD PHYSICAL NODES ----------

$nodes = @()

foreach ($record in $latestNodes) {

    $ramTotal = 0.0
    $ramFree = 0.0
    $diskTotal = 0.0
    $diskFree = 0.0
    $cpuPercent = 0.0

    if ($record.RAM_TOTAL_GB -match '^\d+(\.\d+)?$') {
        $ramTotal = [double]$record.RAM_TOTAL_GB
    }

    if ($record.RAM_FREE_GB -match '^\d+(\.\d+)?$') {
        $ramFree = [double]$record.RAM_FREE_GB
    }

    if ($record.DISK_TOTAL_GB -match '^\d+(\.\d+)?$') {
        $diskTotal = [double]$record.DISK_TOTAL_GB
    }

    if ($record.DISK_FREE_GB -match '^\d+(\.\d+)?$') {
        $diskFree = [double]$record.DISK_FREE_GB
    }

    if ($record.CPU -match '^\d+(\.\d+)?$') {
        $cpuPercent = [double]$record.CPU
    }

    $ramUsedPercent = 0
    if ($ramTotal -gt 0) {
        $ramUsedPercent = [math]::Round(
            (($ramTotal - $ramFree) / $ramTotal) * 100, 2
        )
    }

    $diskUsedPercent = 0
    if ($diskTotal -gt 0) {
        $diskUsedPercent = [math]::Round(
            (($diskTotal - $diskFree) / $diskTotal) * 100, 2
        )
    }

    # ---------- RESOURCE HEALTH ----------

    $health = "HEALTHY"

    if ($cpuPercent -ge 90) {
        $health = "HIGH_CPU"
    }
    elseif ($ramUsedPercent -ge 90) {
        $health = "HIGH_RAM"
    }
    elseif ($diskUsedPercent -ge 90) {
        $health = "LOW_DISK"
    }

    # ---------- TELEMETRY SECURITY FIELDS ----------

    $firewall = [string]$record.FIREWALL
    $defender = [string]$record.DEFENDER
    $firewallProfiles = [string]$record.FIREWALL_PROFILES
    $defenderRealtime = [string]$record.DEFENDER_REALTIME
    $smbv1 = [string]$record.SMBV1
    $securityRisk = [string]$record.SECURITY_RISK

    # Older telemetry rows may not contain the new fields.
    if ([string]::IsNullOrWhiteSpace($defenderRealtime)) {
        $defenderRealtime = $defender
    }

    if ([string]::IsNullOrWhiteSpace($securityRisk)) {
        $securityRisk = "UNKNOWN"
    }

    if ($firewall -eq "DISABLED" -or
        $defenderRealtime -eq "INACTIVE" -or
        $smbv1 -eq "ENABLED") {
        $health = "SECURITY_WARNING"
    }

    # ---------- UPDATE ASSESSMENT ----------

    $updateStatus = "UNKNOWN"
    $availableUpdates = "UNKNOWN"
    $lastUpdateDate = "UNKNOWN"
    $assessmentCollectionStatus = "UNKNOWN"

    if ($securityByNode.ContainsKey([string]$record.NODE)) {
        $assessment = $securityByNode[[string]$record.NODE]

        if ($assessment.WindowsUpdateStatus) {
            $updateStatus = [string]$assessment.WindowsUpdateStatus
        }

        if ($assessment.AvailableUpdateCount) {
            $availableUpdates = [string]$assessment.AvailableUpdateCount
        }

        if ($assessment.LastUpdateDate) {
            $lastUpdateDate = [string]$assessment.LastUpdateDate
        }

        if ($assessment.CollectionStatus) {
            $assessmentCollectionStatus = [string]$assessment.CollectionStatus
        }
    }

    # ---------- SOFTWARE INVENTORY ----------

    $softwareCount = 0
    $softwareInventoryAvailable = $false

    if ($softwareCounts.ContainsKey([string]$record.NODE)) {
        $softwareCount = [int]$softwareCounts[[string]$record.NODE]
        $softwareInventoryAvailable = $true
    }

    # ---------- NODE OBJECT ----------

    $node = [ordered]@{
        Name = $record.NODE
        Hostname = $record.HOSTNAME
        LastUpdated = $record.Timestamp
        Health = $health

        Resources = [ordered]@{
            CPU_Percent = $cpuPercent
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
            LatencyMs = $record.LATENCY_MS
            PacketLossPercent = $record.PACKET_LOSS_PERCENT
            Connectivity = $record.CONNECTIVITY
            BandwidthMbps = $record.BANDWIDTH_MBPS
        }

        Security = [ordered]@{
            Firewall = $firewall
            FirewallProfiles = $firewallProfiles
            Defender = $defender
            DefenderRealtime = $defenderRealtime
            SMBv1 = $smbv1
            SecurityRisk = $securityRisk

            WindowsUpdateStatus = $updateStatus
            AvailableUpdateCount = $availableUpdates
            LastUpdateDate = $lastUpdateDate
            UpdateAssessmentCollectionStatus = $assessmentCollectionStatus

            SoftwareCount = $softwareCount
            SoftwareInventoryAvailable = $softwareInventoryAvailable
            SoftwareInventoryFile = $softwareFile
        }
    }

    $nodes += $node
}

# ---------- CONNECTIVITY ----------

$connectivity = @()

foreach ($node in $nodes) {
    $ip = ""

    if ($node.Name -eq "Slave1") {
        $ip = "10.11.251.207"
    }
    elseif ($node.Name -eq "Slave2") {
        $ip = "10.11.251.48"
    }

    if ($ip -ne "") {
        $online = Test-Connection `
            -ComputerName $ip `
            -Count 1 `
            -Quiet `
            -ErrorAction SilentlyContinue

        $status = if ($online) { "ONLINE" } else { "OFFLINE" }

        $connectivity += [ordered]@{
            Node = $node.Name
            IP = $ip
            Status = $status
        }
    }
}

# ---------- OVERALL HEALTH ----------

$overallHealth = "HEALTHY"

if ($connectivity.Status -contains "OFFLINE") {
    $overallHealth = "NETWORK_DEGRADED"
}

if ($nodes.Health -contains "HIGH_CPU" -or
    $nodes.Health -contains "HIGH_RAM" -or
    $nodes.Health -contains "LOW_DISK") {
    $overallHealth = "RESOURCE_WARNING"
}

if ($nodes.Health -contains "SECURITY_WARNING") {
    $overallHealth = "SECURITY_WARNING"
}

if ($overallHealth -eq "HEALTHY" -and
    @($nodes | Where-Object {
        $_.Security.SecurityRisk -eq "UNKNOWN" -or
        $_.Security.UpdateAssessmentCollectionStatus -ne "SUCCESS"
    }).Count -gt 0) {
    $overallHealth = "SECURITY_REVIEW"
}

# ---------- BUILD DIGITAL TWIN ----------

$digitalTwin = [ordered]@{
    TwinName = "NetTwin"
    GeneratedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    OverallHealth = $overallHealth
    PhysicalNodes = $nodes
    Connectivity = $connectivity
    SecurityInventory = [ordered]@{
        SoftwareInventoryFile = $softwareFile
        SecurityAssessmentFile = $assessmentFile
    }
}

$digitalTwin |
    ConvertTo-Json -Depth 12 |
    Set-Content -Path $outputFile -Encoding UTF8

# ---------- NETWORK HEALTH HISTORY ----------

$healthTimestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$slave1Health = ""
$slave2Health = ""

foreach ($node in $nodes) {
    if ($node.Name -eq "Slave1") {
        $slave1Health = $node.Health
    }
    elseif ($node.Name -eq "Slave2") {
        $slave2Health = $node.Health
    }
}

if (!(Test-Path $healthFile)) {
    "Timestamp,OverallHealth,Slave1Health,Slave2Health" |
        Set-Content -Path $healthFile -Encoding UTF8
}

$healthRow = @(
    $healthTimestamp
    $overallHealth
    $slave1Health
    $slave2Health
)

$escapedHealthRow = $healthRow | ForEach-Object {
    '"' + ([string]$_ -replace '"','""') + '"'
}

[System.IO.File]::AppendAllText(
    $healthFile,
    ($escapedHealthRow -join ",") + [Environment]::NewLine
)

# ---------- DISPLAY RESULT ----------

Write-Host ""
Write-Host "======================================"
Write-Host "       NETTWIN DIGITAL TWIN"
Write-Host "======================================"
Write-Host "Overall Health : $overallHealth"

foreach ($node in $nodes) {
    Write-Host ""
    Write-Host "$($node.Name) : $($node.Health)"
    Write-Host "  Firewall       : $($node.Security.Firewall)"
    Write-Host "  Defender       : $($node.Security.DefenderRealtime)"
    Write-Host "  SMBv1           : $($node.Security.SMBv1)"
    Write-Host "  Security Risk   : $($node.Security.SecurityRisk)"
    Write-Host "  Windows Updates : $($node.Security.WindowsUpdateStatus)"
    Write-Host "  Available Updates: $($node.Security.AvailableUpdateCount)"
    Write-Host "  Software Count  : $($node.Security.SoftwareCount)"
}

Write-Host ""
Write-Host "Digital Twin updated: $outputFile"
Write-Host "Network Health saved: $healthFile"

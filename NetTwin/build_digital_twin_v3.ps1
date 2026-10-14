
# ==========================================
# NetTwin Digital Twin Builder v3
# Three physical laptops + telemetry + health
# ==========================================

$ErrorActionPreference = "Stop"

$root = "C:\NetTwin"
$slaveFile = Join-Path $root "network_data.csv"
$masterFile = Join-Path $root "master_telemetry.csv"
$assessmentFile = Join-Path $root "security_assessment.csv"
$softwareFile = Join-Path $root "software_inventory.csv"
$outputFile = Join-Path $root "digital_twin_v3.json"
$healthFile = Join-Path $root "network_health.csv"

$staleAfterSeconds = 180

$slaveIPs = @{
    Slave1 = "10.11.251.207"
    Slave2 = "10.11.251.48"
}

# ---------- HELPERS ----------

function Get-Field {
    param($Record, [string]$Name, $Default = $null)

    if ($null -eq $Record) { return $Default }

    $property = $Record.PSObject.Properties[$Name]

    if ($null -eq $property -or
        $null -eq $property.Value -or
        [string]::IsNullOrWhiteSpace([string]$property.Value)) {
        return $Default
    }

    return $property.Value
}

function Get-Number {
    param($Value)

    $number = 0.0

    if ($null -ne $Value -and
        [double]::TryParse([string]$Value, [ref]$number)) {
        return $number
    }

    return $null
}

function Get-TimestampAge {
    param($Timestamp)

    $parsed = [datetime]::MinValue

    if ([datetime]::TryParse([string]$Timestamp, [ref]$parsed)) {
        return [math]::Max(
            0,
            [math]::Round(((Get-Date) - $parsed).TotalSeconds, 1)
        )
    }

    return $null
}

function Get-MetricScore {
    param(
        [string]$Metric,
        [double]$Value
    )

    switch ($Metric) {
        "CPU" {
            if ($Value -lt 85) { return 100 }
            if ($Value -lt 95) { return 60 }
            return 20
        }
        "RAM" {
            if ($Value -lt 85) { return 100 }
            if ($Value -lt 95) { return 60 }
            return 20
        }
        "DISK" {
            if ($Value -lt 85) { return 100 }
            if ($Value -lt 95) { return 60 }
            return 20
        }
        "PACKETLOSS" {
            if ($Value -lt 1) { return 100 }
            if ($Value -lt 5) { return 60 }
            return 20
        }
    }

    return 0
}

function Test-SshPort {
    param([string]$IP)

    try {
        $result = Test-NetConnection `
            -ComputerName $IP `
            -Port 22 `
            -InformationLevel Quiet `
            -WarningAction SilentlyContinue `
            -ErrorAction SilentlyContinue

        return [bool]$result
    }
    catch {
        return $false
    }
}

function Convert-ListeningPorts {
    param($Value)

    $ports = @()

    if (-not [string]::IsNullOrWhiteSpace([string]$Value)) {
        foreach ($item in ([string]$Value -split ";")) {
            $port = 0

            if ([int]::TryParse($item.Trim(), [ref]$port) -and
                $port -ge 1 -and $port -le 65535) {
                $ports += $port
            }
        }
    }

    return @($ports | Sort-Object -Unique)
}

# ---------- LOAD TELEMETRY ----------

if (-not (Test-Path $slaveFile)) {
    throw "Slave telemetry file not found: $slaveFile"
}

if (-not (Test-Path $masterFile)) {
    throw "Master telemetry file not found: $masterFile"
}

$slaveRows = @(Import-Csv $slaveFile)
$masterRows = @(Import-Csv $masterFile)

if ($slaveRows.Count -eq 0 -or $masterRows.Count -eq 0) {
    throw "One or more telemetry files contain no records."
}

$latestByNode = @{}

foreach ($group in ($slaveRows | Group-Object NODE)) {
    $latestByNode[$group.Name] = $group.Group |
        Sort-Object {
            $dt = [datetime]::MinValue
            [datetime]::TryParse($_.Timestamp, [ref]$dt) | Out-Null
            $dt
        } |
        Select-Object -Last 1
}

$masterRecord = $masterRows |
    Sort-Object {
        $dt = [datetime]::MinValue
        [datetime]::TryParse($_.Timestamp, [ref]$dt) | Out-Null
        $dt
    } |
    Select-Object -Last 1

# ---------- LOAD SECURITY ASSESSMENTS ----------

$securityByNode = @{}

if (Test-Path $assessmentFile) {
    $assessments = @(Import-Csv $assessmentFile)

    foreach ($group in ($assessments | Group-Object Node)) {
        $securityByNode[$group.Name] = $group.Group |
            Sort-Object {
                $dt = [datetime]::MinValue
                [datetime]::TryParse($_.Timestamp, [ref]$dt) | Out-Null
                $dt
            } |
            Select-Object -Last 1
    }
}

# ---------- SOFTWARE COUNTS ----------

$softwareCounts = @{}

if (Test-Path $softwareFile) {
    foreach ($group in (@(Import-Csv $softwareFile) | Group-Object Node)) {
        $softwareCounts[$group.Name] = @($group.Group).Count
    }
}

# ---------- BUILD NODE RECORDS ----------

$nodes = @()
$nodeRecords = @()

$nodeRecords += [PSCustomObject]@{
    Name = "Master"
    Record = $masterRecord
    IP = [string](Get-Field $masterRecord "IP_ADDRESS" "10.11.251.194")
    IsMaster = $true
}

foreach ($name in @("Slave1", "Slave2")) {
    if ($latestByNode.ContainsKey($name)) {
        $nodeRecords += [PSCustomObject]@{
            Name = $name
            Record = $latestByNode[$name]
            IP = $slaveIPs[$name]
            IsMaster = $false
        }
    }
}

foreach ($entry in $nodeRecords) {
    $r = $entry.Record
    $name = $entry.Name
    $ip = $entry.IP
    $isMaster = $entry.IsMaster

    $timestamp = [string](Get-Field $r "Timestamp" "")
    $age = Get-TimestampAge $timestamp

    $cpu = Get-Number (Get-Field $r "CPU")
    $ramTotal = Get-Number (Get-Field $r "RAM_TOTAL_GB")
    $ramFree = Get-Number (Get-Field $r "RAM_FREE_GB")
    $ramUsed = Get-Number (Get-Field $r "RAM_USED_GB")
    $ramPercent = Get-Number (Get-Field $r "RAM_USED_PERCENT")

    if ($null -eq $ramPercent -and
        $null -ne $ramTotal -and $ramTotal -gt 0 -and
        $null -ne $ramFree) {
        $ramPercent = [math]::Round(
            (($ramTotal - $ramFree) / $ramTotal) * 100, 2
        )
    }

    $diskTotal = Get-Number (Get-Field $r "DISK_TOTAL_GB")
    $diskFree = Get-Number (Get-Field $r "DISK_FREE_GB")
    $diskPercent = Get-Number (Get-Field $r "DISK_USED_PERCENT")

    if ($null -eq $diskPercent -and
        $null -ne $diskTotal -and $diskTotal -gt 0 -and
        $null -ne $diskFree) {
        $diskPercent = [math]::Round(
            (($diskTotal - $diskFree) / $diskTotal) * 100, 2
        )
    }

    $packetLoss = Get-Number (Get-Field $r "PACKET_LOSS_PERCENT")
    $latency = Get-Number (Get-Field $r "LATENCY_MS")
    $bandwidth = Get-Number (Get-Field $r "BANDWIDTH_MBPS")

    $sshStatus = if ($isMaster) {
        "LOCAL"
    } elseif (Test-SshPort $ip) {
        "REACHABLE"
    } else {
        "UNREACHABLE"
    }

    $telemetryStatus = "FRESH"
    if ($null -eq $age) {
        $telemetryStatus = "UNKNOWN"
    } elseif ($age -gt $staleAfterSeconds) {
        $telemetryStatus = "STALE"
    }

    $connectivity = if ($isMaster) {
        "LOCAL"
    } elseif ($sshStatus -eq "REACHABLE") {
        "ONLINE"
    } elseif ($telemetryStatus -eq "FRESH") {
        "UNCONFIRMED"
    } else {
        "OFFLINE_OR_UNREACHABLE"
    }

    $metricScores = @()

    if ($null -ne $cpu) {
        $metricScores += Get-MetricScore "CPU" $cpu
    }
    if ($null -ne $ramPercent) {
        $metricScores += Get-MetricScore "RAM" $ramPercent
    }
    if ($null -ne $diskPercent) {
        $metricScores += Get-MetricScore "DISK" $diskPercent
    }
    if ($null -ne $packetLoss) {
        $metricScores += Get-MetricScore "PACKETLOSS" $packetLoss
    }

    $score = if ($metricScores.Count -gt 0) {
        [math]::Round(
            ($metricScores | Measure-Object -Average).Average, 0
        )
    } else {
        $null
    }

    $health = "HEALTHY"

    if ($telemetryStatus -ne "FRESH") {
        $health = "DATA_STALE"
    }

    if ($null -ne $score -and $score -lt 60) {
        $health = "CRITICAL"
    } elseif ($null -ne $score -and $score -lt 100 -and
              $health -eq "HEALTHY") {
        $health = "WARNING"
    }

    if (-not $isMaster -and $sshStatus -eq "UNREACHABLE") {
        $health = "CONNECTIVITY_WARNING"
    }

    $firewall = [string](Get-Field $r "FIREWALL" "UNKNOWN")
    $firewallProfiles = [string](Get-Field $r "FIREWALL_PROFILES" "UNKNOWN")
    $defender = [string](Get-Field $r "DEFENDER_REALTIME" `
        (Get-Field $r "DEFENDER" "UNKNOWN"))
    $smbv1 = [string](Get-Field $r "SMBV1" "UNKNOWN")
    $securityRisk = [string](Get-Field $r "SECURITY_RISK" "UNKNOWN")

    if ($isMaster) {
        $firewallProfiles = "Not collected"
        $smbv1 = "UNKNOWN"
        $securityRisk = "UNKNOWN"
    }

    $updateStatus = "UNKNOWN"
    $availableUpdates = $null
    $lastUpdateDate = "UNKNOWN"
    $assessmentStatus = "NOT_COLLECTED"
    $softwareCount = $null

    if ($securityByNode.ContainsKey($name)) {
        $a = $securityByNode[$name]
        $updateStatus = [string](Get-Field $a "WindowsUpdateStatus" "UNKNOWN")
        $availableUpdates = Get-Number (Get-Field $a "AvailableUpdateCount")
        $lastUpdateDate = [string](Get-Field $a "LastUpdateDate" "UNKNOWN")
        $assessmentStatus = [string](Get-Field $a "CollectionStatus" "UNKNOWN")
    }

    if ($softwareCounts.ContainsKey($name)) {
        $softwareCount = $softwareCounts[$name]
    }

    $ports = Convert-ListeningPorts (Get-Field $r "LISTENING_PORTS" "")

    $node = [ordered]@{
        Name = $name
        Hostname = [string](Get-Field $r "HOSTNAME" "UNKNOWN")
        IPAddress = $ip
        Role = if ($isMaster) { "COLLECTOR" } else { "MONITORED_NODE" }
        LastUpdated = $timestamp
        TelemetryAgeSeconds = $age
        TelemetryStatus = $telemetryStatus
        Connectivity = [ordered]@{
            Status = $connectivity
            SSHStatus = $sshStatus
            ICMPStatus = "NOT_MEASURED_BY_V3"
        }
        Health = $health
        HealthScore = $score
        HealthScoreBasis = "Average of available CPU, RAM, disk and packet-loss metric scores; see HealthRules"
        Resources = [ordered]@{
            CPU_Percent = $cpu
            RAM_Total_GB = $ramTotal
            RAM_Free_GB = $ramFree
            RAM_Used_GB = $ramUsed
            RAM_Used_Percent = $ramPercent
            Disk_Total_GB = $diskTotal
            Disk_Free_GB = $diskFree
            Disk_Used_Percent = $diskPercent
        }
        Network = [ordered]@{
            Adapter = [string](Get-Field $r "NETWORK" "UNKNOWN")
            AdapterStatus = [string](Get-Field $r "ADAPTER_STATUS" "UNKNOWN")
            LinkSpeed = [string](Get-Field $r "LINK_SPEED" "UNKNOWN")
            PacketsSent = Get-Number (Get-Field $r "PACKETS_SENT")
            PacketsReceived = Get-Number (Get-Field $r "PACKETS_RECEIVED")
            BytesSent = Get-Number (Get-Field $r "BYTES_SENT")
            BytesReceived = Get-Number (Get-Field $r "BYTES_RECEIVED")
            PacketErrors = Get-Number (Get-Field $r "PACKET_ERRORS")
            PacketDiscards = Get-Number (Get-Field $r "PACKET_DISCARDS")
            TCPConnections = Get-Number (Get-Field $r "TCP_CONNECTIONS")
            ListeningPorts = $ports
            ListeningPortCount = $ports.Count
            LatencyMs = $latency
            PacketLossPercent = $packetLoss
            BandwidthMbps = $bandwidth
            ReceivedMbps = Get-Number (Get-Field $r "RECEIVED_MBPS")
            SentMbps = Get-Number (Get-Field $r "SENT_MBPS")
            NetworkUtilizationPercent = Get-Number (Get-Field $r "NETWORK_UTILIZATION_PERCENT")
            SampleIntervalSeconds = Get-Number (Get-Field $r "SAMPLE_INTERVAL_SECONDS")
            ReceivedPacketErrors = Get-Number (Get-Field $r "RECEIVED_PACKET_ERRORS")
            OutboundPacketErrors = Get-Number (Get-Field $r "OUTBOUND_PACKET_ERRORS")
        }
        Security = [ordered]@{
            Firewall = $firewall
            FirewallProfiles = $firewallProfiles
            DefenderRealtime = $defender
            SMBv1 = $smbv1
            SecurityRisk = $securityRisk
            WindowsUpdateStatus = $updateStatus
            AvailableUpdateCount = $availableUpdates
            LastUpdateDate = $lastUpdateDate
            UpdateAssessmentCollectionStatus = $assessmentStatus
            SoftwareCount = $softwareCount
            VulnerabilityAssessmentStatus = "NOT_YET_IMPLEMENTED"
            VulnerabilityFindings = @()
        }
    }

    $nodes += $node
}

# ---------- VERIFIED MASTER-TO-SLAVE SSH LINKS ----------

$links = @()

foreach ($node in $nodes) {
    if ($node.Name -eq "Master") { continue }

    $linkStatus = $node.Connectivity.SSHStatus

    $links += [ordered]@{
        Source = "Master"
        Target = $node.Name
        Type = "TCP_SSH"
        TargetIP = $node.IPAddress
        TargetPort = 22
        Status = $linkStatus
        Evidence = "Test-NetConnection TCP port 22 at build time"
        PhysicalLayerTopologyVerified = $false
    }
}

# ---------- OVERALL HEALTH ----------

$overallHealth = "HEALTHY"

if (@($nodes | Where-Object {
    $_.Health -eq "CRITICAL" -or
    $_.Health -eq "CONNECTIVITY_WARNING"
}).Count -gt 0) {
    $overallHealth = "CRITICAL_OR_CONNECTIVITY_WARNING"
}
elseif (@($nodes | Where-Object {
    $_.Health -eq "WARNING" -or
    $_.Health -eq "DATA_STALE"
}).Count -gt 0) {
    $overallHealth = "WARNING_OR_STALE_DATA"
}

if (@($nodes | Where-Object {
    $_.Security.SecurityRisk -eq "HIGH"
}).Count -gt 0) {
    $overallHealth = "SECURITY_WARNING"
}

# ---------- MODEL ----------

$generatedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

$digitalTwin = [ordered]@{
    TwinName = "NetTwin"
    ModelVersion = "3.0"
    GeneratedAt = $generatedAt
    OverallHealth = $overallHealth
    HealthRules = [ordered]@{
        CPU_Percent = @{ Healthy = "<85"; Warning = "85 to <95"; Critical = ">=95" }
        RAM_Used_Percent = @{ Healthy = "<85"; Warning = "85 to <95"; Critical = ">=95" }
        Disk_Used_Percent = @{ Healthy = "<85"; Warning = "85 to <95"; Critical = ">=95" }
        PacketLossPercent = @{ Healthy = "<1"; Warning = "1 to <5"; Critical = ">=5" }
        Score = "Average of available metric scores: 100 healthy, 60 warning, 20 critical"
        TelemetryFreshnessSeconds = $staleAfterSeconds
        Note = "Proposed project thresholds; missing measurements are excluded, not treated as healthy."
    }
    PhysicalNodes = @($nodes)
    Topology = [ordered]@{
        Nodes = @(
            $nodes | ForEach-Object {
                [ordered]@{
                    Id = $_.Name
                    Hostname = $_.Hostname
                    IPAddress = $_.IPAddress
                    Role = $_.Role
                }
            }
        )
        Links = @($links)
        Note = "Links confirm TCP SSH reachability at build time; physical Wi-Fi/LAN topology is not independently discovered."
    }
    SecurityInventory = [ordered]@{
        SoftwareInventoryFile = $softwareFile
        SecurityAssessmentFile = $assessmentFile
    }
}

$digitalTwin |
    ConvertTo-Json -Depth 15 |
    Set-Content -Path $outputFile -Encoding UTF8

# ---------- PRESERVE HEALTH HISTORY ----------

if (-not (Test-Path $healthFile)) {
    "Timestamp,OverallHealth,MasterHealth,Slave1Health,Slave2Health" |
        Set-Content $healthFile -Encoding UTF8
}

$healthRow = @(
    $generatedAt,
    $overallHealth,
    ($nodes | Where-Object Name -eq "Master" | Select-Object -First 1).Health,
    ($nodes | Where-Object Name -eq "Slave1" | Select-Object -First 1).Health,
    ($nodes | Where-Object Name -eq "Slave2" | Select-Object -First 1).Health
)

$escaped = $healthRow | ForEach-Object {
    '"' + ([string]$_ -replace '"','""') + '"'
}

[System.IO.File]::AppendAllText(
    $healthFile,
    ($escaped -join ",") + [Environment]::NewLine
)

# ---------- SUMMARY ----------

Write-Host ""
Write-Host "======================================"
Write-Host "       NETTWIN DIGITAL TWIN V3"
Write-Host "======================================"
Write-Host "Generated at : $generatedAt"
Write-Host "Overall health: $overallHealth"
Write-Host "Node count    : $($nodes.Count)"

foreach ($node in $nodes) {
    Write-Host ""
    Write-Host "$($node.Name) [$($node.Hostname)]"
    Write-Host "  IP          : $($node.IPAddress)"
    Write-Host "  Connectivity: $($node.Connectivity.Status)"
    Write-Host "  SSH         : $($node.Connectivity.SSHStatus)"
    Write-Host "  Telemetry   : $($node.TelemetryStatus)"
    Write-Host "  Health      : $($node.Health)"
    Write-Host "  Health score: $($node.HealthScore)"
    Write-Host "  CPU         : $($node.Resources.CPU_Percent)"
    Write-Host "  RAM used %  : $($node.Resources.RAM_Used_Percent)"
    Write-Host "  Disk used % : $($node.Resources.Disk_Used_Percent)"
    Write-Host "  Open ports  : $($node.Network.ListeningPortCount)"
    Write-Host "  Security risk: $($node.Security.SecurityRisk)"
}

Write-Host ""
Write-Host "Digital Twin JSON: $outputFile"
Write-Host "Health history   : $healthFile"




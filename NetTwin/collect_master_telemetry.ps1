$ErrorActionPreference = "Stop"

$root = "C:\NetTwin"
$outFile = Join-Path $root "master_telemetry.csv"
$now = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

$cpu = (Get-CimInstance Win32_Processor |
    Measure-Object -Property LoadPercentage -Average).Average

$os = Get-CimInstance Win32_OperatingSystem
$ramTotal = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
$ramFree = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
$ramUsed = [math]::Round($ramTotal - $ramFree, 2)

$disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
$diskTotal = [math]::Round($disk.Size / 1GB, 2)
$diskFree = [math]::Round($disk.FreeSpace / 1GB, 2)

$adapter = Get-NetAdapter |
    Where-Object { $_.Name -eq "Wi-Fi" } |
    Select-Object -First 1

$firewallProfiles = Get-NetFirewallProfile
$firewallState = if (
    @($firewallProfiles | Where-Object { -not $_.Enabled }).Count -eq 0
) { "ENABLED" } else { "DISABLED" }

$defenderState = "UNKNOWN"
try {
    $defender = Get-MpComputerStatus
    if ($defender.RealTimeProtectionEnabled) {
        $defenderState = "ACTIVE"
    } else {
        $defenderState = "INACTIVE"
    }
} catch {}

$ports = @(
    Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty LocalPort -Unique |
        Sort-Object
) -join ";"

$ramUsedPercent = if ($ramTotal -gt 0) {
    [math]::Round(($ramUsed / $ramTotal) * 100, 2)
} else { 0 }

$diskUsedPercent = if ($diskTotal -gt 0) {
    [math]::Round((($diskTotal - $diskFree) / $diskTotal) * 100, 2)
} else { 0 }

# --- Network measurements ---
$stateFile = Join-Path $root "master_network_previous.json"
$nowUtc = [DateTime]::UtcNow
$stats = Get-NetAdapterStatistics -Name $adapter.Name -ErrorAction Stop

$receivedMbps = $null
$sentMbps = $null
$bandwidthMbps = $null
$utilizationPercent = $null
$sampleIntervalSeconds = $null
$receivedPacketErrors = $null
$outboundPacketErrors = $null

$previous = $null
if (Test-Path $stateFile) {
    try {
        $previous = Get-Content $stateFile -Raw | ConvertFrom-Json
    } catch {
        $previous = $null
    }
}

if ($null -ne $previous) {
    try {
        $previousTime = [DateTime]::Parse(
            [string]$previous.TimestampUtc
        ).ToUniversalTime()

        $interval = ($nowUtc - $previousTime).TotalSeconds

        if ($interval -gt 0) {
            $sampleIntervalSeconds = [math]::Round($interval, 2)

            $oldReceived = [double]$previous.ReceivedBytes
            $oldSent = [double]$previous.OutboundBytes
            $oldRxErrors = [double]$previous.ReceivedPacketErrors
            $oldTxErrors = [double]$previous.OutboundPacketErrors

            $newReceived = [double]$stats.ReceivedBytes
            $newSent = [double]$stats.OutboundBytes
            $newRxErrors = [double]$stats.ReceivedPacketErrors
            $newTxErrors = [double]$stats.OutboundPacketErrors

            if ($newReceived -ge $oldReceived) {
                $receivedMbps = [math]::Round(
                    (($newReceived - $oldReceived) * 8) /
                    ($interval * 1000000), 4
                )
            }

            if ($newSent -ge $oldSent) {
                $sentMbps = [math]::Round(
                    (($newSent - $oldSent) * 8) /
                    ($interval * 1000000), 4
                )
            }

            if ($null -ne $receivedMbps -and $null -ne $sentMbps) {
                $bandwidthMbps = [math]::Round(
                    $receivedMbps + $sentMbps, 4
                )
            }

            if ($newRxErrors -ge $oldRxErrors) {
                $receivedPacketErrors = [long](
                    $newRxErrors - $oldRxErrors
                )
            }

            if ($newTxErrors -ge $oldTxErrors) {
                $outboundPacketErrors = [long](
                    $newTxErrors - $oldTxErrors
                )
            }

            # Convert the adapter link speed to Mbps.
            $linkSpeedMbps = $null
            if ([string]$adapter.LinkSpeed -match
                '([\d.]+)\s*(Gbps|Mbps|Kbps)') {
                $speedValue = [double]$Matches[1]
                switch ($Matches[2]) {
                    'Gbps' { $linkSpeedMbps = $speedValue * 1000 }
                    'Mbps' { $linkSpeedMbps = $speedValue }
                    'Kbps' { $linkSpeedMbps = $speedValue / 1000 }
                }
            }

            if ($null -ne $bandwidthMbps -and
                $null -ne $linkSpeedMbps -and
                $linkSpeedMbps -gt 0) {
                $utilizationPercent = [math]::Round(
                    ($bandwidthMbps / $linkSpeedMbps) * 100, 2
                )
            }
        }
    } catch {
        Write-Warning "Could not calculate network deltas: $($_.Exception.Message)"
    }
}

# Save this sample so the next execution can calculate differences.
$state = [PSCustomObject]@{
    TimestampUtc = $nowUtc.ToString("o")
    ReceivedBytes = [string]$stats.ReceivedBytes
    OutboundBytes = [string]$stats.OutboundBytes
    ReceivedPacketErrors = [string]$stats.ReceivedPacketErrors
    OutboundPacketErrors = [string]$stats.OutboundPacketErrors
}
$state | ConvertTo-Json | Set-Content $stateFile -Encoding UTF8
# --- End network measurements ---
$row = [PSCustomObject]@{
    Timestamp = $now
    NODE = "Master"
    HOSTNAME = $env:COMPUTERNAME
    IP_ADDRESS = (
        Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias "Wi-Fi" `
            -ErrorAction SilentlyContinue |
        Where-Object {
            $_.IPAddress -notlike "169.254.*" -and
            $_.IPAddress -ne "127.0.0.1"
        } |
        Select-Object -First 1 -ExpandProperty IPAddress
    )
    CPU = $cpu
    RAM_TOTAL_GB = $ramTotal
    RAM_FREE_GB = $ramFree
    RAM_USED_GB = $ramUsed
    RAM_USED_PERCENT = $ramUsedPercent
    DISK_TOTAL_GB = $diskTotal
    DISK_FREE_GB = $diskFree
    DISK_USED_PERCENT = $diskUsedPercent
    NETWORK = $adapter.Name
    LINK_SPEED = [string]$adapter.LinkSpeed
    RECEIVED_MBPS = $receivedMbps
    ADAPTER_STATUS = [string]$adapter.Status
    SENT_MBPS = $sentMbps
    BANDWIDTH_MBPS = $bandwidthMbps
    NETWORK_UTILIZATION_PERCENT = $utilizationPercent
    SAMPLE_INTERVAL_SECONDS = $sampleIntervalSeconds
    RECEIVED_PACKET_ERRORS = $receivedPacketErrors
    OUTBOUND_PACKET_ERRORS = $outboundPacketErrors
    LISTENING_PORTS = $ports
    FIREWALL = $firewallState
    DEFENDER_REALTIME = $defenderState
}

if (Test-Path $outFile) {
    $row | Export-Csv $outFile -NoTypeInformation -Append
} else {
    $row | Export-Csv $outFile -NoTypeInformation
}

$row | Format-List
Write-Host "Master telemetry saved to $outFile"




